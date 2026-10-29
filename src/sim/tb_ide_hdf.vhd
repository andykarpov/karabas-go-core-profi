-------------------------------------------------------------------------------
-- The IDE path of profi.vhd: ide_controller -> ide_mux -> the CF card / hdf_ata -> img_sdc -> the mcu.
--
-- The CPU does IO cycles on the Profi IDE ports (#xxEB write, #xxCB read, #FFCB / #FFEB the high byte, held while
-- IDE_BUSY as the wait of profi.vhd does). The mcu is a model of the file mounter of the firmware (IMG_LBA,
-- IMG_SEC, the sector bytes with their sum, IMG_BUF_BANK / IMG_BUF_DATA of a write, the result), the image a
-- function of the LBA and the byte, the sectors written kept aside. The CF card is a model with the status
-- register and the device / head register, the data of a write taken one clock after /WR goes high.
--   part 1, HDD = CF card: the card answers as device 0, device 1 (no image) reads 0, and DEV back to 0 reaches
--           the card; a data word written to the card;
--   part 2, HDD = Image (slot 4): no strobe on the card; IDENTIFY (the geometry of the image size), READ SECTORS
--           of 2 in LBA, WRITE SECTORS and reading it back, READ SECTORS in CHS; the byte order (the low byte of
--           a word is the first of the sector).
-- Prints "tb_ide_hdf: <n> errors".
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_ide_hdf is
end tb_ide_hdf;

architecture sim of tb_ide_hdf is

constant T : time := 35556 ps;
constant SECTORS : integer := 20160; -- 20 cylinders of 16 heads, 63 sectors

signal clk : std_logic := '0';
signal reset : std_logic := '1';
signal cf : std_logic := '1';

-- CPU
signal a : std_logic_vector(15 downto 0) := (others => '0');
signal di : std_logic_vector(7 downto 0) := (others => '0');
signal do : std_logic_vector(7 downto 0);
signal iorq_n, rd_n, wr_n : std_logic := '1';
signal oe_n, active, busy : std_logic;

-- ide_controller <-> ide_mux
signal ide_a : std_logic_vector(2 downto 0);
signal ide_d : std_logic_vector(15 downto 0);
signal ide_cs_n : std_logic_vector(1 downto 0);
signal ide_rd_n, ide_wr_n, ide_reset_n, ata_rst : std_logic;

-- the CF card
signal wa : std_logic_vector(2 downto 0);
signal wd : std_logic_vector(15 downto 0);
signal wcs_n : std_logic_vector(1 downto 0);
signal wrd_n, wwr_n, wreset_n : std_logic;
signal cf_head : std_logic_vector(7 downto 0) := x"00";
signal cf_word : std_logic_vector(15 downto 0) := (others => '0');
signal cf_strobes : integer := 0;

-- hdf_ata
signal hdf_dev, hdf_dev1_here, hdf_led : std_logic;
signal hdf_dout : std_logic_vector(15 downto 0);
signal hdf_rd, hdf_wr : std_logic_vector(1 downto 0);
signal hdf_sector : std_logic_vector(31 downto 0);
signal hdf_out_data : std_logic_vector(7 downto 0);
signal hdf_own, hdf_dev0_en, hdf_sdc_busy, hdf_sdc_done, hdf_sdc_strobe : std_logic;

-- img_sdc
signal img_mounted : std_logic_vector(7 downto 0) := (others => '0');
signal img_size : std_logic_vector(63 downto 0) := (others => '0');
signal img_data_wr : std_logic := '0';
signal img_data_addr : std_logic_vector(8 downto 0) := (others => '0');
signal img_data : std_logic_vector(7 downto 0) := (others => '0');
signal img_result_wr : std_logic := '0';
signal img_result : std_logic_vector(7 downto 0) := (others => '0');
signal img_sum : std_logic_vector(15 downto 0) := (others => '0');
signal img_q_wr : std_logic;
signal img_q_di : std_logic_vector(23 downto 0);
signal img_q_ack : std_logic := '0';
signal sdc_img_mounted : std_logic_vector(7 downto 0);
signal sdc_img_size : std_logic_vector(63 downto 0);
signal sdc_rd, sdc_wr : std_logic_vector(7 downto 0);
signal sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe, sdc_active : std_logic;
signal sdc_slot : std_logic_vector(2 downto 0);
signal sdc_byte_addr : std_logic_vector(8 downto 0);
signal sdc_byte_in_data : std_logic_vector(7 downto 0);

