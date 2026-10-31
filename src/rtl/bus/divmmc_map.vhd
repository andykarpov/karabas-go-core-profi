-------------------------------------------------------------------------------
-- DivMMC automap
--
-- Engineer:   Mario Prato
-- 11.07.2013:OCH: adapted by me
-- i take this implementation to correctly and easy make nmi
--
-- mapcond and automap change where MREQ_n falls in an M1 cycle. They were flip-flops clocked by MREQ_n (a clock
-- from logic, outside the timing analysis); now they are taken on the clock after MREQ_n fell and passed through
-- in that first clock of the fetch, so on every clock edge they have the values of the old flip-flops and the
-- fetch that maps (#3Dxx) still reads the DivMMC ROM. Checked against the old version by sim/tb_eq_strobes.vhd
-- (the T80 running random code).
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;

entity divmmc_map is
port (
	CLK			: in std_logic;
	RESET			: in std_logic;
	DIVMMC_EN	: in std_logic;
	A				: in std_logic_vector(15 downto 0);
	M1_N			: in std_logic;
	MREQ_N		: in std_logic;
	MAPCOND		: out std_logic;
	AUTOMAP		: out std_logic
);
end divmmc_map;

architecture rtl of divmmc_map is

signal mapterm, map3DXX, map1F00 : std_logic;
signal blk : std_logic;
signal blk_r : std_logic := '1';
signal fetch, fetch_r, fetch_start : std_logic := '0';
signal mapcond_r, automap_r : std_logic := '0';
signal mapcond_next_r, automap_next_r : std_logic := '0';

begin

-- the addresses (the reset and DIVMMC_EN = 0 of the old version are in blk)
mapterm <= '1' when A = x"0000" or A = x"0008" or A = x"0038" or A = x"0066" or A = x"04c6" or A = x"0562" else '0';
map3DXX <= '1' when A(15 downto 8) = "00111101" else '0'; -- mappa 3D00 - 3DFF
map1F00 <= '0' when A(15 downto 3) = "0001111111111" else '1'; -- 1ff8 - 1fff

blk <= RESET or not DIVMMC_EN;
fetch <= '1' when M1_N = '0' and MREQ_N = '0' else '0';
fetch_start <= fetch and not fetch_r;

-- The values for a fetch are registered on every clock: in an M1 cycle the T80 sets A a clock or more before
-- MREQ_n falls, so in the first clock of the fetch they are those of its address. This keeps the address decoder
-- of the SRAM one LUT from M1_n / MREQ_n.
process (CLK)
begin
	if rising_edge(CLK) then
		mapcond_next_r <= mapterm or map3DXX or (mapcond_r and map1F00);
		automap_next_r <= mapcond_r or map3DXX;
		fetch_r <= fetch;
		blk_r <= blk;
		if blk = '1' then
			mapcond_r <= '0';
			automap_r <= '0';
		elsif fetch_start = '1' then
			mapcond_r <= mapcond_next_r;
			automap_r <= automap_next_r;
		end if;
	end if;
end process;

-- cleared by RESET and DIVMMC_EN = 0 (an asynchronous reset before), one clock after they rise: blk_r keeps the
-- combinational reset of profi.vhd (loader, keys, buttons) off the path to the SRAM address pads (TS_SRAM_OUT).
-- In that clock the CPU is in reset already (or DIVMMC_EN was changed from the OSD); after the release the outputs
-- follow the registers again one clock later, before the CPU can start a fetch (T1 comes first).
MAPCOND <= '0' when blk_r = '1' else mapcond_next_r when fetch_start = '1' else mapcond_r;
AUTOMAP <= '0' when blk_r = '1' else automap_next_r when fetch_start = '1' else automap_r;

end rtl;
