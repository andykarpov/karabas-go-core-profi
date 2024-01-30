-------------------------------------------------------------------------------
-- IDE controller module
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all;


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
	IDE_RESET_N : out std_logic;
	IDE_BUSY 	: buffer std_logic
);
end ide_controller;

architecture rtl of ide_controller is 

-- Profi HDD ports

signal cs_profi_ports : std_logic := '0';
signal profi_ebl_n	:std_logic := '1';
signal profi_wrh_n	:std_logic := '1';
signal profi_iow_n	:std_logic := '1';
signal profi_ior_n	:std_logic := '1';
signal profi_rdh_n	:std_logic := '1';
signal cs3fx_n			:std_logic := '1';
signal cs1fx_n			:std_logic := '1';

-- Nemo HDD ports
signal cs_nemo_ports		: std_logic := '0';
signal nemo_ebl_n			: std_logic := '1';
signal nemo_iow_n			: std_logic := '1';
signal nemo_wrh_n 		: std_logic := '1';
signal nemo_ior_n 		: std_logic := '1';
signal nemo_rdh_n 		: std_logic := '1';

-- data latches
signal wd_reg_in	: std_logic_vector(15 downto 0);
signal wd_reg_out	: std_logic_vector(15 downto 0);

-- state machine
type qmachine IS(idle, rd_wr_on, rd_wr_2, rd_wr_3, cs_off, finish );
signal qstate : qmachine := idle;

-- r/w latches
signal rd_r, wr_r : std_logic;

-- address helpers
signal loa, hia : std_logic_vector(7 downto 0);

begin 

loa <= A(7 downto 0);
hia <= A(15 downto 8);

-- Profi HDD ports description:
-- PP_1F7W		EQU 0X07EB			;W РЕГИСТР КОМАНД
-- PP_1F7R		EQU 0X07CB			;R РЕГИСТР СОСТОЯНИЯ
-- PP_1F6W		EQU 0X06EB			;W CHS-НОМЕР ГОЛОВЫ И УСТР/LBA АДРЕС 24-27
-- PP_1F6R		EQU 0X06CB			;R CHS-НОМЕР ГОЛОВЫ И УСТР/LBA АДРЕС 24-27
-- PP_1F5W		EQU 0X05EB			;W CHS-ЦИЛИНДР 8-15/LBA АДРЕС 16-23
-- PP_1F5R		EQU 0X05CB			;R CHS-ЦИЛИНДР 8-15/LBA АДРЕС 16-23
-- PP_1F4W		EQU 0X04EB			;W CHS-ЦИЛИНДР 0-7/LBA АДРЕС 8-15
-- PP_1F4R		EQU 0X04CB			;R CHS-ЦИЛИНДР 0-7/LBA АДРЕС 8-15
-- PP_1F3W		EQU 0X03EB			;W CHS-НОМЕР СЕКТОРА/LBA АДРЕС 0-7
-- PP_1F3R		EQU 0X03CB			;R CHS-НОМЕР СЕКТОРА/LBA АДРЕС 0-7
-- PP_1F2W		EQU 0X02EB			;W СЧЕТЧИК СЕКТОРОВ
-- PP_1F2R		EQU 0X02CB			;R СЧЕТЧИК СЕКТОРОВ
-- PP_1F1W		EQU 0X01EB			;W ПОРТ СВОЙСТВ
-- PP_1F1R		EQU 0X01CB			;R ПОРТ ОШИБОК
-- PP_1F0W		EQU 0X00EB			;W ПОРТ ДАННЫХ МЛАДШИЕ 8 БИТ
-- PP_1F0R		EQU 0X00CB			;R ПОРТ ДАННЫХ МЛАДШИЕ 8 БИТ
-- PP_3F6		EQU 0X06AB			;W РЕГИСТР СОСТОЯНИЯ/УПРАВЛЕНИЯ
-- PP_HIW		EQU 0XFFCB			;W ПОРТ ДАННЫХ СТАРШИЕ 8 БИТ
-- PP_HIR		EQU 0XFFEB			;R ПОРТ ДАННЫХ СТАРШИЕ 8 БИТ

--  Profi HDD ports: AB, CB, EB
cs_profi_ports <= '1' when (loa = x"AB" or loa = x"CB" or loa = x"EB") and IORQ_N='0' and HDD_OFF = '0' and
							  ((CPM='1' and ROM14='1') or (DOS='1' and ROM14='0')) else '0';
profi_ebl_n	<='0' when cs_profi_ports = '1' and M1_N = '1' else '1';				 						 -- Profi HDD ports access
profi_iow_n <='0' when (WR_N='0' and loa=x"EB" and hia <= x"07" and profi_ebl_n = '0') else '1'; -- Write Cycle 
profi_wrh_n <='0' when (WR_N='0' and loa=x"CB" and profi_ebl_n = '0') else '1'; 						 -- Write High byte from Data bus to "Write register"
profi_ior_n <='0' when (RD_N='0' and loa=x"CB" and hia <= x"07" and profi_ebl_n = '0') else '1'; -- Read Cycle
profi_rdh_n <='0' when (RD_N='0' and loa=x"EB" and profi_ebl_n = '0') else '1'; 						 -- Read High byte from "Read register" to Data bus
cs3fx_n 		<='0' when (WR_N='0' and loa=x"AB" and hia  = x"06" and profi_ebl_n = '0') else '1'; -- select CF register 8-15
cs1fx_n 		<= profi_ior_n and profi_iow_n; 																		 -- select CF register 0-7