signal errors : integer := 0;
signal err_req : boolean := false;

-- the image: a byte of a sector not written
function img_byte(lba : integer; i : integer) return std_logic_vector is
	variable l : unsigned(31 downto 0) := to_unsigned(lba, 32);
	variable n : unsigned(8 downto 0) := to_unsigned(i, 9);
begin
	return std_logic_vector(l(7 downto 0) xor l(15 downto 8) xor n(7 downto 0) xor (n(8) & "0101010"));
end function;

-- the data written by the CPU
function wr_byte(i : integer) return std_logic_vector is
begin
	return std_logic_vector(to_unsigned((i * 37 + 11) mod 256, 8));
end function;

begin

clk <= not clk after T / 2;

U_IDE: entity work.ide_controller
port map (
	CLK => clk, RESET => reset, PROFIDE_EN => '1', NEMOIDE_EN => '1', A => a, DI => di, IORQ_N => iorq_n,
	MREQ_N => '1', M1_N => '1', RD_N => rd_n, WR_N => wr_n, CPM => '0', ROM14 => '0', DOS => '1', HDD_OFF => '0',
	DO => do, ACTIVE => active, OE_N => oe_n, IDE_A => ide_a, IDE_D => ide_d, IDE_CS_N => ide_cs_n,
	IDE_RD_N => ide_rd_n, IDE_WR_N => ide_wr_n, IDE_RESET_N => ide_reset_n, IDE_BUSY => busy
);

U_MUX: entity work.ide_mux
port map (
	CLK => clk, CF => cf, HDF_DEV => hdf_dev, HDF_DOUT => hdf_dout,
	IDE_A => ide_a, IDE_D => ide_d, IDE_CS_N => ide_cs_n, IDE_RD_N => ide_rd_n, IDE_WR_N => ide_wr_n,
	IDE_RESET_N => ide_reset_n,
	WA => wa, WD => wd, WCS_N => wcs_n, WRD_N => wrd_n, WWR_N => wwr_n, WRESET_N => wreset_n
);

-- as profi.vhd
ata_rst <= not ide_reset_n;
hdf_own <= '1' when sdc_slot(2 downto 1) = "10" else '0';
sdc_rd <= "00" & hdf_rd & "0000";
sdc_wr <= "00" & hdf_wr & "0000";
hdf_dev0_en <= not cf;
hdf_sdc_busy <= sdc_busy and hdf_own;
hdf_sdc_done <= sdc_done and hdf_own;
hdf_sdc_strobe <= sdc_byte_in_strobe and hdf_own;

U_HDF: entity work.hdf_ata
port map (
	clk => clk, reset => reset, ata_reset => ata_rst, dev0_en => hdf_dev0_en, dev => hdf_dev, dev1_here => hdf_dev1_here,
	a => ide_a, cs_n => ide_cs_n, rd_n => ide_rd_n, wr_n => ide_wr_n, din => ide_d, dout => hdf_dout,
	img_mounted => sdc_img_mounted(5 downto 4), img_size => sdc_img_size,
	sdc_rd => hdf_rd, sdc_wr => hdf_wr, sdc_sector => hdf_sector,
	sdc_busy => hdf_sdc_busy, sdc_done => hdf_sdc_done, sdc_error => sdc_error,
	sdc_byte_in_strobe => hdf_sdc_strobe, sdc_byte_addr => sdc_byte_addr,
	sdc_byte_in_data => sdc_byte_in_data, sdc_byte_out_data => hdf_out_data, led => hdf_led
);

U_SDC: entity work.img_sdc
generic map (OUT_LATENCY => 3, TIMEOUT => 5600000, RETRIES => 3)
port map (
	clk => clk, reset => reset,
	img_mounted => img_mounted, img_size => img_size, img_data_wr => img_data_wr, img_data_addr => img_data_addr,
	img_data => img_data, img_result_wr => img_result_wr, img_result => img_result, img_sum => img_sum,
	img_q_wr => img_q_wr, img_q_di => img_q_di, img_q_ack => img_q_ack,
	sdc_img_mounted => sdc_img_mounted, sdc_img_size => sdc_img_size, sdc_rd => sdc_rd, sdc_wr => sdc_wr,
	sdc_sector => hdf_sector, sdc_busy => sdc_busy, sdc_done => sdc_done, sdc_error => sdc_error,
	sdc_slot => sdc_slot, sdc_byte_in_strobe => sdc_byte_in_strobe, sdc_byte_addr => sdc_byte_addr,
	sdc_byte_in_data => sdc_byte_in_data, sdc_byte_out_data => hdf_out_data, active => sdc_active
);

