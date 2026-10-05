library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;
library unisim;
use unisim.vcomponents.all;

entity overlay is
	port (
		CLK_BUS	: in std_logic;
		CLK		: in std_logic;
		VMODE 	: in std_logic_vector(3 downto 0);
		RGB_I 	: in std_logic_vector(8 downto 0);
		RGB_O 	: out std_logic_vector(8 downto 0);

		PIXEL_EN	: in std_logic;
		FRAME_SYNC : in std_logic;
		
		STATUS_SD : in std_logic := '0'; -- SD card r/w status
		STATUS_CF : in std_logic := '0'; -- CF card r/w status
		STATUS_FD : in std_logic := '0'; -- FDD r/w status
		
		OSD_COMMAND 	: in std_logic_vector(15 downto 0)
	);
end entity;

architecture rtl of overlay is

	 signal ds80 : std_logic;

    signal video_on : std_logic;
	 signal rgb : std_logic_vector(8 downto 0);

    signal rom_addr: std_logic_vector(10 downto 0);
    signal font_word: std_logic_vector(7 downto 0);
	 signal pixel_reg: std_logic;

    signal attr, attr2: std_logic_vector(7 downto 0);
    signal bitmap, bitmap2: std_logic_vector(7 downto 0);
    
    signal addr_read: std_logic_vector(9 downto 0);
    signal addr_write: std_logic_vector(9 downto 0);
    signal vram_di: std_logic_vector(15 downto 0);
    signal vram_do: std_logic_vector(15 downto 0);
    signal vram_wr: std_logic := '0';

    signal flash : std_logic;
    signal is_flash : std_logic;
    signal rgb_fg : std_logic_vector(8 downto 0);
    signal rgb_bg : std_logic_vector(8 downto 0);

    signal selector : std_logic_vector(3 downto 0);
	 signal last_osd_command : std_logic_vector(15 downto 0);
	 signal char_buf : std_logic_vector(7 downto 0);
	 signal paper_load : std_logic := '0';
	 signal paper_active : std_logic := '0';
	 
 	 signal osd_overlay: std_logic := '0'; -- normal popup
	 signal osd_popup: std_logic := '0'; -- double sized popup
	 
	 signal osdfont_addr : std_logic_vector(10 downto 0) := (others => '1');
	 signal osdfont_data : std_logic_vector(7 downto 0);
	 signal osdfont_we : std_logic := '0';
	 signal osdfont_upd, osdfont_prev_upd : std_logic := '0';	 
	 
	 signal load_dbl: std_logic; -- load pix doubler shift register
	 signal shift_dbl: std_logic; -- shift the doubler shift register
	 
	 signal hcnt_i : std_logic_vector(9 downto 0); -- frame counters
	 signal vcnt_i : std_logic_vector(8 downto 0);

	 signal hcnt : std_logic_vector(9 downto 0) := (others => '0'); -- paper counters (osd body)
	 signal vcnt : std_logic_vector(8 downto 0) := (others => '0');
	 signal fcnt : std_logic_vector(5 downto 0) := (others => '0'); -- flash counter

	 signal h_end : natural; -- frame parameters (based on vmode)
	 signal v_end : natural;
	 signal p_start_h : natural;
	 signal p_end_h : natural;
	 signal p_start_v : natural;
	 signal p_end_v : natural;
