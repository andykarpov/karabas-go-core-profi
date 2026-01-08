-------------------------------------------------------------------[04.06.2014]
-- SDRAM Controller
-------------------------------------------------------------------------------
-- Engineer: MVV

-- CLK		= 84 MHz	= 11,9047619047619 ns
-- WR/RD		= 6T		= 71,42857142857143 ns
-- RFSH		= 6T		= 71,42857142857143 ns

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity sdram is
	port(
		CLK				: in std_logic;
		-- Memory port
		A				: in std_logic_vector(24 downto 0);
		DI				: in std_logic_vector(7 downto 0);
		DO				: out std_logic_vector(7 downto 0);
		WR				: in std_logic;
		RD				: in std_logic;
		RFSH			: in std_logic;
		IDLE			: buffer std_logic;
		-- SDRAM Pin
		RAS_n			: out std_logic;
		CAS_n			: out std_logic;
		WE_n			: out std_logic;
		DQM			: out std_logic_vector(1 downto 0);
		BA				: out std_logic_vector(1 downto 0);
		MA				: out std_logic_vector(12 downto 0);
		DQ				: inout std_logic_vector(15 downto 0) );
end sdram;

architecture rtl of sdram is

	signal state 		: unsigned(4 downto 0) := "00000";
	signal address 		: std_logic_vector(24 downto 0);
	signal data_reg		: std_logic_vector(7 downto 0);
	signal data			: std_logic_vector(7 downto 0);	
	signal idle1		: std_logic;
	
	-- SD-RAM control signals
	signal sdr_cmd		: std_logic_vector(2 downto 0);
	signal sdr_ba		: std_logic_vector(1 downto 0);
	signal sdr_dqm		: std_logic_vector(1 downto 0);
	signal sdr_a		: std_logic_vector(12 downto 0);
	signal sdr_dq		: std_logic_vector(15 downto 0);
	
	constant SdrCmd_xx 	: std_logic_vector(2 downto 0) := "111"; -- no operation
	constant SdrCmd_ac 	: std_logic_vector(2 downto 0) := "011"; -- activate
	constant SdrCmd_rd 	: std_logic_vector(2 downto 0) := "101"; -- read
	constant SdrCmd_wr 	: std_logic_vector(2 downto 0) := "100"; -- write		
	constant SdrCmd_pr 	: std_logic_vector(2 downto 0) := "010"; -- precharge all
	constant SdrCmd_re 	: std_logic_vector(2 downto 0) := "001"; -- refresh
	constant SdrCmd_ms 	: std_logic_vector(2 downto 0) := "000"; -- mode regiser set

-- Init----------------------------------------------------------  Idle      Read----------  Write---------  Refresh-------
-- 00 01 02 03 04 05 06 07 08 09 0A 0B 0C 0D 0E 0F 10 11 12 13 14  15        16 17 12 13 14  18 19 12 13 14  10 11 12 13 14
-- pr xx xx re xx xx xx xx xx re xx xx xx xx xx ms xx xx xx xx xx  xx/ac/re  xx rd xx xx xx  xx wr xx xx xx  xx xx xx xx xx

begin
	process (CLK)
	begin
		if CLK'event and CLK = '0' then
			case state is
				-- Init
				when "00000" =>						-- s00
					sdr_cmd <= SdrCmd_pr;			-- PRECHARGE
					sdr_a <= "1111111111111";
					sdr_ba <= "00";
					sdr_dqm <= "11";
					state <= state + 1;
				when "00011" | "01001" =>			-- s03 s09
					sdr_cmd <= SdrCmd_re;			-- REFRESH
					state <= state + 1;
				when "01111" =>						-- s0F
					sdr_cmd <= SdrCmd_ms;			-- LOAD MODE REGISTER
					sdr_a <= "000" & "1" & "00" & "010" & "0" & "000";				
					state <= state + 1;
				
				-- Idle
				when "10101" =>						-- s15
					sdr_cmd <= SdrCmd_xx;			-- NOP
					sdr_dq <= (others => 'Z');
					idle1 <= '1';
					if RD = '1' then
						idle1 <= '0';
						address <= A;
						sdr_cmd <= SdrCmd_ac;		-- ACTIVE
						sdr_ba <= A(11 downto 10);
						sdr_a <= A(24 downto 12);					 
						state <= "10110";			-- s16 Read
					elsif WR = '1' then
						idle1 <= '0';
						address <= A;
						data <= DI;
						sdr_cmd <= SdrCmd_ac;		-- ACTIVE
						sdr_ba <= A(11 downto 10);
						sdr_a <= A(24 downto 12);
						state <= "11000";			-- s18 Write
					elsif RFSH = '1' then
						idle1 <= '0';
						sdr_cmd <= SdrCmd_re;		-- REFRESH
						state <= "10000";			-- s10
					end if;

				-- A24 A23 A22 A21 A20 A19 A18 A17 A16 A15 A14 A13 A12 A11 A10 A9 A8 A7 A6 A5 A4 A3 A2 A1 A0
				-- -----------------------ROW------------------------- BA1 BA0 ----------COLUMN---------- HL		

				-- Single read - with auto precharge
				when "10111" =>						-- s17
					sdr_cmd <= SdrCmd_rd;			-- READ (A10 = 1 enable auto precharge; A8..0 = column)
					sdr_a <= "0010" & address(9 downto 1);
					sdr_dqm <= "00";
					state <= "10010";				-- s12
					
				-- Single write - with auto precharge
				when "11001" =>						-- s19
					sdr_cmd <= SdrCmd_wr;			-- WRITE (A10 = 1 enable auto precharge; A8..0 = column)
					sdr_a <= "0010" & address(9 downto 1);
					sdr_dq <= data & data;
					sdr_dqm <= not address(0) & address(0);
					state <= "10010";				-- s12
					
				when others =>
					sdr_dq <= (others => 'Z');
					sdr_cmd <= SdrCmd_xx;			-- NOP
					state <= state + 1;
			end case;
		end if;
	end process;
	
	process (CLK, state, DQ, data_reg, idle1)
	begin
		if CLK'event and CLK = '1' and idle1 = '0' then
			if state = "10100" then					-- s14
				if address(0) = '0' then
					data_reg <= DQ(7 downto 0);
				else
					data_reg <= DQ(15 downto 8);
				end if;
			end if;
		end if;
	end process;
	
	IDLE	<= idle1;
	DO 		<= data_reg;
	RAS_n 	<= sdr_cmd(2);
	CAS_n 	<= sdr_cmd(1);
	WE_n 	<= sdr_cmd(0);
	DQM 	<= sdr_dqm;
	BA	 	<= sdr_ba;
	MA 		<= sdr_a;
	DQ 		<= sdr_dq;

end rtl;