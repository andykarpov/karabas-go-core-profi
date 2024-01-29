library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;

-- OCH: info taken from solegstar's profi extender
-- hdd			  Profi		  Nemo
   ----------- ----------- ---------
-- hdd_a0      adress(8)   adress(5)
-- hdd_a1      adress(9)   adress(6)
-- hdd_a2      adress(10)  adress(7)
-- hdd_wr      wr          iow
-- hdd_rd      rd          nemo_ior
-- hdd_cs0     cs1fx       nemo_cs0
-- hdd_cs1     cs3fx       nemo_cs1
-- hdd_rh_oe   rwe         rdh
-- hdd_rh_c    cs1fx       ior
-- hdd_wh_oe   wwe         iow
-- hdd_wh_c    wwc         wrh
-- hdd_rwl_t   rww         ior
-- hdd_iorqge  '0'         nemo_ebl -- used in another way OCH:
   ----------- ----------- ---------


entity ide_controller is 
port (
	CLK 			: in std_logic;
	ENA_CPU		: in std_logic;
	RESET 		: in std_logic;
	
	NEMOIDE_EN	: in std_logic;
	
	A 				: in std_logic_vector(15 downto 0);
	DI 			: in std_logic_vector(7 downto 0);
	IORQ_N 		: in std_logic;
	MREQ_N 		: in std_logic;
	M1_N 			: in std_logic;
	RD_N 			: in std_logic;
	WR_N 			: in std_logic;
	
	CPM 			: in std_logic;
	ROM14			: in std_logic;
	DOS			: in std_logic;
	HDD_OFF		: in std_logic;

	DO 			: out std_logic_vector(7 downto 0);
	ACTIVE		: out std_logic;
	OE_N 			: out std_logic;
	
	IDE_A 		: out std_logic_vector(2 downto 0);
	IDE_D 		: inout std_logic_vector(15 downto 0);
	IDE_CS_N 	: out std_logic_vector(1 downto 0);
	IDE_RD_N 	: out std_logic;
	IDE_WR_N 	: out std_logic;
	IDE_RESET_N : out std_logic	
);
end ide_controller;

architecture rtl of ide_controller is 

-- Profi HDD ports
signal profi_ebl_n	:std_logic;
signal wwc_n			:std_logic; -- Write High byte from Data bus to "Write register"
signal wwe_n			:std_logic; -- Read High byte from "Write register" to HDD bus
signal rww_n			:std_logic; -- Selector Low byte Data bus Buffer Direction: 1 - to HDD bus, 0 - to Data bus
signal rwe_n			:std_logic; -- Read High byte from "Read register" to Data bus
signal cs3fx_n			:std_logic;
signal cs1fx_n			:std_logic;

-- Nemo HDD ports
signal cs_nemo_ports		: std_logic;
signal nemo_ebl_n			: std_logic;
signal IOW					: std_logic;
signal WRH 					: std_logic;
signal IOR 					: std_logic;
signal RDH 					: std_logic;
signal nemo_cs0			: std_logic;
signal nemo_cs1			: std_logic;
signal nemo_ior			: std_logic;

signal cs_hdd_wr	: std_logic;
signal cs_hdd_rd	: std_logic;
signal wd_reg_in	: std_logic_vector(15 downto 0);
signal wd_reg_out	: std_logic_vector(15 downto 0);

signal cnt      : std_logic_vector(5 downto 0);

begin 

