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
	
	CLK_BUS		: buffer std_logic; -- 56 / 48
	CLK_16 		: buffer std_logic; -- 16
	CLK_8			: buffer std_logic; -- 8 -- disabled yet
	CLK_SDR		: buffer std_logic; -- 84 (sdram)
	CLK_12      : buffer std_logic; -- 12
	CLK_RGB 		: buffer std_logic; -- 7 / 12
	CLK_VGA		: buffer std_logic; -- 28 / 24
	
	ENA_DIV2		: buffer std_logic;
	ENA_DIV4		: buffer std_logic;
	ENA_DIV8		: buffer std_logic;
	ENA_DIV16   : buffer std_logic;
	ENA_DIV32   : buffer std_logic;
	ENA_CPU 		: buffer std_logic;
	ENA_RGB 		: buffer std_logic; -- 7/12
	
	TURBO			: in std_logic_vector(2 downto 0);
	WAIT_CPU		: in std_logic;
	ARESET 		: out std_logic
);
end clock;

architecture rtl of clock is

signal ena_cnt : std_logic_vector(4 downto 0) := "00000";
signal locked : std_logic := '0';
signal ce_8 : std_logic := '0';
signal clk_56, clk_48 : std_logic;
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
	CLKOUT0_DIVIDE			=> 12,
	CLKOUT0_PHASE			=> 0.000,
   CLKOUT0_DUTY_CYCLE 	=> 0.500,
   CLKOUT1_DIVIDE			=> 14,
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
   CLKOUT0					=> clkout0, -- 56
   CLKOUT1          	 	=> clkout1, -- 48
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
U4 : BUFG port map (O => clk_56, I => clkout0);
U5 : BUFG port map (O => clk_48, I => clkout1);
U6 : BUFG port map (O => clk_16, I => clkout2);
U7 : BUFG port map (O => clk_sdr, I => clkout3);
U8 : BUFG port map (O => clk_12, I => clkout4);
U9 : BUFGMUX port map (I0 => clk_56, I1 => clk_48, O => clk_bus, S => ds80);
U10: BUFGCE port map(I => clk_bus, O => clk_rgb, CE => ena_rgb);
U11: BUFGCE port map(I => clk_bus, O => clk_vga, CE => ena_div2);

ARESET 		<= not locked;

--process (clk_16)
--begin
--	if rising_edge(clk_16) then
--		ce_8 <= not ce_8;
--	end if;
--end process;
--
--U_BUFG: BUFGCE 
--port map(
--	O => clk_8,
--	I => clk_16,
--	CE	=> ce_8
--);

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
		ENA_DIV32 <= ena_cnt(4) and ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		if (ds80 = '1') then
			ENA_RGB <= ena_cnt(0) and ena_cnt(1);
		else
			ENA_RGB <= ena_cnt(0) and ena_cnt(1) and ena_cnt(2);
		end if;

		if (WAIT_CPU = '1') then 
			ENA_CPU <= '0';
		elsif turbo = "011" then -- 28
			ENA_CPU <= ena_cnt(0);
		elsif turbo = "010" then -- 14
			ENA_CPU <= ena_cnt(1) and ena_cnt(0);
		elsif turbo = "001" then -- 7
			ENA_CPU <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0);
		else
			ENA_CPU <= ena_cnt(3) and ena_cnt(2) and ena_cnt(1) and ena_cnt(0); -- 3.5
		end if;
	end if;
end process;

end rtl;