begin

	ds80 <= vmode(3);

	 -- 8x8 font RAM
	 U_FONT: entity work.dpram2
	 generic map(
		addr_width_g => 11,
		data_width_g => 8
	 )
	 port map(
		clk_a_i	=> clk_bus,
		we_i		=> osdfont_we,
		addr_a_i	=> osdfont_addr,
		data_a_i	=> osdfont_data,
		
		clk_b_i	=> clk,
		addr_b_i => rom_addr,
		data_b_o => font_word
	 );

	 -- OSD icons
	 U_ICONS: entity work.icons
    port map (
		CLK		=> CLK,
		RGB_I 	=> RGB_I,
		RGB_O 	=> rgb,
		DS80		=> DS80,
		HCNT		=> HCNT,
		VCNT		=> VCNT,
		
		STATUS_SD => STATUS_SD,
		STATUS_CF => STATUS_CF,
		STATUS_FD => STATUS_FD
    );

	-- osd vram
	 U_VRAM: entity work.dpram2
	 generic map(
		addr_width_g => 10,
		data_width_g => 16
	 )
	 port map(
		clk_a_i	=> clk_bus,
		we_i		=> vram_wr,
		addr_a_i	=> addr_write,
		data_a_i	=> vram_di,
		
		clk_b_i	=> clk,
		addr_b_i => addr_read,
		data_b_o => vram_do
	 );
	 

	 -- hcnt >=0 - unexpected behavior!
	 paper_load <= '1' when hcnt > 0 and hcnt < 32*8 and vcnt >= 0 and vcnt < 27*8 else '0'; -- load vram / font 8 pixels ahead
	 paper_active <= '1' when hcnt >= 8 and hcnt < 32*8+8 and vcnt >= 0 and vcnt < 27*8 else '0'; -- active paper for osd
	 
    video_on <= '1' when (OSD_OVERLAY = '1' or OSD_POPUP = '1') else '0';
	 
	 -- h/v end - based on vmode
	 process (clk)
	 begin
		if rising_edge(clk) then 
			case (vmode) is
				when "1000" | "1010" | "1100" | "1110" => -- profi 50
					h_end <= 768; v_end <= 312; p_start_h <= 48-8; p_end_h <= 512+48-8; p_start_v <= 32; p_end_v <= 208+32;
				when "1001" | "1011" | "1101" | "1111" => -- profi 60
					h_end <= 768; v_end <= 264; p_start_h <= 48-8; p_end_h <= 512+48-8; p_start_v <= 32; p_end_v <= 208+32;
				when "0000" => -- pentagon 50
					h_end <= 448; v_end <= 320; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0001" => -- pentagon 60
					h_end <= 448; v_end <= 264; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0010" => -- 128 50
					h_end <= 448; v_end <= 312; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0011" => -- 128 60
					h_end <= 448; v_end <= 256; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0100" => -- +3 50
					h_end <= 448; v_end <= 312; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0101" => -- +3 60
					h_end <= 448; v_end <= 256; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0110" => -- 48 50
					h_end <= 448; v_end <= 312; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when "0111" => -- 48 60
					h_end <= 448; v_end <= 256; p_start_h <= 64; p_end_h <= 256+64; p_start_v <= 64; p_end_v <= 272;
				when others => null;
			end case;
		end if;
	 end process;
	 
	 -- frame counters
	process (clk) 
	begin
		if rising_edge(clk) then
			if (frame_sync = '1') then 
				hcnt_i <= (others => '0');
				vcnt_i <= (others => '0');
			else
				if hcnt_i = h_end-1 then 
					hcnt_i <= (others => '0'); 
					if vcnt_i = v_end-1 then
						vcnt_i <= (others => '0');
					else
						vcnt_i <= vcnt_i + 1;
					end if;
				else
					hcnt_i <= hcnt_i + 1;
				end if;
			end if;
		end if;
	end process;
	
	-- osd paper counters (bounds to the center of the screen)
	process (clk)
	begin
		if rising_edge(clk) then 

			if hcnt_i = p_start_h then -- paper begin h
				hcnt <= (others => '0');
				if vcnt_i = p_start_v then -- paper begin v
					vcnt <= (others => '0');
					fcnt <= fcnt + 1;
				else
					vcnt <= vcnt + 1;
				end if;
			else
				if (ds80 = '1' and hcnt_i(0) = '1') or ds80 = '0' then
					hcnt <= hcnt + 1;
				end if;
			end if;
		end if;
	end process;
	 
	 -- mem read character / attribute
	 process (clk, osd_popup, paper_load, hcnt, vcnt)
	 begin
--		if (rising_edge(clk)) then 
			if (OSD_POPUP = '1') then 
				if paper_load = '1' then
					case (HCNT(3 downto 0)) is -- read every 16 pixels
						when "1001" => addr_read <= VCNT(8 downto 4) & HCNT(8 downto 4); -- load char from vram
						when "1010" => attr2 <= vram_do(7 downto 0); -- save attribute to tmp reg
											rom_addr <= vram_do(15 downto 8) & VCNT(3 downto 1); -- load bitmap from font ram
						when "1011" => bitmap2 <= font_word; -- save bitmap to tmp reg
						--when "1111" => attr <= attr2; bitmap <= bitmap2; -- move attribute and bitmap
						when others => null;						
					end case;
				end if;
			else 
				if (paper_load = '1') then
					case (HCNT(2 downto 0)) is -- read every 8 pixels
						when "100" => addr_read <= VCNT(7 downto 3) & HCNT(7 downto 3); -- ??? hcnt(7:3) ???
						when "101" => attr2 <= vram_do(7 downto 0);
										  rom_addr <= vram_do(15 downto 8) & VCNT(2 downto 0);
						when "110" => bitmap2 <= font_word;
						--when "111" => attr <= attr2; bitmap <= bitmap2;
						when others => null;						
					end case;
				end if;
			end if;
