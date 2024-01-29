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
	CLK_16 		: buffer std_logic; -- 16
	CLK_8			: buffer std_logic; -- 8
	CLK_SDR		: buffer std_logic; -- 84 (sdram)
	
	ENA_DIV2		: buffer std_logic;
	ENA_DIV4		: buffer std_logic;
	ENA_DIV8		: buffer std_logic;
	ENA_DIV16   : buffer std_logic;
	ENA_CPU 		: buffer std_logic;
	
	TURBO			: in std_logic_vector(2 downto 0);
	WAIT_CPU		: in std_logic;
	ARESET 		: out std_logic
);
end clock;

architecture rtl of clock is

signal ena_cnt : std_logic_vector(4 downto 0) := "00000";
signal locked : std_logic := '0';
signal ce_8 : std_logic := '0';
signal clk_28, clk_24 : std_logic;

begin 

-- PLL1
U1: entity work.pll
port map (
	CLK_IN1			=> CLK,
	CLK_OUT1			=> clk_28,
	CLK_OUT2 		=> clk_24,
	CLK_OUT3 		=> clk_16,
	CLK_OUT4			=> clk_sdr,
	LOCKED			=> locked
	);

-- clock switch
U2 : BUFGMUX_1
port map (
 I0      => clk_28,
 I1      => clk_24,
 O       => clk_bus,
 S       => ds80
);

	
ARESET 		<= not locked;

process (clk_16)
begin
	if rising_edge(clk_16) then
		ce_8 <= not ce_8;
	end if;
end process;

U_BUFG: BUFGCE 
port map(
	O => clk_8,
	I => clk_16,
	CE	=> ce_8
);

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

		if (WAIT_CPU = '1') then 
			ENA_CPU <= '0';
		elsif turbo = "011" then -- 28
			ENA_CPU <= '1';
		elsif turbo = "010" then -- 14
			ENA_CPU <= ena_cnt(0);
		elsif turbo = "001" then -- 7
			ENA_CPU <= ena_cnt(1) and ena_cnt(0);
		else
			ENA_CPU <= ena_cnt(2) and ena_cnt(1) and ena_cnt(0); -- 3.5
		end if;
	end if;
end process;

--U_BUFG_DIV2: BUFGCE
--port map (
--	O => CLK_DIV2,
--	I => clk_bus,
--	CE => ena_div2
--);

end rtl;