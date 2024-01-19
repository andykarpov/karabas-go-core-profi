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
	CLK_8			: buffer std_logic; -- 8
	
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

signal prev_ds80 : std_logic := '0';
signal pulse_reconf : std_logic_vector(7 downto 0) := "00000001"; -- force reconfigure on boot

signal ena_cnt : std_logic_vector(4 downto 0) := "00000";
signal locked : std_logic := '0';
signal pll_state : std_logic_vector(2 downto 0) := "000";

signal ce_8 : std_logic := '0';

begin 

process (CLK_BUS)
begin
	if rising_edge(CLK_BUS) then 
		if (prev_ds80 /= ds80) then 	
			prev_ds80 <= ds80;
			pulse_reconf <= "00000001";
		else
			pulse_reconf <= pulse_reconf(6 downto 0) & '0';
		end if;
		
		if (locked = '0') then 
			locked <= '1';
		end if;
		
	end if;
end process;

pll_state <= "00" & prev_ds80;

-- reconfigurable pll 28 / 24 MHZ
U1: entity work.pll_top
port map (
	SSTEP 			=> pulse_reconf(7),
	STATE 			=> pll_state,
	RST 				=> '0',
	CLKIN				=> CLK,
	SRDY 				=> open,
	CLK0OUT 			=> CLK_BUS, -- 28 / 24
	CLK1OUT 			=> CLK_16,  -- 16
	CLK2OUT 			=> open,
	CLK3OUT 			=> open
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