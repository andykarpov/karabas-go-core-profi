-------------------------------------------------------------------[14.07.2014]
-- VIDEO Pentagon or Spectrum mode
-------------------------------------------------------------------------------
-- V0.1 	05.10.2011	первая версия
-- V0.2 	11.10.2011	RGB, CLKEN
-- V0.3 	19.12.2011	INT
-- V0.4 	20.05.2013	изменены параметры растра для режима Video 15КГц
-- V0.5 	20.07.2013	изменено формирование сигнала INT, FLASH
-- V0.6	09.03.2014	изменены параметры для режима pentagon 48K, добавлена рамка
-- V0.7	14.07.2014	добавлен сигнал BLANK

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	port (
		CLK		: in std_logic;							-- системная частота
		ENA		: in std_logic_vector(1 downto 0);
		INTA		: in std_logic;
		INT		: out std_logic;
		DS80		: in std_logic;
		BORDER	: in std_logic_vector(2 downto 0);	-- цвет бордюра (порт #xxFE)
		BORDON	: out std_logic;
		ATTR		: out std_logic_vector(7 downto 0);
		A			: out std_logic_vector(13 downto 0);
		DI			: in std_logic_vector(7 downto 0);
		DIPIX		: in std_logic_vector(7 downto 0);
		DIATR		: in std_logic_vector(7 downto 0);
		MODE		: in std_logic_vector(1 downto 0);	-- ZX видео режим 0: Spectrum; 1: Pentagon
		BLANK		: out std_logic;							-- BLANK
		RGB		: out std_logic_vector(5 downto 0);	-- RRGGBB
		HSYNC		: out std_logic;
		VSYNC		: out std_logic);
end entity;

architecture rtl of video is

-- pentagon	48K screen mode
	constant pent_screen_h		: natural := 256;
	constant pent_border_right	: natural :=  72;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек больше 
	constant pent_blank_front	: natural :=   8;
	constant pent_sync_h			: natural :=  48;
	constant pent_blank_back	: natural :=   8;
	constant pent_border_left	: natural :=  56;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек меньше

	constant pent_screen_v		: natural := 192;
	constant pent_border_bot	: natural :=  48;
	constant pent_blank_down	: natural :=   6;
	constant pent_sync_v			: natural :=   4;
	constant pent_blank_up		: natural :=   6;
	constant pent_border_top	: natural :=  64;

	constant pent_h_blank_on	: natural := (pent_screen_h + pent_border_right) - 1;
	constant pent_h_sync_on		: natural := (pent_screen_h + pent_border_right + pent_blank_front) - 1;
	constant pent_h_sync_off	: natural := (pent_screen_h + pent_border_right + pent_blank_front + pent_sync_h);
	constant pent_h_blank_off	: natural := (pent_screen_h + pent_border_right + pent_blank_front + pent_sync_h + pent_blank_back);
	constant pent_h_end_count	: natural := 447;

	constant pent_v_blank_on	: natural := (pent_screen_v + pent_border_bot) - 1;
	constant pent_v_sync_on		: natural := (pent_screen_v + pent_border_bot + pent_blank_down) - 1;
	constant pent_v_sync_off	: natural := (pent_screen_v + pent_border_bot + pent_blank_down + pent_sync_v);
	constant pent_v_blank_off	: natural := (pent_screen_v + pent_border_bot + pent_blank_down + pent_sync_v + pent_blank_up);
	constant pent_v_end_count	: natural := 319;

	constant pent_h_int_on		: natural := pent_h_blank_on - 8;	-- 319 (-8 точек компенсация на выравнивании)
	constant pent_v_int_on		: natural := pent_v_blank_on;			-- 239

	
	
-- Profi-spectum screen mode
	constant pspec_scr_h			: natural := 256;
	constant pspec_brd_right	: natural :=  24;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек больше
	constant pspec_blk_front	: natural :=  56;
	constant pspec_sync_h		: natural :=  32;
	constant pspec_blk_back		: natural :=  72;
	constant pspec_brd_left		: natural :=   8;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек меньше

	constant pspec_scr_v			: natural := 192;
	constant pspec_brd_bot		: natural :=  16;
	constant pspec_blk_down		: natural :=  56;--24
	constant pspec_sync_v		: natural :=  16;
	constant pspec_blk_up		: natural :=  24;--56
	constant pspec_brd_top		: natural :=  16;

	constant pspec_h_blk_on		: natural := (pspec_scr_h + pspec_brd_right) - 1;
	constant pspec_h_sync_on	: natural := (pspec_scr_h + pspec_brd_right + pspec_blk_front) - 1;
	constant pspec_h_sync_off	: natural := (pspec_scr_h + pspec_brd_right + pspec_blk_front + pspec_sync_h);
	constant pspec_h_blk_off	: natural := (pspec_scr_h + pspec_brd_right + pspec_blk_front + pspec_sync_h + pspec_blk_back);
	constant pspec_h_end			: natural := 447;

	constant pspec_v_blk_on		: natural := (pspec_scr_v + pspec_brd_bot) - 1;
	constant pspec_v_sync_on	: natural := (pspec_scr_v + pspec_brd_bot + pspec_blk_down) - 1;
	constant pspec_v_sync_off	: natural := (pspec_scr_v + pspec_brd_bot + pspec_blk_down + pspec_sync_v);
	constant pspec_v_blk_off	: natural := (pspec_scr_v + pspec_brd_bot + pspec_blk_down + pspec_sync_v + pspec_blk_up);
	constant pspec_v_end			: natural := 319;

--	constant pspec_h_int_on		: natural := pspec_sync_h+8;
--	constant pspec_v_int_on		: natural := pspec_v_blk_off - 1;
	constant pspec_h_int_on		: natural := 360;
	constant pspec_v_int_on		: natural := 239;
	constant pspec_h_int_off	: natural := 064;
	constant pspec_v_int_off	: natural := 240;
-- INT  Y239,X360  - Y240,X064



-- Profi-CPM screen mode
	constant pcpm_scr_h			: natural := 512;
	constant pcpm_brd_right		: natural :=  40;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек больше
	constant pcpm_blk_front		: natural :=  48;--32
	constant pcpm_sync_h			: natural :=  64;
	constant pcpm_blk_back		: natural :=  80;--96
	constant pcpm_brd_left		: natural :=  24;	-- для выравнивания из-за задержки на чтение vid_reg и attr_reg задано на 8 точек меньше

	constant pcpm_scr_v			: natural := 240;
	constant pcpm_brd_bot		: natural :=  8;--16
	constant pcpm_blk_down		: natural :=  40;--16
	constant pcpm_sync_v			: natural :=  16;--16
	constant pcpm_blk_up			: natural :=  8;--16
	constant pcpm_brd_top		: natural :=  8;--16

	constant pcpm_h_blk_on		: natural := (pcpm_scr_h + pcpm_brd_right) - 1;
	constant pcpm_h_sync_on		: natural := (pcpm_scr_h + pcpm_brd_right + pcpm_blk_front) - 1;
	constant pcpm_h_sync_off	: natural := (pcpm_scr_h + pcpm_brd_right + pcpm_blk_front + pcpm_sync_h);
	constant pcpm_h_blk_off		: natural := (pcpm_scr_h + pcpm_brd_right + pcpm_blk_front + pcpm_sync_h + pcpm_blk_back);
	constant pcpm_h_end			: natural := 767;

	constant pcpm_v_blk_on		: natural := (pcpm_scr_v + pcpm_brd_bot) - 1;
	constant pcpm_v_sync_on		: natural := (pcpm_scr_v + pcpm_brd_bot + pcpm_blk_down) - 1;
	constant pcpm_v_sync_off	: natural := (pcpm_scr_v + pcpm_brd_bot + pcpm_blk_down + pcpm_sync_v);
	constant pcpm_v_blk_off		: natural := (pcpm_scr_v + pcpm_brd_bot + pcpm_blk_down + pcpm_sync_v + pcpm_blk_up);
	constant pcpm_v_end			: natural := 319;

	constant pcpm_h_int_on		: natural := 752; --pspec_sync_h+8;
	constant pcpm_v_int_on		: natural := 303; --pspec_v_blk_off - 1;
	constant pcpm_h_int_off		: natural := 128;
	constant pcpm_v_int_off		: natural := 304;

-- INT  Y303,X752  - Y304,X128

---------------------------------------------------------------------------------------	

	signal h_cnt			: unsigned(9 downto 0) := (others => '0');
	signal v_cnt			: unsigned(8 downto 0) := (others => '0');
	signal paper			: std_logic;
	signal paper1			: std_logic;
	signal flash			: unsigned(4 downto 0) := (others => '0');
	signal vid_reg			: std_logic_vector(7 downto 0);
	signal pixel_reg		: std_logic_vector(7 downto 0);
	signal at_reg			: std_logic_vector(7 downto 0);	
	signal attr_reg		: std_logic_vector(7 downto 0);
	signal h_sync			: std_logic;
	signal v_sync			: std_logic;
	signal int_sig			: std_logic;
	signal blank_sig		: std_logic;
	signal scan_cnt		: std_logic_vector(9 downto 0);
	signal scan_cnt1		: std_logic_vector(9 downto 0);
	signal scan_in			: std_logic_vector(5 downto 0);
	signal scan_out		: std_logic_vector(5 downto 0);

begin


--process (DS80, h_cnt, v_cnt)
--begin
--	if (DS80'event and DS80 = '0') then
--		h_cnt <= (others => '0');
--		v_cnt <= (others => '0');
--	end if;
--end process;	
	



process (CLK)
begin
	if (CLK'event and CLK = '1') then
		if DS80 = '0' then
			if (ENA(1) = '1') then		-- 7MHz		
				if (h_cnt >= pspec_h_end and MODE(0) = '0') or (h_cnt >= pent_h_end_count and MODE(0) = '1') then
					h_cnt <= (others => '0');
				else
					h_cnt <= h_cnt + 1;
				end if;
			
				if (h_cnt = pspec_h_sync_on and MODE(0) = '0') or (h_cnt = pent_h_sync_on and MODE(0) = '1') then
					if (v_cnt = pspec_v_end and MODE(0) = '0') or (v_cnt = pent_v_end_count and MODE(0) = '1') then
						v_cnt <= (others => '0');
					else
						v_cnt <= v_cnt + 1;
					end if;
				end if;
				if (h_cnt = pspec_h_sync_on and MODE(0) = '0') or (h_cnt = pent_h_sync_on and MODE(0) = '1') then
					scan_cnt1 <= (others => '0');
				else
					scan_cnt1 <= scan_cnt1 + 1;
				end if;
				if (v_cnt = pspec_v_sync_on and MODE(0) = '0') or (v_cnt = pent_v_sync_on and MODE(0) = '1') then
					v_sync <= '0';
				elsif (v_cnt = pspec_v_sync_off and MODE(0) = '0') or (v_cnt = pent_v_sync_off and MODE(0) = '1') then
					v_sync <= '1';
				end if;

				if (h_cnt = pspec_h_sync_on and MODE(0) = '0') or (h_cnt = pent_h_sync_on and MODE(0) = '1') then
					h_sync <= '0';
				elsif (h_cnt = pspec_h_sync_off and MODE(0) = '0') or (h_cnt = pent_h_sync_off and MODE(0) = '1') then
					h_sync <= '1';
				end if;

				if ((h_cnt = pspec_h_int_on and v_cnt = pspec_v_int_on) and MODE(0)= '0') or ((h_cnt = pent_h_int_on and v_cnt = pent_v_int_on) and MODE(0) = '1') then
					flash <= flash + 1;
--					int_sig <= '0';
				elsif (INTA = '0') then
--					int_sig <= '1';
				end if;				

				if MODE(0) = '0' then
					if (h_cnt > pspec_h_int_on and v_cnt = pspec_v_int_on) or (h_cnt < pspec_h_int_off and v_cnt = pspec_v_int_off) then
						int_sig <= '0'; else	int_sig <= '1';
					end if;	
				else
					if (h_cnt = pent_h_int_on and v_cnt = pent_v_int_on) then
						int_sig <= '0';
					elsif (INTA = '0') then
						int_sig <= '1';
					end if;	
				end if;				

				case h_cnt(2 downto 0) is
					when "100" => 
						A <= std_logic_vector('0' & v_cnt(7 downto 6)) & std_logic_vector(v_cnt(2 downto 0)) & std_logic_vector(v_cnt(5 downto 3)) & std_logic_vector(h_cnt(7 downto 3));
					when "101" =>
						vid_reg <= DI;
					when "110" =>
						A <= "0110" & std_logic_vector(v_cnt(7 downto 3)) & std_logic_vector(h_cnt(7 downto 3));
					when "111" =>
						pixel_reg <= vid_reg;
						attr_reg <= DI;
						paper1 <= paper;
					when others => null;
				end case;
			end if;
		else -- CPM режим
			if (ENA(0) = '1') then		-- 7MHz			
				if (h_cnt = pcpm_h_end) then
					h_cnt <= (others => '0');
				else
					h_cnt <= h_cnt + 1;
				end if;
			
				if (h_cnt = pcpm_h_sync_on) then
					if (v_cnt = pcpm_v_end) then
						v_cnt <= (others => '0');
					else
						v_cnt <= v_cnt + 1;
					end if;
				end if;
				if (h_cnt = pcpm_h_sync_on) then
					scan_cnt1 <= (others => '0');
				else
					scan_cnt1 <= scan_cnt1 + 1;
				end if;
				if (v_cnt = pcpm_v_sync_on) then
					v_sync <= '0';
				elsif (v_cnt = pcpm_v_sync_off) then
					v_sync <= '1';
				end if;

				if (h_cnt = pcpm_h_sync_on) then
					h_sync <= '0';
				elsif (h_cnt = pcpm_h_sync_off) then
					h_sync <= '1';
				end if;

				
				if (h_cnt > pcpm_h_int_on  and v_cnt = pcpm_v_int_on) or (h_cnt < pcpm_h_int_off and v_cnt = pcpm_v_int_off) then
					int_sig <= '0'; else	int_sig <= '1';
				end if;				

--				if (h_cnt = pcpm_h_int_on and v_cnt = pcpm_v_int_on) then
--					flash <= flash + 1;
--					int_sig <= '0';
--				elsif (INTA = '0') then
--					int_sig <= '1';
--				end if;
			
				case (h_cnt(2 downto 0)) is
					when "101" => 
						A <= std_logic_vector((not h_cnt(3)) & v_cnt(7 downto 6)) & std_logic_vector(v_cnt(2 downto 0)) & std_logic_vector(v_cnt(5 downto 3)) & std_logic_vector(h_cnt(8 downto 4));
					when "110" => 	
						vid_reg <= DIPIX;
--					when "110" => 							
						at_reg <= DIATR;						
					when "111" =>
						pixel_reg <= vid_reg;
						attr_reg <= at_reg;
						paper1 <= paper;					
--					when "1001" =>
--						A <= std_logic_vector((not h_cnt(3)) & v_cnt(7 downto 6)) & std_logic_vector(v_cnt(2 downto 0)) & std_logic_vector(v_cnt(5 downto 3)) & std_logic_vector(h_cnt(8 downto 4));
--					when "1010" =>	
--						vid_reg <= DIPIX;
--					when "1100" =>							
--						at_reg <= DIATR;							
--					when "1111" =>
--						pixel_reg <= vid_reg;
--						attr_reg <= at_reg;
--						paper1 <= paper;
					when others => null;
				end case;
			end if;
		end if;
	end if;
end process;



scan_in <= 	(others => '0') when (blank_sig = '1') else
--scan_in <= 	("010010") when (blank_sig = '1') else
			"111111" when (((h_cnt = pspec_h_blk_on or h_cnt = pspec_h_blk_off or v_cnt = pspec_v_blk_on or v_cnt = pspec_v_blk_off) and MODE = "10") or ((h_cnt = pent_h_blank_on or h_cnt = pent_h_blank_off or v_cnt = pent_v_blank_on or v_cnt = pent_v_blank_off) and MODE = "11")) and DS80 = '0' else	-- видео рамка
			attr_reg(4) & (attr_reg(4) and attr_reg(6)) & attr_reg(5) & (attr_reg(5) and attr_reg(6)) & attr_reg(3) & (attr_reg(3) and attr_reg(6)) when paper1 = '1' and (pixel_reg(7 - to_integer(h_cnt(2 downto 0))) xor (flash(4) and attr_reg(7))) = '0' and DS80 = '0' else
			attr_reg(1) & (attr_reg(1) and attr_reg(6)) & attr_reg(2) & (attr_reg(2) and attr_reg(6)) & attr_reg(0) & (attr_reg(0) and attr_reg(6)) when paper1 = '1' and (pixel_reg(7 - to_integer(h_cnt(2 downto 0))) xor (flash(4) and attr_reg(7))) = '1' and DS80 = '0' else
			BORDER(1) & '0' & BORDER(2) & '0' & BORDER(0) & '0' when DS80 = '0' else
--			"111111" when (h_cnt = pcpm_h_blk_on or h_cnt = pcpm_h_blk_off or v_cnt = pcpm_v_blk_on or v_cnt = pcpm_v_blk_off) and DS80 = '1' else	-- видео рамка
			attr_reg(4) & (attr_reg(4) and attr_reg(6)) & attr_reg(5) & (attr_reg(5) and attr_reg(6)) & attr_reg(3) & (attr_reg(3) and attr_reg(6)) when 
			paper1 = '1' and (pixel_reg(7 - to_integer(h_cnt(2 downto 0)))) = '0' and DS80 = '1' else
			attr_reg(1) & (attr_reg(1) and attr_reg(6)) & attr_reg(2) & (attr_reg(2) and attr_reg(6)) & attr_reg(0) & (attr_reg(0) and attr_reg(6)) when 
			paper1 = '1' and (pixel_reg(7 - to_integer(h_cnt(2 downto 0)))) = '1' and DS80 = '1' else 			
			BORDER(1) & '0' & BORDER(2) & '0' & BORDER(0) & '0' when DS80 = '1';			
--			"001010" when DS80 = '1';		
			
			
			


			
blank_sig	<= '1' when (((h_cnt > pspec_h_blk_on and h_cnt < pspec_h_blk_off) or (v_cnt > pspec_v_blk_on and v_cnt < pspec_v_blk_off)) and MODE(0) = '0' and DS80 = '0') or 
                        (((h_cnt > pent_h_blank_on and h_cnt < pent_h_blank_off) or (v_cnt > pent_v_blank_on and v_cnt < pent_v_blank_off)) and MODE(0) = '1' and DS80 = '0') or 
								(((h_cnt > pcpm_h_blk_on and h_cnt < pcpm_h_blk_off) or (v_cnt > pcpm_v_blk_on and v_cnt < pcpm_v_blk_off)) and DS80 = '1') else '0';
paper			<= '1' when ((h_cnt < pspec_scr_h and v_cnt < pspec_scr_v) and MODE(0) = '0' and DS80 = '0') or 
                        ((h_cnt < pent_screen_h and v_cnt < pent_screen_v) and MODE(0) = '1' and DS80 = '0') or 
                        ((h_cnt < pcpm_scr_h and v_cnt < pcpm_scr_v) and DS80 = '1') else '0';
INT			<= int_sig;
RGB 			<= scan_in; --scan_out;
HSYNC 		<= h_sync;
VSYNC 		<= v_sync;
BORDON		<= paper;	-- для порта атрибутов #FF
ATTR			<= attr_reg;
BLANK			<= blank_sig;

end architecture;