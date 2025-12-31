-------------------------------------------------------------------------------
-- MCU Soft switches receiver
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity soft_switches is
	port(
	CLK : in std_logic;	
	SOFTSW_COMMAND : in std_logic_vector(15 downto 0);
	
	ROM_BANK : out std_logic_vector(1 downto 0);
	COVOX : out std_logic;
	PSG_MIX : out std_logic_vector(1 downto 0);
	PSG_TYPE : out std_logic;
	TURBO : out std_logic_vector(2 downto 0);
	JOY_TYPE_L : out std_logic_vector(2 downto 0);
	JOY_TYPE_R : out std_logic_vector(2 downto 0);
	MODE : out std_logic_vector(1 downto 0);
	DIVMMC_EN : out std_logic;
	NEMOIDE_EN : out std_logic;
	KB_TYPE : out std_logic;
	PAUSE : out std_logic;
	NMI : out std_logic;
	RESET : out std_logic;
	GS_RESET : out std_logic
	);
end soft_switches;

architecture rtl of soft_switches is
	signal prev_command : std_logic_vector(15 downto 0) := x"FFFF";
begin 

process (CLK, prev_command, SOFTSW_COMMAND)
begin
	if rising_edge(CLK) then 
		if (prev_command /= SOFTSW_COMMAND) then
			prev_command <= SOFTSW_COMMAND;
			case SOFTSW_COMMAND(15 downto 8) is
				when x"00" => ROM_BANK <= SOFTSW_COMMAND(1 downto 0);
				when x"01" => COVOX <= SOFTSW_COMMAND(0);
				when x"02" => PSG_MIX <= SOFTSW_COMMAND(1 downto 0);
				when x"03" => PSG_TYPE <= SOFTSW_COMMAND(0);
				when x"04" => TURBO <= SOFTSW_COMMAND(2 downto 0);
				when x"05" => JOY_TYPE_L <= SOFTSW_COMMAND(2 downto 0);
				when x"06" => JOY_TYPE_R <= SOFTSW_COMMAND(2 downto 0);
				when x"07" => MODE <= SOFTSW_COMMAND(1 downto 0);
				when x"08" => DIVMMC_EN <= SOFTSW_COMMAND(0);
				when x"09" => NEMOIDE_EN <= SOFTSW_COMMAND(0);
				when x"0A" => KB_TYPE <= SOFTSW_COMMAND(0);
				when x"0B" => PAUSE <= SOFTSW_COMMAND(0);
				when x"0C" => GS_RESET <= SOFTSW_COMMAND(0);
				when x"0D" => NMI <= SOFTSW_COMMAND(0);
				when x"0E" => RESET <= SOFTSW_COMMAND(0);	
				when others => null;
			end case;
		end if;
	end if;
end process;

end rtl;