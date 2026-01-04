-------------------------------------------------------------------------------
-- Clocks
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

library unisim;
use unisim.vcomponents.all;

entity clock is
port (
	CLK			: in std_logic;
	DS80			: in std_logic;
	
	CLK_BUS		: buffer std_logic; -- 112 / 96
	CLK_16 		: buffer std_logic; -- 16
	CLK_SDR		: buffer std_logic; -- 84 (sdram)
	CLK_12      : buffer std_logic; -- 12
	CLK_RGB 		: buffer std_logic; -- 7 / 12
	CLK_VGA		: buffer std_logic; -- 28 / 24
	
	ENA_DIV2		: buffer std_logic;
	ENA_DIV4		: buffer std_logic;
	ENA_DIV8		: buffer std_logic;
	ENA_DIV16   : buffer std_logic;
	ENA_DIV32   : buffer std_logic;
	ENA_DIV64 	: buffer std_logic;
	ENA_CPU 		: buffer std_logic;
	ENA_RGB 		: buffer std_logic; -- 7/12
	ENA_SAA		: buffer std_logic; -- 8
	
	ENA_DIV2N	: buffer std_logic;
	ENA_DIV4N	: buffer std_logic;
	ENA_DIV8N	: buffer std_logic;
	ENA_DIV16N	: buffer std_logic;
	ENA_DIV32N	: buffer std_logic;
	ENA_DIV64N	: buffer std_logic;
	
	CE_14			: buffer std_logic;
	
	TURBO			: in std_logic_vector(2 downto 0);
	WAIT_CPU		: in std_logic;
	ARESET 		: out std_logic
);
end clock;

architecture rtl of clock is

signal ena_cnt : std_logic_vector(5 downto 0) := "000000";
signal ena_cnt_saa : std_logic_vector(3 downto 0) := "0000";
signal locked : std_logic := '0';
signal clk_112, clk_96 : std_logic;
signal clkin1, clkfbout, clkfbout_buf, clkout0, clkout1, clkout2, clkout3, clkout4 : std_logic;

begin 

U1: IBUFG port map (O => clkin1, I => CLK);

U2: PLL_BASE
generic map (
	BANDWIDTH 				=> "OPTIMIZED",
   CLK_FEEDBACK			=> "CLKFBOUT",
   COMPENSATION			=> "SYSTEM_SYNCHRONOUS",
	DIVCLK_DIVIDE			=> 2,
	CLKFBOUT_MULT 			=> 27,
	CLKFBOUT_PHASE			=> 0.000,
	CLKOUT0_DIVIDE			=> 6,
	CLKOUT0_PHASE			=> 0.000,
   CLKOUT0_DUTY_CYCLE 	=> 0.500,
   CLKOUT1_DIVIDE			=> 7,
   CLKOUT1_PHASE			=> 0.000,
   CLKOUT1_DUTY_CYCLE 	=> 0.500,
   CLKOUT2_DIVIDE			=> 42,
   CLKOUT2_PHASE			=> 0.000,
	CLKOUT2_DUTY_CYCLE 	=> 0.500,
   CLKOUT3_DIVIDE			=> 8,
   CLKOUT3_PHASE			=> 0.000,
   CLKOUT3_DUTY_CYCLE 	=> 0.500,
   CLKOUT4_DIVIDE			=> 56,
   CLKOUT4_PHASE 			=> 0.000,
   CLKOUT4_DUTY_CYCLE 	=> 0.500,
   CLKIN_PERIOD			=> 20.000,
   REF_JITTER				=> 0.010
)
port map (
   CLKFBOUT					=> clkfbout,
   CLKOUT0					=> clkout0, -- 112
   CLKOUT1          	 	=> clkout1, -- 96
   CLKOUT2           	=> clkout2, -- 16
   CLKOUT3           	=> clkout3, -- 84
   CLKOUT4           	=> clkout4, -- 12
   CLKOUT5           	=> open,
   LOCKED            	=> locked,
	RST 						=> '0',
   CLKFBIN           	=> clkfbout_buf,
   CLKIN             	=> clkin1
);
	
U3 : BUFG port map (O => clkfbout_buf, I => clkfbout);
U4 : BUFG port map (O => clk_112, I => clkout0);
U5 : BUFG port map (O => clk_96, I => clkout1);
U6 : BUFG port map (O => clk_16, I => clkout2);
U7 : BUFG port map (O => clk_sdr, I => clkout3);
U8 : BUFG port map (O => clk_12, I => clkout4);
U9 : BUFGMUX port map (I0 => clk_112, I1 => clk_96, O => clk_bus, S => ds80);
U10: BUFGCE port map(I => clk_bus, O => clk_rgb, CE => ena_rgb);
U11: BUFGCE port map(I => clk_bus, O => clk_vga, CE => ena_div2 and ena_div4);

ARESET 		<= not locked;

-- ena counters
process (clk_bus)
begin
	if falling_edge(clk_bus) then
		ena_cnt <= ena_cnt + 1;
	end if;
end process;

process (clk_bus)
begin
	if falling_edge(clk_bus) then
		-- 112 / 14 = 8, 96 / 12 = 8
		if (ds80 = '0' and ena_cnt_saa >= 13) or (ds80 = '1' and ena_cnt_saa >= 11) then
			ena_cnt_saa <= (others => '0');
		else
			ena_cnt_saa <= ena_cnt_saa + 1;
		end if;
	end if;
end process;

process (clk_bus)
begin
	if rising_edge(clk_bus) then
		-- positive pulses
		ENA_DIV2 <= ena_cnt(0);
		ENA_DIV4 <= ena_cnt(1) and ena_cnt(0);
		ENA_DIV8 <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		ENA_DIV16 <= ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		ENA_DIV32 <= ena_cnt(4) and ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		ENA_DIV64 <= ena_cnt(5) and ena_cnt(4) and ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);

		-- negative pulses
		ENA_DIV2N <= not ena_cnt(0);
		ENA_DIV4N <= not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV8N <= not ena_cnt(2) and not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV16N <= not ena_cnt(3) and not ena_cnt(2) and not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV32N <= not ena_cnt(4) and not ena_cnt(3) and not ena_cnt(2) and not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV64N <= not ena_cnt(5) and not ena_cnt(4) and not ena_cnt(3) and not ena_cnt(2) and not ena_cnt(1) and ena_cnt(0);
		
		if (ds80 = '1') then
			ENA_RGB <= ena_cnt(0) and ena_cnt(1) and ena_cnt(2); -- 12
		else
			ENA_RGB <= ena_cnt(0) and ena_cnt(1) and ena_cnt(2) and ena_cnt(3); -- 7
		end if;

		if (ena_cnt_saa = "0000") then -- 8 mhz pulse in clk_bus domain
			ENA_SAA <= '1';
		else
			ENA_SAA <= '0';
		end if;
		
		CE_14 <= ena_cnt(2);

		if (WAIT_CPU = '1') then 
			ENA_CPU <= '0';
		elsif turbo = "100" then -- 56
			ENA_CPU <= ena_cnt(0);
		elsif turbo = "011" then -- 28
			ENA_CPU <= ena_cnt(1) and ena_cnt(0);
		elsif turbo = "010" then -- 14
			ENA_CPU <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		elsif turbo = "001" then -- 7
			ENA_CPU <= ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		else
			ENA_CPU <= ena_cnt(4) and ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0); -- 3.5
		end if;
	end if;
end process;

end rtl;