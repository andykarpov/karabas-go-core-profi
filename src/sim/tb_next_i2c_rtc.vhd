-- tb_next_i2c_rtc: the CPU bit-bangs I2C on ports 103B / 113B (as the RTC.SYS of the Next) and reads the DS1307
-- emulation of next_i2c_rtc over a model of the board RTC (MC146818 registers, rtc_do a clock after rtc_a).
-- Checks: registers 0..6 in BCD (binary and BCD MC146818 modes), the signature "ZX" at 3E / 3F, a write of the
-- minutes, EN = 0 (no answer). Run: ghdl -a --std=08 ... ; ghdl -r --std=08 tb_next_i2c_rtc
library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_next_i2c_rtc is
end tb_next_i2c_rtc;

architecture sim of tb_next_i2c_rtc is
	signal clk      : std_logic := '0';
	signal reset    : std_logic := '1';
	signal en       : std_logic := '1';
	signal a        : std_logic_vector(15 downto 0) := x"0000";
	signal di       : std_logic_vector(7 downto 0) := x"00";
	signal iorq_n, rd_n, wr_n : std_logic := '1';
	signal do_bus   : std_logic_vector(7 downto 0);
	signal oe       : std_logic;
	signal bin_mode : std_logic := '0';
	signal rtc_a, rtc_di, rtc_do : std_logic_vector(7 downto 0);
	signal rtc_wr   : std_logic;
	type ram_t is array (0 to 255) of std_logic_vector(7 downto 0);
	signal ram : ram_t := (others => x"00");
	signal done : boolean := false;
	signal load : integer := 0;   -- 1: the BCD time, 2: the binary time (the RAM process loads it)
