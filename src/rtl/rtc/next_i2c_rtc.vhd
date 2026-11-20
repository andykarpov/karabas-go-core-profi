-- I2C of ZX Next (port 103B: SCL, port 113B: SDA, bit 0; a read gives 1111111 & the line) with the DS1307
-- emulation of core-next (ds1307.vhd + i2cslave.vhd) on the MC146818 registers of the board RTC (kg_mcu,
-- core.json rtc_mode 0). The RTC.SYS of esxDOS for the Next reads the date and time here.
--
-- DS1307 -> MC146818: 0 sec -> 0, 1 min -> 2, 2 hour -> 4, 3 day of week -> 6, 4 day -> 7, 5 month -> 8,
-- 6 year -> 9 (BCD on the I2C side; converted when register B of the MC146818 is in binary mode, DM = 1),
-- 7 control = 00, 08..39 RAM -> 0E..3F, 3A..3D = FF, 3E / 3F = "ZX" (the signature the RTC.SYS of the Next checks).
--
-- EN: the ports work only when it is 1 (profi: not in the DOS / CP/M modes, whose short decoders cover xx3B).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity next_i2c_rtc is
	port(
		CLK      : in std_logic;
		RESET    : in std_logic;
		EN       : in std_logic;
		A        : in std_logic_vector(15 downto 0);
		DI       : in std_logic_vector(7 downto 0);
		IORQ_N   : in std_logic;
		M1_N     : in std_logic;
		RD_N     : in std_logic;
		WR_N     : in std_logic;
		DO       : out std_logic_vector(7 downto 0);
		OE       : out std_logic;

		BIN_MODE : in std_logic;                      -- MC146818 register B bit 2 (DM)
		RTC_A    : out std_logic_vector(7 downto 0);
		RTC_DI   : out std_logic_vector(7 downto 0);
		RTC_WR   : out std_logic;
		RTC_DO   : in std_logic_vector(7 downto 0)
	);
end next_i2c_rtc;

architecture rtl of next_i2c_rtc is

	signal io_103b, io_113b : std_logic;
	signal nx_scl, nx_sda   : std_logic := '1';
	signal scl, sda, sda_s  : std_logic;

	signal ds_a, ds_di, ds_do : std_logic_vector(7 downto 0);
	signal ds_wr              : std_logic;
	signal reg                : unsigned(5 downto 0);
	signal is_time, is_map    : std_logic;
	signal mc_a               : std_logic_vector(7 downto 0);

	function bin2bcd(v : std_logic_vector(7 downto 0)) return std_logic_vector is
		variable n : integer range 0 to 255;
	begin
		n := to_integer(unsigned(v(6 downto 0)));
		if n > 99 then n := 99; end if;
		return std_logic_vector(to_unsigned(n / 10, 4)) & std_logic_vector(to_unsigned(n mod 10, 4));
	end function;

	function bcd2bin(v : std_logic_vector(7 downto 0)) return std_logic_vector is
	begin
		return std_logic_vector(resize(unsigned(v(7 downto 4)) * 10 + unsigned(v(3 downto 0)), 8));
	end function;

begin

	io_103b <= '1' when EN = '1' and IORQ_N = '0' and M1_N = '1' and A = x"103B" else '0';
	io_113b <= '1' when EN = '1' and IORQ_N = '0' and M1_N = '1' and A = x"113B" else '0';

	process (CLK)
	begin
		if rising_edge(CLK) then
			if RESET = '1' then
				nx_scl <= '1';
				nx_sda <= '1';
			else
				if io_103b = '1' and WR_N = '0' then nx_scl <= DI(0); end if;
				if io_113b = '1' and WR_N = '0' then nx_sda <= DI(0); end if;
			end if;
		end if;
	end process;

	scl <= nx_scl;
	sda <= nx_sda and sda_s;                         -- wired AND: the slave pulls SDA low

	OE <= '1' when (io_103b = '1' or io_113b = '1') and RD_N = '0' else '0';
	DO <= "1111111" & scl when io_103b = '1' else "1111111" & sda;

	U_DS1307: entity work.ds1307
	port map(
		clk     => CLK,
		reset_n => not RESET,
		scl_i   => scl,
		sda_i   => sda,
		scl_o   => open,
		sda_o   => sda_s,
		rtc_a   => ds_a,
		rtc_di  => ds_di,
		rtc_do  => ds_do,
		rtc_wr  => ds_wr
	);

	-- the register map
	reg <= unsigned(ds_a(5 downto 0));
	process (reg)
	begin
		is_time <= '0';
		is_map <= '1';
		mc_a <= x"FF";
		case to_integer(reg) is
			when 0 => mc_a <= x"00"; is_time <= '1';
			when 1 => mc_a <= x"02"; is_time <= '1';
			when 2 => mc_a <= x"04"; is_time <= '1';
			when 3 => mc_a <= x"06"; is_time <= '1';
			when 4 => mc_a <= x"07"; is_time <= '1';
			when 5 => mc_a <= x"08"; is_time <= '1';
			when 6 => mc_a <= x"09"; is_time <= '1';
			when 8 to 16#39# => mc_a <= std_logic_vector(resize(reg + 6, 8));
			when others => is_map <= '0';
		end case;
	end process;

	ds_do <= x"5A" when reg = 16#3E# else
	         x"58" when reg = 16#3F# else
	         x"00" when reg = 7 else
	         x"FF" when is_map = '0' else
	         bin2bcd(RTC_DO) when is_time = '1' and BIN_MODE = '1' else
	         RTC_DO;

	RTC_A <= mc_a;
	RTC_DI <= bcd2bin(ds_di and x"7F") when is_time = '1' and BIN_MODE = '1' else ds_di;
	RTC_WR <= ds_wr and is_map;

end rtl;
