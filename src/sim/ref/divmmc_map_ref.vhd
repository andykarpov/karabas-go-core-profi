-- The DivMMC automap of profi.vhd before divmmc_map (master 3d016a4): mapcond / automap are flip-flops clocked by
-- the falling MREQ_n.

library IEEE;
use IEEE.std_logic_1164.all;

entity divmmc_map_ref is
port (
	I_RESET		: in std_logic;
	I_DIVMMC_EN	: in std_logic;
	I_A			: in std_logic_vector(15 downto 0);
	I_M1_N		: in std_logic;
	I_MREQ_N		: in std_logic;
	O_MAPCOND	: out std_logic;
	O_AUTOMAP	: out std_logic
);
end divmmc_map_ref;

architecture rtl of divmmc_map_ref is
signal cpu_a_bus : std_logic_vector(15 downto 0);
signal hia : std_logic_vector(15 downto 8);
signal reset, divmmc_en, cpu_m1_n, cpu_mreq_n : std_logic;
signal mapterm, map3DXX, map1F00, mapcond, automap : std_logic;
begin
cpu_a_bus <= I_A;
hia <= I_A(15 downto 8);
reset <= I_RESET;
divmmc_en <= I_DIVMMC_EN;
cpu_m1_n <= I_M1_N;
cpu_mreq_n <= I_MREQ_N;
O_MAPCOND <= mapcond;
O_AUTOMAP <= automap;

process (reset, divmmc_en, cpu_a_bus)
begin
	if reset = '1' or divmmc_en = '0' then 
		mapterm <= '0';
		map3DXX <= '0';
		map1F00 <= '1';
	else
		 if cpu_a_bus(15 downto 0) = x"0000"   or 
			 cpu_a_bus(15 downto 0) = x"0008"   or 
			 cpu_a_bus(15 downto 0) = x"0038"   or 
			 cpu_a_bus(15 downto 0) = x"0066"   or 
			 cpu_a_bus(15 downto 0) = x"04c6"   or 
			 cpu_a_bus(15 downto 0) = x"0562" then 
			mapterm <= '1';
		else 
			mapterm <= '0';
		end if;	

		-- mappa 3D00 - 3DFF
		if hia(15 downto 8) = "00111101" then 
			map3DXX <= '1'; 
		else 
			map3DXX <= '0';
		end if; 

		-- 1ff8 - 1fff
		if cpu_a_bus(15 downto 3) =   "0001111111111" then 
			map1F00 <= '0';
		else 
			map1F00 <= '1';
		end if; 
	end if;
end process;
process(reset, divmmc_en, cpu_mreq_n, cpu_m1_n, mapcond, mapterm, map3DXX, map1F00, automap)
begin
	if reset = '1' or divmmc_en = '0' then 
		mapcond <= '0';
		automap <= '0';
   elsif falling_edge(cpu_mreq_n) then
		   if cpu_m1_n = '0' then
				 mapcond <= (mapterm or map3DXX or (mapcond and map1F00)) and divmmc_en;
				 automap <= (mapcond or map3DXX) and divmmc_en;
		  end if;
	end if;	  
end process; 

end rtl;
