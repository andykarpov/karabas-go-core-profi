-------------------------------------------------------------------------------
-- Memory controller
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;

entity memory is
port (
	CLK_BUS		: in std_logic;

	ENA_CPU 		: in std_logic;

	A           : in std_logic_vector(15 downto 0); -- address bus
	D 				: in std_logic_vector(7 downto 0);
	N_MREQ		: in std_logic;
	N_IORQ 		: in std_logic;
	N_WR 			: in std_logic;
	N_RD 			: in std_logic;
	N_M1 			: in std_logic;
	
	loader_act 	: in std_logic := '0';
	loader_ram_a: in std_logic_vector(20 downto 0);
	loader_ram_do: in std_logic_vector(7 downto 0);
	loader_ram_wr: in std_logic := '0';
	
	DO 			: out std_logic_vector(7 downto 0);
	N_OE 			: out std_logic;
	
	MA 			: out std_logic_vector(20 downto 0);
	MD 			: inout std_logic_vector(15 downto 0) := "ZZZZZZZZZZZZZZZZ";
	N_MRD 		: buffer std_logic_vector(1 downto 0);
	N_MWR 		: buffer std_logic_vector(1 downto 0);
	
	RAM_BANK		: in std_logic_vector(2 downto 0);
	RAM_EXT 		: in std_logic_vector(2 downto 0);
	
	TRDOS 		: in std_logic;

	VA				: in std_logic_vector(13 downto 0);
	VID_PAGE 	: in std_logic := '0';
	VID_DO 		: out std_logic_vector(7 downto 0);
	VID_RD 		: in std_logic;
	
	DS80			: in std_logic := '0';
	CPM 			: in std_logic := '0';
	SCO			: in std_logic := '0';
	SCR 			: in std_logic := '0';
	WOROM 		: in std_logic := '0';
	
	ROM_BANK : in std_logic := '0';
	EXT_ROM_BANK : in std_logic_vector(1 downto 0) := "00";
	
	COUNT_BLOCK : in std_logic := '0'; -- paper = '0' and (not (chr_col_cnt(2) and hor_cnt(0)));
	CONTENDED   : out std_logic := '0';
	
	DIVMMC_EN	: in std_logic;
	AUTOMAP		: in std_logic;
	REG_E3		: in std_logic_vector(7 downto 0);
	
	TURBO_MODE	: in std_logic_vector(2 downto 0)
);
end memory;

architecture RTL of memory is

	signal is_rom : std_logic := '0';
	signal is_ram : std_logic := '0';
	
	signal rom_page : std_logic_vector(1 downto 0) := "00";
	signal ram_page : std_logic_vector(8 downto 0) := "000000000";

	signal mux : std_logic_vector(1 downto 0);
	
	signal block_reg : std_logic := '0';
	signal page_cont : std_logic := '0';
	
	signal is_romDIVMMC : std_logic;
	signal is_ramDIVMMC : std_logic;
	
	signal vid_wr : std_logic_vector(0 downto 0);
	signal vid_wr_a_bus, vid_rd_a_bus: std_logic_vector(15 downto 0);
	signal vid_wr_attr : std_logic;
	signal vid_wr_page : std_logic;
	
