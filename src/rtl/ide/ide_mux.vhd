-------------------------------------------------------------------------------
-- IDE bus of ide_controller to the CF card and to hdf_ata (the image of the file mounter)
--
-- CF = 1: the card is device 0 and hdf_ata device 1 (its slot 5 image or no device). The card gets every strobe,
-- as the task file of ATA is written to both devices: the device / head register has to reach it also when DEV
-- goes back from device 1 to 0. The read data is the card's when DEV is 0, else hdf_ata's.
-- CF = 0: hdf_ata is device 0 (and 1), the card gets no strobe.
--
-- The write data is on the card from /WR low to one clock after /CS high, as ide_controller drives IDE_D.
-- Checked by sim/tb_ide_hdf.vhd.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity ide_mux is
port (
	CLK 			: in std_logic;
	CF 			: in std_logic;		-- the CF card is device 0
	HDF_DEV 		: in std_logic;		-- DEV of the task file (hdf_ata)
	HDF_DOUT 	: in std_logic_vector(15 downto 0);

	-- ide_controller
	IDE_A 		: in std_logic_vector(2 downto 0);
	IDE_D 		: inout std_logic_vector(15 downto 0);
	IDE_CS_N 	: in std_logic_vector(1 downto 0);
	IDE_RD_N 	: in std_logic;
	IDE_WR_N 	: in std_logic;
	IDE_RESET_N : in std_logic;

	-- the CF card
	WA 			: out std_logic_vector(2 downto 0);
	WD 			: inout std_logic_vector(15 downto 0);
	WCS_N 		: out std_logic_vector(1 downto 0);
	WRD_N 		: out std_logic;
	WWR_N 		: out std_logic;
	WRESET_N 	: out std_logic
);
end ide_mux;

architecture rtl of ide_mux is

signal cf_data : std_logic;
signal wr_act : std_logic := '0';

begin

cf_data <= CF and not HDF_DEV;

WA <= IDE_A;
WCS_N <= IDE_CS_N when CF = '1' else "11";
WRD_N <= IDE_RD_N when CF = '1' else '1';
WWR_N <= IDE_WR_N when CF = '1' else '1';
WRESET_N <= IDE_RESET_N;

process (CLK)
begin
	if rising_edge(CLK) then
		if IDE_WR_N = '0' then
			wr_act <= '1';
		elsif IDE_CS_N = "11" then
			wr_act <= '0';
		end if;
	end if;
end process;

WD <= IDE_D when CF = '1' and (IDE_WR_N = '0' or wr_act = '1') else (others => 'Z');

IDE_D <= WD when cf_data = '1' and IDE_RD_N = '0' else
         HDF_DOUT when cf_data = '0' and IDE_RD_N = '0' else
         (others => 'Z');

end rtl;