--  Profi HDD
profi_ebl_n	<='0' when (A(7)='1' and A(4 downto 0)="01011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1';	-- ROM14=0 BAS=0  SYS
wwc_n 		<='0' when (WR_N='0' and A(7 downto 0)="11001011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1'; -- Write High byte from Data bus to "Write register"
wwe_n 		<='0' when (WR_N='0' and A(7 downto 0)="11101011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1'; -- Read High byte from "Write register" to HDD bus
rww_n 		<='0' when (WR_N='1' and A(7 downto 0)="11001011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1'; -- Selector Low byte Data bus Buffer Direction: 1 - to HDD bus, 0 - to Data bus
rwe_n 		<='0' when (WR_N='1' and A(7 downto 0)="11101011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1'; -- Read High byte from "Read register" to Data bus
cs3fx_n 		<='0' when (WR_N='0' and A(7 downto 0)="10101011" and IORQ_N='0') and ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) and HDD_OFF = '0' else '1';
cs1fx_n 		<= rww_n and wwe_n; 

ACTIVE 	<= not(wwc_n and wwe_n and rww_n and rwe_n) or not(WRH and IOW and IOR and RDH);

--  Nemo HDD
cs_nemo_ports <= '1' when (A(7 downto 0) = x"F0" or 
									A(7 downto 0) = x"D0" or 
									A(7 downto 0) = x"B0" or 
									A(7 downto 0) = x"90" or 
									A(7 downto 0) = x"70" or 
									A(7 downto 0) = x"50" or 
									A(7 downto 0) = x"30" or 
									A(7 downto 0) = x"10" or 
									A(7 downto 0) = x"C8" or 
									A(7 downto 0) = x"11") and IORQ_N = '0' and CPM = '0' else '0'; 

nemo_ebl_n <= '0' when cs_nemo_ports = '1' and M1_N='1' and NEMOIDE_EN = '1' else '1';
IOW <='0' when A(2 downto 0)="000" and M1_N='1' and IORQ_N='0' and CPM='0' and WR_N='0' else '1';
WRH <='0' when A(2 downto 0)="001" and M1_N='1' and IORQ_N='0' and CPM='0' and WR_N='0' else '1';
IOR <='0' when A(2 downto 0)="000" and M1_N='1' and IORQ_N='0' and CPM='0' and RD_N='0' else '1';
RDH <='0' when A(2 downto 0)="001" and M1_N='1' and IORQ_N='0' and CPM='0' and RD_N='0' else '1';
nemo_cs0 <= A(3) when nemo_ebl_n='0' else '1';
nemo_cs1 <= A(4) when nemo_ebl_n='0' else '1';
nemo_ior <= ior when nemo_ebl_n='0' else '1';

-----------------HDD------------------
cs_hdd_wr <= cs3fx_n and wwe_n and wwc_n;
cs_hdd_rd <= rww_n and rwe_n; -- IOR and RDH (0 active) OK

process (CLK,A,WR_N,RD_N,cs1fx_n,cs3fx_n,RESET,profi_ebl_n, nemo_ebl_n)
begin
	if RESET = '1' then
		IDE_WR_N <='1';
		IDE_RD_N <='1';
		IDE_CS_N <= "11";
		IDE_A <= "000";
	elsif CLK'event and CLK='0' then
		if (profi_ebl_n = '0') then 
			IDE_A <= A(10 downto 8);
			IDE_WR_N <= WR_N;
			IDE_RD_N <= RD_N;
			IDE_CS_N <= cs3fx_n & cs1fx_n;
		elsif (nemo_ebl_n = '0') then
			IDE_A <= A(7 downto 5);
			IDE_WR_N <= iow;
			IDE_RD_N <= nemo_ior;
			IDE_CS_N <= nemo_cs1 & nemo_cs0;
		else
			IDE_A <= "000";
			IDE_WR_N <= '1';
			IDE_RD_N <= '1';
			IDE_CS_N <= "11";
		end if;  
  end if;
end process;

process (CLK, rww_n, wd_reg_in,cs_hdd_wr,RESET,profi_ebl_n)
begin
	if RESET = '1' then
		IDE_D(7 downto 0) <= "11111111";	
	elsif CLK'event and CLK='1' then
		if (rww_n='1' and cs_hdd_wr='0' and profi_ebl_n='0') or (rww_n='1' and nemo_ebl_n= '0') then
			IDE_D(7 downto 0) <= DI;
		else 
			IDE_D(7 downto 0) <= "ZZZZZZZZ";
		end if;
	end if;
end process;

process (cs1fx_n, IDE_D)
begin
		if cs1fx_n'event and cs1fx_n='1' then 
			wd_reg_out (15 downto 8) <= IDE_D(15 downto 8);
		end if;
end process;

process (wwc_n, DI)
begin
		if wwc_n'event and wwc_n='1' then   -- wwc=WRH write high byte to latch from z80 -- OK
			wd_reg_in (15 downto 8) <= DI;
		end if;
end process;

IDE_D (15 downto 8) <= wd_reg_in (15 downto 8) when wwe_n='0' else "ZZZZZZZZ"; -- wwe=IOW write to high byte HDD from latch -- OK

DO <= IDE_D(7 downto 0) when rww_n='0' else -- rww=IOR - read low byte from HDD -- OK
			wd_reg_out (15 downto 8) when rwe_n='0' else "11111111"; -- rwe=RDH - read high byte from HDD -- OK
	
OE_N <= cs_hdd_rd; --OCH OK

IDE_RESET_N <= not RESET;

end rtl;