--		end if;
	 end process;
	 
	 process (clk) 
	 begin
		if rising_edge(clk) then
			if (OSD_POPUP = '1' and paper_load = '1' and HCNT(3 downto 0) = "1111") or (OSD_POPUP = '0' and paper_load = '1' and HCNT(2 downto 0) = "111") then
					attr <= attr2; bitmap <= bitmap2; -- move attribute and bitmap
			end if;
		end if;
	 end process;
	 
	 -- pix doubler load
	 process (CLK) 
	 begin
		if rising_edge(CLK) then
			load_dbl <= '0';
			shift_dbl <= '0';
			-- load
			if ((OSD_POPUP = '0' and HCNT(2 downto 0) = "111" and paper_load = '1') or 
			    (OSD_POPUP = '1' and HCNT(3 downto 0) = "1111" and paper_load = '1')) 
				 then 
				load_dbl <= '1';
			end if;
			-- do
			if ((OSD_POPUP = '0' and HCNT(2 downto 0) /= "111" and paper_active = '1') or 
			    (OSD_POPUP = '1' and HCNT(3 downto 0) /= "1111" and paper_active = '1')) 
				 then 
				shift_dbl <= '1';
			end if;
		end if;
	 end process;
	 
	 -- pix doubler shifter
	 U_DBL: entity work.pix_doubler
	 port map(
		CLK => CLK,
		LOAD => load_dbl,
		SHIFT => shift_dbl,
		D => bitmap,
		QUAD => DS80 & OSD_POPUP,
		DOUT => pixel_reg
	 );
	 
	 -- output rgb
	 flash <= fcnt(5);
    is_flash <= '1' when attr(3 downto 0) = "0001" else '0';
    selector <= video_on & pixel_reg & flash & is_flash;
    rgb_fg <= (attr(7) and attr(4)) & attr(7) & attr(7) & (attr(6) and attr(4)) & attr(6) & attr(6) & (attr(5) and attr(4)) & attr(5) & attr(5);
    rgb_bg <= (attr(3) and attr(0)) & attr(3) & attr(3) & (attr(2) and attr(0)) & attr(2) & attr(2) & (attr(1) and attr(0)) & attr(1) & attr(1);
    RGB_O <= 
				--"000000111" when (hcnt = 1 or hcnt = 32*8-1 or vcnt = 0 or vcnt = 26*8-1) and paper_load='1' else -- blue = debug load paper (
				--"111000000" when (hcnt = 8 or hcnt = 32*8+8-1) and paper_active='1' else -- red = debug active paper
				
				rgb_fg when rgb_fg /= "000000000" and paper_active = '1' and (selector="1111" or selector="1001" or selector="1100" or selector="1110") else 
            rgb_bg when rgb_bg /= "000000000" and paper_active = '1' and (selector="1011" or selector="1101" or selector="1000" or selector="1010") else 
				"00" & rgb(8) & "00" & rgb(5) & "00" & rgb(2) when video_on = '1' else 
				--"000000000" when video_on = '1' else -- black solid bg
				rgb;

	-- load osd and font from mcu
	process(clk_bus, osd_command, last_osd_command)
	begin
		  if rising_edge(clk_bus) then
				 vram_wr <= '0';
				 if (osd_command /= last_osd_command) then 
					last_osd_command <= osd_command;
					case osd_command(15 downto 8) is 
					  when x"01" => vram_wr <= '0'; osd_overlay <= osd_command(0); -- osd
					  when x"02" => vram_wr <= '0'; osd_popup <= osd_command(0); -- popup						
					  when X"10"  => vram_wr <= '0'; addr_write(4 downto 0) <= osd_command(4 downto 0); -- x: 0...32
					  when X"11" => vram_wr <= '0'; addr_write(9 downto 5) <= osd_command(4 downto 0); -- y: 0...32
					  when X"12"  => vram_wr <= '0'; char_buf <= osd_command(7 downto 0); -- char
					  when X"13"  => vram_wr <= '1'; vram_di <= char_buf & osd_command(7 downto 0); -- attrs
					  when x"20" => 
							-- reset font address
							if (OSD_COMMAND(0) = '1') then 
								osdfont_addr <= (others => '1');
								osdfont_upd <= '0';
								osdfont_prev_upd <= '0';
							end if;
					  when x"21" => 
							-- new font data
							osdfont_addr <= osdfont_addr + 1;
							osdfont_data <= OSD_COMMAND(7 downto 0);
							osdfont_upd <= not osdfont_upd;
					  when others => vram_wr <= '0';
					end case;
				 end if;

				-- wr signal / osd font loader
				osdfont_we <= '0';
				if (osdfont_prev_upd /= osdfont_upd) then
					osdfont_prev_upd <= osdfont_upd;
					osdfont_we <= '1';
				end if;

		  end if;
	end process;

end architecture;