-- the CF card: device 0 only, status #50 while DEV = 0, data taken one clock after /WR goes high
wd <= x"00" & x"50" when wrd_n = '0' and wcs_n = "10" and wa = "111" and cf_head(4) = '0' else
      x"00" & cf_head when wrd_n = '0' and wcs_n = "10" and wa = "110" else
      x"0000" when wrd_n = '0' and wcs_n = "10" else
      (others => 'Z');

process (clk)
	variable wwr_d, wrd_d : std_logic := '1';
	variable wa_d : std_logic_vector(2 downto 0);
begin
	if rising_edge(clk) then
		if wwr_d = '0' and wwr_n = '1' then
			if wa_d = "110" then
				cf_head <= wd(7 downto 0);
			elsif wa_d = "000" then
				cf_word <= wd;
			end if;
		end if;
		if (wwr_n = '0' and wwr_d = '1') or (wrd_n = '0' and wrd_d = '1') then
			cf_strobes <= cf_strobes + 1;
		end if;
		wwr_d := wwr_n;
		wrd_d := wrd_n;
		wa_d := wa;
	end if;
end process;

-- the mcu: the file mounter
process (clk)
	type sec_t is array (0 to 511) of std_logic_vector(7 downto 0);
	type store_t is array (0 to 7) of sec_t;
	type lbas_t is array (0 to 7) of integer;
	variable store : store_t;
	variable lbas : lbas_t := (others => -1);
	variable n_store : integer := 0;
	variable lba : unsigned(31 downto 0) := (others => '0');
	variable buf : sec_t;
	variable bank : integer := 0;
	variable sending : integer := -1; -- the byte of a read to send, -1 none
	variable cur : integer;
	variable sum : unsigned(15 downto 0);
	variable cmd : std_logic_vector(7 downto 0);
	variable k : integer;

	impure function rd_byte(l : integer; i : integer) return std_logic_vector is
	begin
		for s in 0 to 7 loop
			if lbas(s) = l then
				return store(s)(i);
			end if;
		end loop;
		return img_byte(l, i);
	end function;
begin
	if rising_edge(clk) then
		img_data_wr <= '0';
		img_result_wr <= '0';
		img_q_ack <= '0';
		if img_q_wr = '1' and img_q_ack = '0' then
			img_q_ack <= '1';
			cmd := img_q_di(23 downto 16);
			if cmd = x"42" then -- IMG_LBA
				k := to_integer(unsigned(img_q_di(9 downto 8)));
				lba(k * 8 + 7 downto k * 8) := unsigned(img_q_di(7 downto 0));
			elsif cmd = x"43" then -- IMG_SEC
				cur := to_integer(lba);
				if img_q_di(7 downto 0) = x"01" then
					sending := 0;
					sum := (others => '0');
				end if;
			elsif cmd = x"44" then -- IMG_BUF_BANK
				if img_q_di(15 downto 8) = x"00" then
					bank := to_integer(unsigned(img_q_di(0 downto 0)));
				elsif img_q_di(15 downto 8) = x"11" then -- the sum, its high byte last: the write is done
					k := -1;
					for s in 0 to 7 loop
						if lbas(s) = cur then k := s; end if;
					end loop;
					if k < 0 then
						k := n_store mod 8;
						n_store := n_store + 1;
					end if;
					lbas(k) := cur;
					store(k) := buf;
					img_result <= x"01";
					img_result_wr <= '1';
				end if;
			elsif cmd = x"45" then -- IMG_BUF_DATA
				buf(bank * 256 + to_integer(unsigned(img_q_di(15 downto 8)))) := img_q_di(7 downto 0);
			end if;
		end if;
		if sending >= 0 and sending < 512 then
			img_data_wr <= '1';
			img_data_addr <= std_logic_vector(to_unsigned(sending, 9));
			img_data <= rd_byte(cur, sending);
			sum := sum + unsigned(rd_byte(cur, sending));
			sending := sending + 1;
		elsif sending = 512 then
			img_sum <= std_logic_vector(sum);
			img_result <= x"01";
			img_result_wr <= '1';
			sending := -1;
		end if;
	end if;