begin

	-- video ram 64k
	U_VRAM: entity work.vram
	port map(
		clka => CLK_BUS,
		wea => vid_wr,
		addra => vid_wr_a_bus,
		dina => D,
		clkb => CLK_BUS,
		addrb => vid_rd_a_bus,
		doutb => VID_DO
	);

	-- video mem write: 
	vid_wr <= "1" when ENA_CPU = '1' and DS80 = '0' and N_MREQ = '0' and N_WR = '0' and A(13) = '0' and (ram_page = "000000101" or ram_page = "000000111") else -- spectrum pix / att
				 "1" when ENA_CPU = '1' and DS80 = '1' and N_MREQ = '0' and N_WR = '0' and (ram_page = "000000100" or ram_page = "000000110") else -- profi pix
				 "1" when ENA_CPU = '1' and DS80 = '1' and N_MREQ = '0' and N_WR = '0' and (ram_page = "000111000" or ram_page = "000111010") else -- profi att
				 "0";

	-- detect profi attr write
	vid_wr_attr <= '1' when (ram_page = "000111000" or ram_page = "000111010") else '0';
	
	-- detect video page for write
	vid_wr_page <= '1' when DS80 = '0' and ram_page = "000000111" else -- spectrum video page
						'1' when DS80 = '1' and (ram_page = "000000110" or ram_page = "000111010") else -- profi video page
						'0';

	-- write address to vram
	vid_wr_a_bus <= 
		"00" & vid_wr_page & A(12 downto 0) when DS80 = '0' else -- spectrum video address
		vid_wr_attr & VID_wr_page & A(13 downto 0); -- profi video address 
		
	-- read address from vram
	vid_rd_a_bus <= 
		"00" & VID_PAGE & VA(12 downto 0) when DS80 = '0' else -- spectrum video address
		VID_RD & VID_PAGE & VA(13 downto 0); -- profi video address

	N_MRD <= "11" when loader_act = '1' else
				"10" when (is_rom = '1' and N_RD = '0') or -- read rom
						(N_RD = '0' and N_MREQ = '0') else  -- read ram
				"11";
				
	N_MWR <= '1' & not(loader_ram_wr) when loader_act = '1' else 
				"10" when (is_ram = '1' or is_ramDIVMMC = '1') and N_WR = '0' else -- write ram
				"11";

	MA(20 downto 0) <=
		loader_ram_a(20 downto 0) when loader_act = '1' else -- loader ram
		"1010000" & A(13 downto 0) when is_romDIVMMC = '1' else -- DIVMMC rom
		"11" & REG_E3(5 downto 0) & A(12 downto 0) when is_ramDIVMMC = '1' else -- DIVMMC ram 512 kB from #X180000 SRAM
		"100" & EXT_ROM_BANK(1 downto 0) & rom_page(1 downto 0) & A(13 downto 0) when is_rom = '1' else -- rom from sram high bank 
		ram_page(6 downto 0) & A(13 downto 0);  -- ram
		
	MD(7 downto 0) <= 
		loader_ram_do when loader_act = '1' else -- loader DO
		D(7 downto 0) when (is_ram = '1' or is_ramDIVMMC = '1' or (N_IORQ = '0' and N_M1 = '1')) and N_WR = '0' else  -- OCH: why (N_IORQ = '0' and N_M1 = '1') this used in memory controller? and in write mode
		(others => 'Z');

	DO <= MD(7 downto 0);
		
	is_romDIVMMC <= '1' when DIVMMC_EN = '1' and N_MREQ = '0' and (AUTOMAP ='1' or REG_E3(7) = '1') and A(15 downto 13) = "000" else '0';
	is_ramDIVMMC <= '1' when DIVMMC_EN = '1' and N_MREQ = '0' and (AUTOMAP ='1' or REG_E3(7) = '1') and A(15 downto 13) = "001" else '0';
	
	is_rom <= '1' when N_MREQ = '0' and A(15 downto 14)  = "00"  and WOROM = '0' else '0';
	is_ram <= '1' when N_MREQ = '0' and is_rom = '0' else '0';	
	
	-- 00 - bank 0, CPM
	-- 01 - bank 1, TRDOS
	-- 10 - bank 2, Basic-128
	-- 11 - bank 3, Basic-48

	rom_page <= (not(TRDOS)) & ROM_BANK when DIVMMC_EN = '0' else "11";
			
	N_OE <= '0' when (is_ram = '1' or is_rom = '1') and N_RD = '0' else '1';
		
	mux <= A(15 downto 14);
		
	process (mux, RAM_EXT, RAM_BANK, SCR, SCO)
	begin
		case mux is
			when "00" => ram_page <= "000000000";                 -- Seg0 ROM 0000-3FFF or Seg0 RAM 0000-3FFF				
			when "01" => if SCO='0' then 
								ram_page <= "000000101";
							 else 
								ram_page <= "000" & RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0); 
							 end if;	                               -- Seg1 RAM 4000-7FFF	
			when "10" => if SCR='0' then 
								ram_page <= "000000010"; 	
							 else 
								ram_page <= "000000110"; 
							 end if;                                -- Seg2 RAM 8000-BFFF
			when "11" => if SCO='0' then 
								ram_page <= "000" & RAM_EXT(2 downto 0) & RAM_BANK(2 downto 0);	
							 else 
								ram_page <= "000000111";               -- Seg3 RAM C000-FFFF	
							 end if;
			when others => null;
		end case;
	end process;
	
	process( CLK_BUS, ENA_CPU )
	begin
		if rising_edge(CLK_BUS) and ENA_CPU = '1' then
			if N_MREQ = '0' or (A(0) = '0' and N_IORQ = '0')then
				block_reg <='0';
			else
				block_reg <= '1';
			end if;
		end if;
	end process;
	
	page_cont <= '1' when (A(0) = '0' and N_IORQ = '0') or mux="01" else '0';
	
	process (CLK_BUS)
	begin 
		if rising_edge(CLK_BUS) then 
		-- OCH: contend only when 3,5 MHz CLK 
			if (page_cont = '1' and block_reg = '1' and count_block = '1' and DS80 = '0' and TURBO_MODE = "000") then 
				contended <= '1';
			else 
				contended <= '0';
			end if;
		end if;
	end process;
			
end RTL;