begin
	clk <= not clk after 17.86 ns when not done;   -- 28 MHz

	dut: entity work.next_i2c_rtc port map(
		CLK => clk, RESET => reset, EN => en, A => a, DI => di, IORQ_N => iorq_n, M1_N => '1', RD_N => rd_n,
		WR_N => wr_n, DO => do_bus, OE => oe, BIN_MODE => bin_mode,
		RTC_A => rtc_a, RTC_DI => rtc_di, RTC_WR => rtc_wr, RTC_DO => rtc_do);

	process (clk)
	begin
		if rising_edge(clk) then
			rtc_do <= ram(to_integer(unsigned(rtc_a)));
			if rtc_wr = '1' then ram(to_integer(unsigned(rtc_a))) <= rtc_di; end if;
			if load = 1 then
				ram(0) <= x"56"; ram(2) <= x"45"; ram(4) <= x"13"; ram(6) <= x"07"; ram(7) <= x"21"; ram(8) <= x"11";
				ram(9) <= x"26"; ram(16#0E#) <= x"A5";
			elsif load = 2 then
				ram(0) <= std_logic_vector(to_unsigned(56, 8)); ram(2) <= std_logic_vector(to_unsigned(45, 8));
				ram(4) <= std_logic_vector(to_unsigned(13, 8)); ram(6) <= x"07";
				ram(7) <= std_logic_vector(to_unsigned(21, 8)); ram(8) <= std_logic_vector(to_unsigned(11, 8));
				ram(9) <= std_logic_vector(to_unsigned(26, 8));
			end if;
		end if;
	end process;

	process
		procedure io_out(port_a : std_logic_vector(15 downto 0); v : std_logic) is
		begin
			a <= port_a; di <= "0000000" & v;
			wait until rising_edge(clk); iorq_n <= '0'; wr_n <= '0';
			for i in 1 to 6 loop wait until rising_edge(clk); end loop;   -- a slow CPU: several clocks per IO
			iorq_n <= '1'; wr_n <= '1';
			for i in 1 to 6 loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure io_in(port_a : std_logic_vector(15 downto 0); v : out std_logic) is
		begin
			a <= port_a;
			wait until rising_edge(clk); iorq_n <= '0'; rd_n <= '0';
			for i in 1 to 4 loop wait until rising_edge(clk); end loop;
			assert oe = '1' report "no OE on a read" severity error;
			v := do_bus(0);
			iorq_n <= '1'; rd_n <= '1';
			for i in 1 to 6 loop wait until rising_edge(clk); end loop;
		end procedure;
		procedure scl(v : std_logic) is begin io_out(x"103B", v); end procedure;
		procedure sda(v : std_logic) is begin io_out(x"113B", v); end procedure;
		procedure start is begin sda('1'); scl('1'); sda('0'); scl('0'); end procedure;
		procedure stop is begin sda('0'); scl('1'); sda('1'); end procedure;
		procedure wr_byte(b : std_logic_vector(7 downto 0)) is
			variable ack : std_logic;
		begin
			for i in 7 downto 0 loop sda(b(i)); scl('1'); scl('0'); end loop;
			sda('1'); scl('1'); io_in(x"113B", ack); scl('0');
			assert ack = '0' report "no ACK" severity error;
		end procedure;
		procedure rd_byte(b : out std_logic_vector(7 downto 0); last : boolean) is
			variable v : std_logic_vector(7 downto 0);
			variable bit_v : std_logic;
		begin
			sda('1');
			for i in 7 downto 0 loop scl('1'); io_in(x"113B", bit_v); v(i) := bit_v; scl('0'); end loop;
			if last then sda('1'); else sda('0'); end if;
			scl('1'); scl('0');
			b := v;
		end procedure;
		procedure read_regs(first : integer; n : integer; exp : ram_t) is
			variable b : std_logic_vector(7 downto 0);
		begin
			start; wr_byte(x"D0"); wr_byte(std_logic_vector(to_unsigned(first, 8)));
			start; wr_byte(x"D1");
			for i in 0 to n - 1 loop
				rd_byte(b, i = n - 1);
				assert b = exp(i) report "reg " & integer'image(first + i) & ": got " &
					integer'image(to_integer(unsigned(b))) & " want " & integer'image(to_integer(unsigned(exp(i))))
					severity error;
			end loop;
			stop;
		end procedure;
		variable e : ram_t := (others => x"00");
	begin
		for i in 1 to 4 loop wait until rising_edge(clk); end loop;
		reset <= '0';
		for i in 1 to 4 loop wait until rising_edge(clk); end loop;

		-- BCD mode: 2026-11-21 (saturday = 7) 13:45:56
		load <= 1; wait until rising_edge(clk); load <= 0; wait until rising_edge(clk);
		e(0) := x"56"; e(1) := x"45"; e(2) := x"13"; e(3) := x"07"; e(4) := x"21"; e(5) := x"11"; e(6) := x"26";
		e(7) := x"00"; e(8) := x"A5";
		read_regs(0, 9, e);
		report "BCD mode: regs 0..8 ok";

		e(0) := x"5A"; e(1) := x"58";
		read_regs(16#3E#, 2, e);
		report "signature ZX ok";

		-- binary mode: the same time as binary values
		bin_mode <= '1';
		load <= 2; wait until rising_edge(clk); load <= 0; wait until rising_edge(clk);
		e(0) := x"56"; e(1) := x"45"; e(2) := x"13"; e(3) := x"07"; e(4) := x"21"; e(5) := x"11"; e(6) := x"26";
		read_regs(0, 7, e);
		report "binary mode: regs 0..6 ok";

		-- write minutes = 0x59 (BCD) in binary mode -> MC146818 register 2 = 59
		start; wr_byte(x"D0"); wr_byte(x"01"); wr_byte(x"59"); stop;
		wait until rising_edge(clk);
		assert ram(2) = std_logic_vector(to_unsigned(59, 8)) report "write of the minutes" severity error;
		report "write ok";

		-- EN = 0: no answer on the ports
		en <= '0';
		a <= x"113B"; wait until rising_edge(clk); iorq_n <= '0'; rd_n <= '0';
		wait until rising_edge(clk); wait until rising_edge(clk);
		assert oe = '0' report "OE with EN = 0" severity error;
		iorq_n <= '1'; rd_n <= '1';
		report "EN = 0 ok";

		report "tb_next_i2c_rtc: done";
		done <= true;
		wait;
	end process;
end sim;
