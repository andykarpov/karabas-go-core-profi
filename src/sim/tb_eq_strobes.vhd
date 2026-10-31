-------------------------------------------------------------------------------
-- strobe_reg and divmmc_map against the flip-flops clocked by CPU strobes they replaced (sim/ref).
--
-- A T80s (as in profi.vhd) runs random code (random bytes, one in 8 places an instruction that jumps to the
-- DivMMC map addresses, #3Dxx, #1FF8, or does IO at #FE, #FD) with the clock enables of clock.vhd in
-- every turbo mode, random WAIT_n, INT_n (IM 1/2 to #0038 and vectors), NMI_n and a reset every RESET_EVERY
-- clocks (the memory is filled again then). Compared on every falling clk edge (the values the logic on clk
-- takes at the next rising edge):
--   divmmc_map:            MAPCOND and AUTOMAP equal to the old ones
--   strobe_reg (fd_port):  Q equal to the old Q one clock before (it changes one clock later by design)
--   strobe_reg (port #FE): the same, EN = cs_xxfe of profi.vhd (IORQ_n low, A0 low)
-- Prints "tb_eq_strobes: <n> errors" and how often each output changed.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_eq_strobes is
generic (
	CLOCKS		: integer := 2000000;
	RESET_EVERY	: integer := 20000;
	SEED			: integer := 1
);
end tb_eq_strobes;

architecture sim of tb_eq_strobes is

constant T : time := 35556 ps; -- 28.125 MHz

type mem_t is array (0 to 65535) of std_logic_vector(7 downto 0);
signal mem : mem_t;

signal clk : std_logic := '0';
signal cyc : integer := 0;
signal done : boolean := false;

signal lfsr : unsigned(31 downto 0) := to_unsigned(16#1234567# + SEED * 7919, 32);

-- clock enables as clock.vhd
signal ena_cnt : unsigned(5 downto 0) := (others => '0');
signal ena_cpu : std_logic := '0';
signal turbo : std_logic_vector(1 downto 0) := "00";

-- cpu
signal reset, cpu_reset_n : std_logic := '1';
signal cpu_wait_n, cpu_int_n, cpu_nmi_n : std_logic := '1';
signal cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n : std_logic;
signal cpu_a : std_logic_vector(15 downto 0);
signal cpu_di, cpu_do, io_data : std_logic_vector(7 downto 0);

signal divmmc_en : std_logic := '1';
signal fd_sel, cs_xxfe : std_logic;

-- outputs
signal mapcond_new, automap_new, mapcond_ref, automap_ref : std_logic;
signal fd_new, fd_ref : std_logic_vector(0 downto 0);
signal fe_new, fe_ref : std_logic_vector(7 downto 0);

begin

clk <= not clk after T / 2; -- std.env.stop ends the run

U_CPU: entity work.T80s
port map (
	RESET_n => cpu_reset_n, CLK => clk, CEN => ena_cpu, WAIT_n => cpu_wait_n, INT_n => cpu_int_n,
	NMI_n => cpu_nmi_n, BUSRQ_n => '1', M1_n => cpu_m1_n, MREQ_n => cpu_mreq_n, IORQ_n => cpu_iorq_n,
	RD_n => cpu_rd_n, WR_n => cpu_wr_n, RFSH_n => cpu_rfsh_n, HALT_n => open, BUSAK_n => open, OUT0 => '1',
	A => cpu_a, DI => cpu_di, DO => cpu_do
);

-- the data bus: memory, a random byte for IO reads and the interrupt vector
cpu_di <= mem(to_integer(unsigned(cpu_a))) when cpu_mreq_n = '0' and cpu_rd_n = '0' else
			 io_data;

-- as profi.vhd
fd_sel <= '0' when (cpu_do = x"DB" or cpu_do = x"D3" or cpu_di = x"DB" or cpu_di = x"D3") else '1';
cs_xxfe <= '1' when cpu_iorq_n = '0' and cpu_a(0) = '0' else '0';

U_DIV_NEW: entity work.divmmc_map
port map (
	CLK => clk, RESET => reset, DIVMMC_EN => divmmc_en, A => cpu_a, M1_N => cpu_m1_n, MREQ_N => cpu_mreq_n,
	MAPCOND => mapcond_new, AUTOMAP => automap_new
);

U_DIV_REF: entity work.divmmc_map_ref
port map (
	I_RESET => reset, I_DIVMMC_EN => divmmc_en, I_A => cpu_a, I_M1_N => cpu_m1_n, I_MREQ_N => cpu_mreq_n,
	O_MAPCOND => mapcond_ref, O_AUTOMAP => automap_ref
);

U_FD_NEW: entity work.strobe_reg
generic map (W => 1, INIT => '1')
port map (CLK => clk, RESET => reset, STROBE_N => cpu_m1_n, D(0) => fd_sel, Q => fd_new);

U_FD_REF: entity work.strobe_reg_ref
generic map (W => 1, INIT => '1')
port map (RESET => reset, STROBE_N => cpu_m1_n, D(0) => fd_sel, Q => fd_ref);

U_FE_NEW: entity work.strobe_reg
generic map (W => 8)
port map (CLK => clk, STROBE_N => cpu_wr_n, EN => cs_xxfe, D => cpu_do, Q => fe_new);

U_FE_REF: entity work.strobe_reg_ref
generic map (W => 8)
port map (STROBE_N => cpu_wr_n, EN => cs_xxfe, D => cpu_do, Q => fe_ref);

-- clock enables (clock.vhd): the counter on the falling edge, ENA_CPU on the rising edge
process (clk)
begin
	if falling_edge(clk) then
		ena_cnt <= ena_cnt + 1;
	end if;
end process;

-- stimulus, changed on the rising edge like the registers of profi.vhd
process (clk)
	variable r : unsigned(31 downto 0);
	variable x : unsigned(31 downto 0);
	variable phase : integer;
	variable i : integer;
	variable m : mem_t;
begin
	if rising_edge(clk) then
		r := lfsr;
		for k in 0 to 31 loop
			r := r(30 downto 0) & (r(31) xor r(21) xor r(1) xor r(0));
		end loop;
		lfsr <= r;
		cyc <= cyc + 1;

		-- ENA_CPU of clock.vhd
		case turbo is
			when "11" => ena_cpu <= '1';
			when "10" => ena_cpu <= ena_cnt(0);
			when "01" => ena_cpu <= ena_cnt(1) and ena_cnt(0);
			when others => ena_cpu <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		end case;

		-- a reset every RESET_EVERY clocks, the turbo mode changes with it, the memory is filled again
		phase := cyc mod RESET_EVERY;
		if phase = 0 then
			reset <= '1';
			turbo <= std_logic_vector(to_unsigned((cyc / RESET_EVERY) mod 4, 2));
			x := r;
			i := 0;
			while i < 65536 loop
				for k in 0 to 7 loop
					x := x(30 downto 0) & (x(31) xor x(21) xor x(1) xor x(0));
				end loop;
				-- random bytes, one in 8 of them starts an instruction the outputs depend on
				if x(10 downto 8) = "000" and i < 65533 then
					case to_integer(x(15 downto 12)) is
						when 0 | 1 => m(i) := x"C3"; m(i+1) := std_logic_vector(x(7 downto 0)); m(i+2) := x"3D"; -- JP #3Dxx
						when 2 => m(i) := x"CD"; m(i+1) := std_logic_vector(x(7 downto 0)); m(i+2) := x"3D"; -- CALL #3Dxx
						when 3 => m(i) := x"C3"; m(i+1) := x"F8" or std_logic_vector(x(7 downto 0) and x"07"); m(i+2) := x"1F"; -- JP #1FF8..F
						when 4 => m(i) := x"C3"; m(i+1) := x"66"; m(i+2) := x"00"; -- JP #0066
						when 5 => m(i) := x"C3"; m(i+1) := x"C6"; m(i+2) := x"04"; -- JP #04C6
						when 6 => m(i) := x"C3"; m(i+1) := x"62"; m(i+2) := x"05"; -- JP #0562
						when 7 => m(i) := x"D3"; m(i+1) := std_logic_vector(x(7 downto 1)) & '0'; m(i+2) := x"00"; -- OUT (even),A
						when 8 => m(i) := x"D3"; m(i+1) := x"FD"; m(i+2) := x"00"; -- OUT (#FD),A
						when 9 => m(i) := x"DB"; m(i+1) := x"FD"; m(i+2) := x"00"; -- IN A,(#FD)
						when 10 => m(i) := x"FF"; m(i+1) := x"FB"; m(i+2) := x"CF"; -- RST #38, EI, RST #08
						when 11 => m(i) := x"3E"; m(i+1) := std_logic_vector(x(7 downto 0)); m(i+2) := x"C7"; -- LD A,n; RST 0
						when 12 => m(i) := x"ED"; m(i+1) := x"79"; m(i+2) := x"FB"; -- OUT (C),A; EI
						when others => m(i) := x"00"; m(i+1) := x"FB"; m(i+2) := x"00"; -- NOP; EI; NOP
					end case;
					i := i + 3;
				else
					m(i) := std_logic_vector(x(7 downto 0));
					i := i + 1;
				end if;
			end loop;
			mem <= m;
		elsif phase = 40 then
			reset <= '0';
		end if;
		cpu_reset_n <= not reset;

		-- the memory takes the writes of the cpu
		if cpu_mreq_n = '0' and cpu_wr_n = '0' then
			mem(to_integer(unsigned(cpu_a))) <= cpu_do;
		end if;

		io_data <= std_logic_vector(r(15 downto 8));
		-- WAIT_n low in 1 of 16 clocks, INT_n for 64 clocks every 4096, NMI_n for 16 clocks every 16384 + 1000
		if r(19 downto 16) = "0000" then cpu_wait_n <= '0'; else cpu_wait_n <= '1'; end if;
		if (cyc mod 4096) < 64 then cpu_int_n <= '0'; else cpu_int_n <= '1'; end if;
		if (cyc mod 16384) >= 1000 and (cyc mod 16384) < 1016 then cpu_nmi_n <= '0'; else cpu_nmi_n <= '1'; end if;
		-- DivMMC off for a while now and then
		if (cyc mod 100000) >= 50000 and (cyc mod 100000) < 50500 then divmmc_en <= '0'; else divmmc_en <= '1'; end if;

		if cyc = CLOCKS then
			done <= true;
		end if;
	end if;
end process;

-- check
process (clk)
	variable errors : integer := 0;
	variable fd_ref_d : std_logic_vector(0 downto 0) := "1";
	variable fe_ref_d : std_logic_vector(7 downto 0) := (others => '0');
	variable n_map, n_auto, n_auto3d, n_fd, n_fe, n_m1 : integer := 0;
	variable automap_d, mapcond_d, fd_d, m1_d : std_logic := '0';
	variable blk_d : std_logic := '1';
	variable fe_d : std_logic_vector(7 downto 0) := (others => '0');

	procedure check(name : string; got, exp : std_logic) is
	begin
		if got /= exp then
			errors := errors + 1;
			if errors <= 10 then
				report "tb_eq_strobes: " & name & " " & std_logic'image(got) & ", expected " & std_logic'image(exp) &
					" at clock " & integer'image(cyc) & " A=" & integer'image(to_integer(unsigned(cpu_a)))
					severity error;
			end if;
		end if;
	end procedure;
begin
	if falling_edge(clk) then
		-- divmmc_map clears its outputs one clock after RESET / DIVMMC_EN = 0 rise (blk_r, for TS_SRAM_OUT), the
		-- clock in which the CPU of profi.vhd (cpu_reset_n registered) is still running: not compared there
		if not ((reset = '1' or divmmc_en = '0') and blk_d = '0') then
			check("mapcond", mapcond_new, mapcond_ref);
			check("automap", automap_new, automap_ref);
		end if;
		blk_d := reset or not divmmc_en;
		check("fd_port", fd_new(0), fd_ref_d(0));
		for i in 0 to 7 loop
			check("port_fe(" & integer'image(i) & ")", fe_new(i), fe_ref_d(i));
		end loop;
		fd_ref_d := fd_ref;
		fe_ref_d := fe_ref;

		-- coverage
		if mapcond_ref /= mapcond_d then n_map := n_map + 1; end if;
		if automap_ref /= automap_d then
			n_auto := n_auto + 1;
			if automap_ref = '1' and cpu_a(15 downto 8) = x"3D" then n_auto3d := n_auto3d + 1; end if;
		end if;
		if fd_ref(0) /= fd_d then n_fd := n_fd + 1; end if;
		if fe_ref /= fe_d then n_fe := n_fe + 1; end if;
		if cpu_m1_n = '0' and m1_d = '1' then n_m1 := n_m1 + 1; end if;
		mapcond_d := mapcond_ref; automap_d := automap_ref; fd_d := fd_ref(0); fe_d := fe_ref; m1_d := cpu_m1_n;

		if done then
			report "tb_eq_strobes: M1 cycles " & integer'image(n_m1) & ", changes: mapcond " & integer'image(n_map) &
				", automap " & integer'image(n_auto) & " (" & integer'image(n_auto3d) & " at #3Dxx), fd_port " &
				integer'image(n_fd) & ", port #FE " & integer'image(n_fe);
			report "tb_eq_strobes: " & integer'image(errors) & " errors";
			std.env.stop;
		end if;
	end if;
end process;

end sim;
