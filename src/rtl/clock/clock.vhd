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
	
	CLK_BUS		: buffer std_logic; -- 28 / 24
	CLK_8			: buffer std_logic; -- 8 (the FDC, the FT812 clock output)
	CLK_GS		: buffer std_logic; -- 28 in both video modes (General Sound)
	CLK_SDR		: buffer std_logic; -- 84 (sdram)
	CLK_12      : buffer std_logic; -- 12
	CLK_RGB 		: buffer std_logic; -- 7 / 12
	CLK_VGA		: buffer std_logic; -- 28 / 24
	CLK_ADC		: buffer std_logic;
	
	ENA_DIV2		: buffer std_logic; -- 14 p
	ENA_DIV4		: buffer std_logic; -- 7 p
	ENA_DIV8		: buffer std_logic; -- 3.5 p 
	ENA_DIV16   : buffer std_logic; -- 1.75 p

	ENA_DIV2N	: buffer std_logic; -- 14 n
	ENA_DIV4N	: buffer std_logic; -- 7 n
	ENA_DIV8N	: buffer std_logic; -- 3.5 n
	ENA_DIV16N  : buffer std_logic; -- 1.75 n
	
	ENA_CPU 		: buffer std_logic; -- 3.5/7/14/28 / 3/6/12/24
	ENA_CPU_N	: buffer std_logic;
	ENA_RGB 		: buffer std_logic; -- 7/12
	
	CE_14			: buffer std_logic;
	CE_8			: buffer std_logic; -- 8 MHz on average (SAA1099)
	
	TURBO			: in std_logic_vector(1 downto 0);
	WAIT_CPU		: in std_logic;
	ARESET 		: out std_logic
);
end clock;

architecture rtl of clock is

signal ena_cnt : std_logic_vector(5 downto 0) := "000000";
signal locked : std_logic := '0';
signal clk_28, clk_24 : std_logic;
signal pll_clk : std_logic_vector(5 downto 0);
signal acc8 : std_logic_vector(16 downto 0) := (others => '0');

begin 

-- 50 MHz -> 28, 24, 28, 84, 12, 8 MHz (karabas-go-modules kg_pll: IBUFG, PLL_BASE, BUFG)
-- All from one PLL (VCO 675 MHz) with phase 0, so the clocks are related and the timing tools analyse the paths
-- between them (see the ucf).
U2: entity work.kg_pll
generic map (
	DIVCLK_DIVIDE			=> 2,
	CLKFBOUT_MULT 			=> 27,
	CLKOUT0_DIVIDE			=> 24, -- 28.125
	CLKOUT1_DIVIDE			=> 28, -- 24.107
	CLKOUT2_DIVIDE			=> 24, -- 28.125 (clk_gs: the same frequency and phase as CLKOUT0)
	CLKOUT3_DIVIDE			=> 8,  -- 84.375
	CLKOUT4_DIVIDE			=> 56, -- 12.054
	CLKOUT5_DIVIDE			=> 84, -- 8.036
	-- 6'b111100: BUFGs on clk_gs, 84, 12 and 8 MHz; 28 and 24 go straight to the clk_bus mux (a BUFG in front of a
	-- BUFGMUX is a cascade off the dedicated clock routing)
	BUFG_MASK				=> 60
)
port map (
	clk_in					=> CLK,
	rst						=> '0',
	clk_out					=> pll_clk,
	locked					=> locked
);
clk_28 <= pll_clk(0);
clk_24 <= pll_clk(1);
clk_gs <= pll_clk(2);
clk_sdr <= pll_clk(3);
clk_12 <= pll_clk(4);
clk_8 <= pll_clk(5);

U9 : BUFGMUX port map (I0 => clk_28, I1 => clk_24, O => clk_bus, S => ds80);
U10: BUFGCE port map(I => clk_bus, O => clk_rgb, CE => ena_rgb);
--U11: BUFGCE port map(I => clk_bus, O => clk_vga, CE => ena_div2);
--U12: BUFG port map(I => ena_cnt(0), O => clk_adc); -- 28, 50/50 duty cycle
clk_vga <= clk_bus;
clk_adc <= clk_bus;

ARESET 		<= not locked;

-- 8 MHz clock enable on clk_bus for the SAA1099 (8 MHz is its clock in the SAM Coupe): a phase accumulator,
-- 8 / 28.125 * 2^16 = 18641, 8 / 24.107 * 2^16 = 21748 (7.99997 / 7.99993 MHz on average, one clk_bus of jitter).
-- The SAA1099 ran on clk_8 before, with the CPU writes and its output crossing to clk_bus unsynchronised.
process (clk_bus)
begin
	if rising_edge(clk_bus) then
		if ds80 = '1' then
			acc8 <= ('0' & acc8(15 downto 0)) + 21748;
		else
			acc8 <= ('0' & acc8(15 downto 0)) + 18641;
		end if;
	end if;
end process;
CE_8 <= acc8(16);

-- ena counters
process (clk_bus)
begin
	if falling_edge(clk_bus) then
		ena_cnt <= ena_cnt + 1;
	end if;
end process;

process (clk_bus)
begin
	if rising_edge(clk_bus) then
		ENA_DIV2 <= ena_cnt(0);
		ENA_DIV4 <= ena_cnt(1) and ena_cnt(0);
		ENA_DIV8 <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		ENA_DIV16 <= ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);

		ENA_DIV2N <= not ena_cnt(0);
		ENA_DIV4N <= not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV8N <= not ena_cnt(2) and not ena_cnt(1) and not ena_cnt(0);
		ENA_DIV16N <= not ena_cnt(3) and not ena_cnt(2) and not ena_cnt(1) and not ena_cnt(0);
		
		if (ds80 = '1') then
			ENA_RGB <= ena_cnt(0); -- 12
		else
			ENA_RGB <= ena_cnt(0) and ena_cnt(1); -- 7
		end if;
		
		CE_14 <= ena_cnt(0);

		if (WAIT_CPU = '1') then 
			ENA_CPU <= '0';
			ENA_CPU_N <= '0';
		elsif turbo = "11" then -- 28
			ENA_CPU <= '1';
			ENA_CPU_N <= '1';
		elsif turbo = "10" then -- 14
			ENA_CPU <= ena_cnt(0);
			ENA_CPU_N <= not(ena_cnt(0));
		elsif turbo = "01" then -- 7
			ENA_CPU <= ena_cnt(1) and ena_cnt(0);
			ENA_CPU_N <= not(ena_cnt(1)) and not(ena_cnt(0));
		else
			ENA_CPU <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0); -- 3.5
			ENA_CPU_N <= not(ena_cnt(2)) and not(ena_cnt(1)) and not(ena_cnt(0));
		end if;
	end if;
end process;

end rtl;