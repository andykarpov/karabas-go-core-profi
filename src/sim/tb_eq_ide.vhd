-------------------------------------------------------------------------------
-- ide_controller against the version before (sim/ref/ide_controller_ref.vhd), whose high byte register was a
-- flip-flop clocked by the decoded write strobes (XST built it with the Profi strobe only).
--
-- Random IO cycles of the CPU (IORQ_n with RD_n or WR_n, held while IDE_BUSY, as the wait of profi.vhd does) to
-- the Profi IDE ports (#xxAB, #xxCB, #xxEB) and other ports, random data from the IDE device on reads.
--   part 1, NEMOIDE_EN = 0: every output equal to the old one, on every falling clock edge;
--   part 2, NEMOIDE_EN = 1, cycles to the Nemo ports too: every output equal except IDE_D(15:8), and on every
--            write cycle of the Nemo data port IDE_D(15:8) carries the byte last written to #11 or #xxCB (the old
--            version did not take #11).
-- Prints "tb_eq_ide: <n> errors".
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_eq_ide is
generic (
	CYCLES		: integer := 20000
);
end tb_eq_ide;

architecture sim of tb_eq_ide is

constant T : time := 35556 ps;

signal clk : std_logic := '0';
signal done : boolean := false;
signal reset : std_logic := '1';
signal nemo_en : std_logic := '0';
signal a : std_logic_vector(15 downto 0) := (others => '0');
signal di : std_logic_vector(7 downto 0) := (others => '0');
signal iorq_n, rd_n, wr_n : std_logic := '1';
signal dev_d : std_logic_vector(15 downto 0) := (others => '0');
signal part2 : boolean := false;
signal nemo_hi : std_logic_vector(7 downto 0) := (others => 'U');

signal do_r, do_n : std_logic_vector(7 downto 0);
signal act_r, act_n, oe_r, oe_n, rdn_r, rdn_n, wrn_r, wrn_n, rst_r, rst_n, busy_r, busy_n : std_logic;
signal ia_r, ia_n : std_logic_vector(2 downto 0);
signal cs_r, cs_n : std_logic_vector(1 downto 0);
signal d_r, d_n : std_logic_vector(15 downto 0);

begin

clk <= not clk after T / 2; -- std.env.stop ends the run

-- the IDE device drives the data bus while IDE_RD_N is low
d_r <= dev_d when rdn_r = '0' else (others => 'Z');
d_n <= dev_d when rdn_n = '0' else (others => 'Z');

U_REF: entity work.ide_controller_ref
port map (
	CLK => clk, RESET => reset, PROFIDE_EN => '1', NEMOIDE_EN => nemo_en, A => a, DI => di, IORQ_N => iorq_n,
	MREQ_N => '1', M1_N => '1', RD_N => rd_n, WR_N => wr_n, CPM => '0', ROM14 => '0', DOS => '1', HDD_OFF => '0',
	DO => do_r, ACTIVE => act_r, OE_N => oe_r, IDE_A => ia_r, IDE_D => d_r, IDE_CS_N => cs_r, IDE_RD_N => rdn_r,
	IDE_WR_N => wrn_r, IDE_RESET_N => rst_r, IDE_BUSY => busy_r
);

U_NEW: entity work.ide_controller
port map (
	CLK => clk, RESET => reset, PROFIDE_EN => '1', NEMOIDE_EN => nemo_en, A => a, DI => di, IORQ_N => iorq_n,
	MREQ_N => '1', M1_N => '1', RD_N => rd_n, WR_N => wr_n, CPM => '0', ROM14 => '0', DOS => '1', HDD_OFF => '0',
	DO => do_n, ACTIVE => act_n, OE_N => oe_n, IDE_A => ia_n, IDE_D => d_n, IDE_CS_N => cs_n, IDE_RD_N => rdn_n,
	IDE_WR_N => wrn_n, IDE_RESET_N => rst_n, IDE_BUSY => busy_n
);

-- IO cycles: the address and data change on the rising edge, the strobe goes low on a falling edge for 2..9
-- clocks and stays low while IDE_BUSY
process
	variable r : unsigned(31 downto 0) := x"2545F491";
	procedure rnd is
	begin
		for k in 0 to 31 loop
			r := r(30 downto 0) & (r(31) xor r(21) xor r(1) xor r(0));
		end loop;
	end procedure;
	variable lo : std_logic_vector(7 downto 0);
	variable n : integer;
	type lo_t is array (0 to 15) of std_logic_vector(7 downto 0);
	constant LOS : lo_t := (x"AB", x"CB", x"EB", x"CB", x"EB", x"10", x"30", x"50", x"70", x"90", x"B0", x"D0",
	                        x"F0", x"C8", x"11", x"FE");
begin
	for i in 1 to 8 loop wait until rising_edge(clk); end loop;
	reset <= '0';
	for c in 0 to CYCLES - 1 loop
		if c = CYCLES / 2 then
			nemo_en <= '1';
			part2 <= true;
		end if;
		rnd;
		wait until rising_edge(clk);
		lo := LOS(to_integer(r(3 downto 0)));
		if r(6 downto 4) = "000" then
			a <= x"FF" & lo;                                    -- #FFCB / #FFEB: Profi high byte
		else
			a <= "00000" & std_logic_vector(r(10 downto 8)) & lo; -- register 0..7
		end if;
		di <= std_logic_vector(r(23 downto 16));
		dev_d <= std_logic_vector(r(31 downto 16)) xor std_logic_vector(r(15 downto 0));
		wait until falling_edge(clk);
		iorq_n <= '0';
		if r(7) = '1' then wr_n <= '0'; else rd_n <= '0'; end if;
		n := 2 + to_integer(r(14 downto 12));
		for k in 1 to n loop wait until falling_edge(clk); end loop;
		while busy_r = '1' or busy_n = '1' loop wait until falling_edge(clk); end loop;
		iorq_n <= '1'; rd_n <= '1'; wr_n <= '1';
		for k in 0 to to_integer(r(25 downto 24)) loop wait until falling_edge(clk); end loop;
	end loop;
	done <= true;
	wait;
end process;

-- the byte last written to a high byte port: Nemo #11, Profi #xxCB
process (clk)
begin
	if falling_edge(clk) then
		if iorq_n = '0' and wr_n = '0' and ((nemo_en = '1' and a(7 downto 0) = x"11") or a(7 downto 0) = x"CB") then
			nemo_hi <= di;
		end if;
	end if;
end process;

process (clk)
	variable errors : integer := 0;
	variable n_nemo_wr, n_cycles : integer := 0;
	variable wrn_d : std_logic := '1';
	procedure check(name : string; got, exp : std_logic_vector) is
	begin
		if got /= exp then
			errors := errors + 1;
			if errors <= 10 then
				report "tb_eq_ide: " & name & " differs at " & time'image(now) severity error;
			end if;
		end if;
	end procedure;
begin
	if falling_edge(clk) then
		check("DO", do_n, do_r);
		check("OE_N", (0 => oe_n), (0 => oe_r));
		check("ACTIVE", (0 => act_n), (0 => act_r));
		check("IDE_A", ia_n, ia_r);
		check("IDE_CS_N", cs_n, cs_r);
		check("IDE_RD_N", (0 => rdn_n), (0 => rdn_r));
		check("IDE_WR_N", (0 => wrn_n), (0 => wrn_r));
		check("IDE_RESET_N", (0 => rst_n), (0 => rst_r));
		check("IDE_BUSY", (0 => busy_n), (0 => busy_r));
		check("IDE_D(7:0)", d_n(7 downto 0), d_r(7 downto 0));
		if not part2 then
			check("IDE_D(15:8)", d_n(15 downto 8), d_r(15 downto 8));
		end if;
		-- a write cycle on the IDE bus to the Nemo data register (CS0, register 0)
		if part2 and wrn_n = '0' and wrn_d = '1' and a(7 downto 0) = x"10" then
			n_nemo_wr := n_nemo_wr + 1;
			check("IDE_D(15:8) of a Nemo write", d_n(15 downto 8), nemo_hi);
		end if;
		wrn_d := wrn_n;
		if done then
			report "tb_eq_ide: Nemo data writes checked " & integer'image(n_nemo_wr);
			report "tb_eq_ide: " & integer'image(errors) & " errors";
			std.env.stop;
		end if;
	end if;
end process;

end sim;
