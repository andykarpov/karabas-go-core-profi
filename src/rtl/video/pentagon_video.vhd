-------------------------------------------------------------------------------
-- VIDEO Pentagon mode
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity pentagon_video is
	generic (
		TEST : integer := 0
	);
	port (
		CLK 		: in std_logic; -- 7 MHz
		VMODE		: in std_logic_vector(3 downto 0);
		
		BORDER	: in std_logic_vector(2 downto 0);	-- bordr color (port #xxFE)
		TURBO 	: in std_logic_vector(2 downto 0) := "000"; -- 01 = turbo 2x mode, 10 - turbo 4x mode, 11 - turbo 8x mode, 00 = normal mode
		INTA		: in std_logic := '0'; -- int request for turbo mode
		INT		: out std_logic; -- int output
		pFF_CS	: out std_logic; -- port FF select
		ATTR_O	: out std_logic_vector(7 downto 0); -- attribute register output

		DI			: in std_logic_vector(7 downto 0);	-- video data from memory
		A			: out std_logic_vector(13 downto 0); -- video address
		VID_RD 	: out std_logic;
		
		RGB		: out std_logic_vector(2 downto 0);	-- RGB
		I			: out std_logic; -- brightness
		HSYNC		: out std_logic;
		VSYNC		: out std_logic;
		BLANK 	: out std_logic;

		ACTIVE 	: out std_logic;
		LOCK 		: out std_logic;		

		COUNT_BLOCK : out std_logic		
	);
end entity;

architecture rtl of pentagon_video is

	signal mode60 : std_logic;
	signal screen_mode : std_logic_vector(1 downto 0);

	signal hcnt: std_logic_vector(9 downto 0);
	signal vcnt: std_logic_vector(8 downto 0);	

	signal invert   : unsigned(4 downto 0) := "00000";	-- Flash counter

	signal chr_col_cnt : unsigned(2 downto 0) := "000"; -- Character column counter
	signal chr_row_cnt : unsigned(2 downto 0) := "000"; -- Character row counter

	signal hor_cnt  : unsigned(5 downto 0) := "000000"; -- Horizontal char counter
	signal ver_cnt  : unsigned(5 downto 0) := "000000"; -- Vertical char counter

	signal vid_reg  : std_logic_vector(7 downto 0);	
	signal attr     : std_logic_vector(7 downto 0);
	signal bitmap   : std_logic_vector(7 downto 0);
	
	signal paper_r  : std_logic;
	signal blank_r  : std_logic;
	signal attr_r   : std_logic_vector(7 downto 0);

	signal shift_r  : std_logic_vector(7 downto 0);
	signal shift_hr_r : std_logic_vector(15 downto 0);

	signal paper     : std_logic;
	
	signal VIDEO_R 	: std_logic;
	signal VIDEO_G 	: std_logic;
	signal VIDEO_B 	: std_logic;
	signal VIDEO_I 	: std_logic;	
		
	signal int_sig : std_logic;
	signal bl_int 			: std_logic;
		
begin

	mode60 <= vmode(0);
	screen_mode <= vmode(2 downto 1);

	-- sync, counters
	process( CLK, chr_col_cnt, hor_cnt, chr_row_cnt, ver_cnt, TURBO, INTA)
	begin
		if rising_edge(CLK) then
			if chr_col_cnt = 7 then
			
				if hor_cnt = 55 then -- 447 (448 pixes in line)
					hor_cnt <= (others => '0');
				else
					hor_cnt <= hor_cnt + 1;
				end if;
				
				if hor_cnt = 39 then
					if chr_row_cnt = 7 then
						if (ver_cnt = 39 and MODE60 = '0' and SCREEN_MODE = "00") or -- pentagon 50 Hz -- 319 (320 lines)
							(ver_cnt = 32 and MODE60 = '1' and SCREEN_MODE = "00") or -- pentagon 60 Hz -- 263 (264 lines)
							(ver_cnt = 38 and MODE60 = '0' and SCREEN_MODE = "01") or -- classic 50 Hz  -- 311 (312 lines)
							(ver_cnt = 31 and MODE60 = '1' and SCREEN_MODE = "01")    -- classic 60 Hz  -- 255 (256 lines)
						then
							ver_cnt <= (others => '0');
							invert <= invert + 1;
						else
							ver_cnt <= ver_cnt + 1;
						end if;
					end if;
					chr_row_cnt <= chr_row_cnt + 1;
				end if;
			end if;

			-- h/v sync

			if chr_col_cnt = 7 then

				if (hor_cnt(5 downto 2) = "1010") then 
					HSYNC <= '0';
				else 
					HSYNC <= '1';
				end if;
				
				if (ver_cnt /= 31 and MODE60 = '0') or (ver_cnt /= 27 and MODE60 = '1') then
					VSYNC <= '1';
				elsif chr_row_cnt = 3 or chr_row_cnt = 4 or ( chr_row_cnt = 5 and ( hor_cnt >= 40 or hor_cnt < 12 ) ) then
					VSYNC<= '0';
				else 
					VSYNC <= '1';
				end if;
				
			end if;
		
			case TURBO is
				when "000" => -- TURBO OFF
					-- PENTAGON int
				if (SCREEN_MODE = "00") then 
					if chr_col_cnt = 6 and hor_cnt(2 downto 0) = "111" then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 3) = "100" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
				-- CLASSIC int
				elsif (SCREEN_MODE = "01") then 
					if chr_col_cnt = 0 then
						if ver_cnt = 31 and chr_row_cnt = 0 and hor_cnt(5 downto 3) = "000" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
				end if;

				when "001" => -- TURBO 2x
					if chr_col_cnt = 6 and hor_cnt(1 downto 0) = "11" then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 2) = "1001" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
					
				when "010" => -- TURBO 4x
					if chr_col_cnt = 6 and hor_cnt(0) = '1' then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 1) = "10011" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;
					
				when "011" => -- TURBO 8x
					if chr_col_cnt = 6 then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 0) = "100111" then
							int_sig <= '0';
						else
							int_sig <= '1';
						end if;
					end if;

				when others => -- TURBO 16x and up
					if chr_col_cnt = 6 or chr_col_cnt = 2 then
						if ver_cnt = 29 and chr_row_cnt = 7 and hor_cnt(5 downto 0) = "100111" and chr_col_cnt = 6 then
							int_sig <= '0';
						elsif chr_col_cnt = 2 then
							int_sig <= '1';
						end if;
					end if;
			end case;

			chr_col_cnt <= chr_col_cnt + 1;
		end if;
	end process;

	-- r/g/b/i
	process( CLK, paper_r, shift_r, attr_r, invert, blank_r, BORDER )
	begin
		if rising_edge(CLK) then
			ACTIVE <= '0';
			if paper_r = '0' then -- paper
				ACTIVE <= '1';
					-- standard RGB
					if TEST = 1 then
						VIDEO_R <= hcnt(5);
						VIDEO_G <= hcnt(6);
						VIDEO_B <= hcnt(7);
						VIDEO_I <= hcnt(4);
					else
						if( shift_r(7) xor ( attr_r(7) and invert(4) ) ) = '1' then -- fg pixel
							VIDEO_B <= attr_r(0);
							VIDEO_R <= attr_r(1);
							VIDEO_G <= attr_r(2);
						else	-- bg pixel
							VIDEO_B <= attr_r(3);
							VIDEO_R <= attr_r(4);
							VIDEO_G <= attr_r(5);
						end if;
						VIDEO_I <= attr_r(6);
					end if;
			else -- not paper
				if blank_r = '0' then
					-- blank
					VIDEO_B <= '0';
					VIDEO_R <= '0';
					VIDEO_G <= '0';
					VIDEO_I <= '0';
				else -- std border
					-- standard RGB
					VIDEO_B <= BORDER(0);
					VIDEO_R <= BORDER(1);
					VIDEO_G <= BORDER(2);
					VIDEO_I <= '0';
					ACTIVE <= '1';
				end if;
			end if;
		end if;
	end process;

	-- paper, blank
	process( CLK, chr_col_cnt, hor_cnt, ver_cnt, shift_hr_r, attr, bitmap, paper, shift_r )
	begin
		if rising_edge(CLK) then
			if chr_col_cnt = 7 then
				-- PENTAGON blank
				if SCREEN_MODE = "00" and (
					(hor_cnt(5 downto 0) > 38 and hor_cnt(5 downto 0) < 48) or 
					((ver_cnt(5 downto 1) = 15 and MODE60 = '0') or 
					 (ver_cnt(5 downto 1) = 14 and MODE60 = '1'))) then	-- 15 = for 320 lines, 13 = for 264 lines
					blank_r <= '0';
				-- CLASSIC blank
				elsif SCREEN_MODE = "01" and (
					hor_cnt(5 downto 2) = 10 or hor_cnt(5 downto 2) = 11 or 
					(ver_cnt = 31 and MODE60 = '0') or 
					(ver_cnt = 30 and MODE60 = '1')) then
					blank_r <= '0';
				else 
					blank_r <= '1';
				end if;							
				paper_r <= paper;
			end if;
		end if;
	end process;	
	
	-- bitmap shift registers
	process( CLK, chr_col_cnt, hor_cnt, ver_cnt, shift_hr_r, attr, bitmap, paper, shift_r )
	begin
		if rising_edge(CLK) then
			-- standard shift register 
			if chr_col_cnt = 7 then
				attr_r <= attr;
				shift_r <= bitmap;
			else
				shift_r(7 downto 1) <= shift_r(6 downto 0);
				shift_r(0) <= '0';
			end if;
		end if;
	end process;
	
	-- video mem read cycle
	process (CLK, chr_col_cnt)
	begin 
		if rising_edge(CLK) then 
			case chr_col_cnt is 
				when "001" => VID_RD <= '0'; A <= std_logic_vector( '0' & ver_cnt(4 downto 3) & chr_row_cnt & ver_cnt(2 downto 0) & hor_cnt(4 downto 0));
				when "010" => bitmap <= DI;
				when "011" => VID_RD <= '1'; A <= std_logic_vector( '0' & "110" & ver_cnt(4 downto 0) & hor_cnt(4 downto 0));
				when "100" => attr <= DI;
				when others => null;
			end case;
		end if;
	end process;
	
	paper <= '0' when hor_cnt(5) = '0' and ver_cnt(5) = '0' and ( ver_cnt(4) = '0' or ver_cnt(3) = '0' ) else '1';
	
	RGB <= VIDEO_R & VIDEO_G & VIDEO_B;
	I <= VIDEO_I;
	pFF_CS	<= not paper;
	ATTR_O	<= attr_r;

	INT <= int_sig;
	
	HCNT <= '0' & std_logic_vector(hor_cnt) & std_logic_vector(chr_col_cnt);
	VCNT <= std_logic_vector(ver_cnt) & std_logic_vector(chr_row_cnt);
	
	COUNT_BLOCK <= '1' when paper = '0' and (chr_col_cnt(2) = '0' or hor_cnt(0) = '0') else '0';

	-- end of hdmi frame strobe (h/v blank start)
	LOCK 		 <= '1' when HCNT = 383 and VCNT = 255 and MODE60 = '0' and SCREEN_MODE = "00" else -- pentagon 50Hz 448x320
					 '1' when HCNT = 383 and VCNT = 255 and MODE60 = '1' and SCREEN_MODE = "00" else -- pentagon 60Hz 448x264
					 '1' when HCNT = 383 and VCNT = 255 and MODE60 = '0' and SCREEN_MODE /= "00" else -- classic 50Hz  448x312
					 '1' when HCNT = 383 and VCNT = 255 and MODE60 = '1' and SCREEN_MODE /= "00" else -- classic 60Hz  448x256
					 '0';
	
	BLANK <= blank_r;

end architecture;