end process;

-- the CPU
process
	procedure io(addr : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0); wr : boolean;
	             q : out std_logic_vector(7 downto 0)) is
	begin
		wait until rising_edge(clk);
		a <= addr;
		di <= data;
		wait until falling_edge(clk);
		iorq_n <= '0';
		if wr then wr_n <= '0'; else rd_n <= '0'; end if;
		for k in 1 to 3 loop wait until falling_edge(clk); end loop;
		while busy = '1' loop wait until falling_edge(clk); end loop;
		q := do;
		iorq_n <= '1'; rd_n <= '1'; wr_n <= '1';
		wait until falling_edge(clk);
	end procedure;

	procedure outp(addr : std_logic_vector(15 downto 0); data : std_logic_vector(7 downto 0)) is
		variable q : std_logic_vector(7 downto 0);
	begin
		io(addr, data, true, q);
	end procedure;

	procedure inp(addr : std_logic_vector(15 downto 0); q : out std_logic_vector(7 downto 0)) is
	begin
		io(addr, x"00", false, q);
	end procedure;

	-- task file register n
	procedure reg_wr(n : integer; data : std_logic_vector(7 downto 0)) is
	begin
		outp(std_logic_vector(to_unsigned(n, 8)) & x"EB", data);
	end procedure;

	procedure reg_rd(n : integer; q : out std_logic_vector(7 downto 0)) is
	begin
		inp(std_logic_vector(to_unsigned(n, 8)) & x"CB", q);
	end procedure;

	procedure data_rd(w : out std_logic_vector(15 downto 0)) is
		variable lo, hi : std_logic_vector(7 downto 0);
	begin
		inp(x"00CB", lo);
		inp(x"FFEB", hi);
		w := hi & lo;
	end procedure;

	procedure data_wr(w : std_logic_vector(15 downto 0)) is
	begin
		outp(x"FFCB", w(15 downto 8));
		outp(x"00EB", w(7 downto 0));
	end procedure;

	procedure fail(msg : string) is
	begin
		report "tb_ide_hdf: " & msg severity error;
		errors <= errors + 1;
		wait for 0 ns;
	end procedure;

	procedure expect(name : string; got, exp : std_logic_vector) is
	begin
		if got /= exp then
			fail(name & " is " & integer'image(to_integer(unsigned(got))) & ", expected " &
			     integer'image(to_integer(unsigned(exp))));
		end if;
	end procedure;

	-- status until not BSY and (DRQ when drq)
	procedure wait_ready(drq : boolean; s : out std_logic_vector(7 downto 0)) is
		variable st : std_logic_vector(7 downto 0);
	begin
		for k in 1 to 20000 loop
			reg_rd(7, st);
			if st(7) = '0' and (not drq or st(3) = '1') then
				s := st;
				return;
			end if;
		end loop;
		fail("timeout, status " & integer'image(to_integer(unsigned(st))));
		s := st;
	end procedure;

	procedure set_lba(lba : integer; count : integer) is
		variable l : std_logic_vector(27 downto 0) := std_logic_vector(to_unsigned(lba, 28));
	begin
		reg_wr(6, x"E" & l(27 downto 24));
		reg_wr(5, l(23 downto 16));
		reg_wr(4, l(15 downto 8));
		reg_wr(3, l(7 downto 0));
		reg_wr(2, std_logic_vector(to_unsigned(count, 8)));
	end procedure;

	-- the sector of the data register against the image or the written data
	procedure check_sector(name : string; lba : integer; written : boolean) is
		variable w : std_logic_vector(15 downto 0);
		variable s : std_logic_vector(7 downto 0);
		variable lo, hi : std_logic_vector(7 downto 0);
		variable bad : integer := 0;
	begin
		wait_ready(true, s);
		for k in 0 to 255 loop
			data_rd(w);
			if written then
				lo := wr_byte(2 * k); hi := wr_byte(2 * k + 1);
			else
				lo := img_byte(lba, 2 * k); hi := img_byte(lba, 2 * k + 1);
			end if;
			if w /= hi & lo then
				bad := bad + 1;
				if bad <= 3 then
					fail(name & " word " & integer'image(k) & " is " & integer'image(to_integer(unsigned(w))) &
					     ", expected " & integer'image(to_integer(unsigned(hi & lo))));
				end if;
			end if;
		end loop;
	end procedure;

	variable s : std_logic_vector(7 downto 0);
	variable w : std_logic_vector(15 downto 0);
	variable n : integer;
begin
	for i in 1 to 8 loop wait until rising_edge(clk); end loop;
	reset <= '0';
	for i in 1 to 8 loop wait until rising_edge(clk); end loop;

	------------ part 1: HDD = CF card ------------
	cf <= '1';
	reg_wr(6, x"A0");
	reg_rd(7, s);
	expect("CF: device 0 status", s, x"50");
	reg_wr(6, x"B0");
	reg_rd(7, s);
	expect("CF: device 1 (no image) status", s, x"00");
	expect("CF: device / head on the card for DEV 1", cf_head, x"B0");
	reg_wr(6, x"A0");
	expect("CF: device / head on the card back to DEV 0", cf_head, x"A0");
	reg_rd(7, s);
	expect("CF: device 0 status again", s, x"50");
	data_wr(x"1234");
	expect("CF: data word written (held after /WR)", cf_word, x"1234");

	------------ part 2: HDD = Image ------------
	cf <= '0';
	wait until rising_edge(clk);
	n := cf_strobes;
	img_size <= std_logic_vector(to_unsigned(SECTORS, 55)) & "000000000";
	img_mounted <= x"10";
	wait until rising_edge(clk);
	img_mounted <= x"00";
	reg_wr(6, x"A0");
	wait_ready(false, s);
	expect("image: status after the mount", s, x"50");

	-- IDENTIFY
	reg_wr(7, x"EC");
	wait_ready(true, s);
	for k in 0 to 255 loop
		data_rd(w);
		case k is
			when 0 => expect("IDENTIFY word 0", w, x"0040");
			when 1 => expect("IDENTIFY cylinders", w, std_logic_vector(to_unsigned(SECTORS / (16 * 63), 16)));
			when 3 => expect("IDENTIFY heads", w, x"0010");
			when 6 => expect("IDENTIFY sectors", w, x"003F");
			when 27 => expect("IDENTIFY model ""KA""", w, x"4B41");
			when 60 => expect("IDENTIFY LBA sectors", w, std_logic_vector(to_unsigned(SECTORS, 16)));
			when others => null;
		end case;
	end loop;
	wait_ready(false, s);
	expect("IDENTIFY end status", s, x"50");

	-- READ SECTORS, LBA 1000, 2 sectors
	set_lba(1000, 2);
	reg_wr(7, x"20");
	check_sector("READ LBA 1000", 1000, false);
	check_sector("READ LBA 1001", 1001, false);
	wait_ready(false, s);
	expect("READ end status", s, x"50");

	-- WRITE SECTORS, LBA 1001, and read it back
	set_lba(1001, 1);
	reg_wr(7, x"30");
	wait_ready(true, s);
	for k in 0 to 255 loop
		data_wr(wr_byte(2 * k + 1) & wr_byte(2 * k));
	end loop;
	wait_ready(false, s);
	expect("WRITE end status", s, x"50");
	set_lba(1000, 2);
	reg_wr(7, x"20");
	check_sector("READ LBA 1000 after the write", 1000, false);
	check_sector("READ LBA 1001 written", 1001, true);
	wait_ready(false, s);

	-- READ SECTORS, CHS: cylinder 1, head 2, sector 3 = LBA (1 * 16 + 2) * 63 + 2
	reg_wr(6, x"A2");
	reg_wr(5, x"00");
	reg_wr(4, x"01");
	reg_wr(3, x"03");
	reg_wr(2, x"01");
	reg_wr(7, x"20");
	check_sector("READ CHS 1/2/3", 1136, false);
	wait_ready(false, s);
	expect("READ CHS end status", s, x"50");

	if cf_strobes /= n then
		fail("image: strobes on the CF card " & integer'image(cf_strobes - n));
	end if;

	wait until rising_edge(clk);
	report "tb_ide_hdf: " & integer'image(errors) & " errors";
	assert false report "tb_ide_hdf: finished" severity failure;
	wait;
end process;

end sim;