--  Nemo HDD ports: 10, 30, 50, 70, 90, B0, D0, F0, C8, 11
cs_nemo_ports <= '1' when (loa = x"F0" or loa = x"D0" or loa = x"B0" or loa = x"90" or loa = x"70" or 
								   loa = x"50" or loa = x"30" or loa = x"10" or loa = x"C8" or loa = x"11") and 
								  IORQ_N = '0' and CPM = '0' else '0';
nemo_ebl_n <='0' when cs_nemo_ports = '1' and M1_N='1' and NEMOIDE_EN = '1' else '1'; -- Nemo HDD ports access
nemo_iow_n <='0' when A(2 downto 0)="000" and nemo_ebl_n = '0' and WR_N='0' else '1'; -- Write Cycle
nemo_wrh_n <='0' when A(2 downto 0)="001" and nemo_ebl_n = '0' and WR_N='0' else '1'; -- Write High byte from Data bus to "Write register"
nemo_ior_n <='0' when A(2 downto 0)="000" and nemo_ebl_n = '0' and RD_N='0' else '1'; -- Read Cycle
nemo_rdh_n <='0' when A(2 downto 0)="001" and nemo_ebl_n = '0' and RD_N='0' else '1'; -- Read High byte from "Read register" to Data bus

-- CF FSM
-- https://github.com/tslabs/zx-evo/blob/master/pentevo/docs/IDE/pio_timings.PNG
process (CLK, RESET)
begin
	if RESET = '1' then
		IDE_WR_N <='1';
		IDE_RD_N <='1';
		IDE_CS_N <= "11";
		IDE_A <= "000";
      qstate <= idle;
		IDE_D <= (others => 'Z');
		IDE_BUSY <= '0';
	elsif CLK'event and CLK='1' then
        
        case qstate is
            when idle => 
                IDE_RD_N <= '1';
                IDE_WR_N <= '1';
                IDE_CS_N <= "11";
                IDE_A <= "000";
					 IDE_D <= (others => 'Z');
					 IDE_BUSY <= '0';
					 wr_r <= '1';
					 rd_r <= '1';

                if profi_ebl_n = '0' and (profi_iow_n = '0' or profi_ior_n = '0' or cs3fx_n = '0') then -- profi r/w cycle start
                    IDE_A <= A(10 downto 8); -- set address
						  IDE_BUSY <= '1';
                    IDE_CS_N <= cs3fx_n & cs1fx_n; -- set cs active
                    wr_r <= WR_N; -- latch rd, wr signals
                    rd_r <= RD_N;
						  if (profi_iow_n = '0' or cs3fx_n = '0') then -- fill input register
								wd_reg_in(7 downto 0) <= DI;
						  end if;
                    qstate <= rd_wr_on;

                elsif nemo_ebl_n = '0' and (nemo_iow_n = '0' or nemo_ior_n = '0') then -- nemo r/w cycle start
                    IDE_A <= A(7 downto 5); -- set address
						  IDE_BUSY <= '1';
                    IDE_CS_N <= A(4 downto 3); -- set cs active
                    wr_r <= nemo_iow_n; -- latch rd, wr signals
                    rd_r <= nemo_ior_n;
						  if (nemo_iow_n = '0') then -- fill input register
								wd_reg_in(7 downto 0) <= DI;
						  end if;
						  qstate <= rd_wr_on;
                end if;

            when rd_wr_on => -- set rd / wr signals
                IDE_RD_N <= rd_r;
                IDE_WR_N <= wr_r;
					 if (wr_r = '0') then -- push write reg to IDE bus
						IDE_D <= wd_reg_in;
					 end if;
                qstate <= rd_wr_2;

            when rd_wr_2 => -- wait r/w					
               qstate <= rd_wr_3;

            when rd_wr_3 =>

					if rd_r = '0' then
						wd_reg_out <= IDE_D; -- latch reading from IDE
					 end if;
					
                IDE_RD_N <= '1'; -- set rd/wr inactive
                IDE_WR_N <= '1';
               qstate <= cs_off;

            when cs_off =>
				
                IDE_CS_N <= "11"; -- set cs inactive
                qstate <= finish;

				when finish => 
					IDE_D <= (others => 'Z');
					IDE_BUSY <= '0';
					if (RD_N = '1' and WR_N = '1' and IORQ_N = '1') then -- goto idle only when cpu io r/w cycle is complete
						qstate <= idle;
					end if;

            when others => 
                qstate <= idle;    
        end case;
  end if;
end process;

-- latch high byte from z80 (profi/nemo)
process (profi_wrh_n, nemo_wrh_n, DI)
begin
		if profi_wrh_n'event and profi_wrh_n = '1' then
				wd_reg_in (15 downto 8) <= DI;
		elsif nemo_wrh_n'event and nemo_wrh_n = '1' then
				wd_reg_in (15 downto 8) <= DI;
		end if;
end process;

-- data output to z80
DO <= wd_reg_out(7 downto 0) when (profi_ior_n = '0' or nemo_ior_n = '0') else
		wd_reg_out(15 downto 8) when profi_rdh_n = '0' or nemo_rdh_n = '0' else 
		"11111111";
		
OE_N <= '0' when ((profi_ior_n = '0' or nemo_ior_n = '0')) or 
					  ((profi_rdh_n = '0' or nemo_rdh_n = '0')) 
					  else '1';

-- to display CF access in the OSD
ACTIVE 	<= not(profi_wrh_n and profi_iow_n and profi_ior_n and profi_rdh_n) or not(nemo_wrh_n and nemo_iow_n and nemo_ior_n and nemo_rdh_n);

-- ide reset
IDE_RESET_N <= not RESET;

end rtl;
