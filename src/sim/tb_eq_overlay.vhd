-------------------------------------------------------------------------------
-- overlay (with icons) against the version before (sim/ref/overlay_ref.vhd, icons_ref.vhd), where addr_read,
-- attr2, rom_addr, bitmap2 and icon_pos were latches with decoded enables.
--
-- clk_bus at 28 MHz, CLK (clk_rgb) gated from it as the BUFGCE of clock.vhd does: 7 MHz in the Spectrum modes,
-- 12 MHz (every other clock) in the Profi modes. The MCU side loads the font with random bytes and writes random
-- characters and attributes, then turns the OSD and the popup on and off; random RGB_I, FRAME_SYNC every frame,
-- random activity of STATUS_SD / CF / FD (the icons). RGB_O compared before every rising edge of CLK (what the
-- HDMI / VGA path takes), from the first frame where the old one is not undefined.
-- Prints "tb_eq_overlay: <n> errors".
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity tb_eq_overlay is
generic (
	FRAMES		: integer := 12
);
end tb_eq_overlay;

architecture sim of tb_eq_overlay is

constant T : time := 35556 ps;

signal clk_bus : std_logic := '0';
signal ena_rgb : std_logic := '0';
signal clk_rgb : std_logic;
signal cnt : unsigned(1 downto 0) := "00";
signal vmode : std_logic_vector(3 downto 0) := "0000";
signal rgb_i : std_logic_vector(8 downto 0) := (others => '0');
signal pixel_en, frame_sync : std_logic := '0';
signal st_sd, st_cf, st_fd : std_logic := '0';
signal osd_command : std_logic_vector(15 downto 0) := (others => '0');
signal rgb_ref, rgb_new : std_logic_vector(8 downto 0);
signal frame : integer := 0;

begin

clk_bus <= not clk_bus after T / 2;

-- BUFGCE: the enable taken while clk_bus is low (ena_rgb of clock.vhd: every 4th clock, every 2nd in DS80)
process (clk_bus)
begin
	if falling_edge(clk_bus) then
		cnt <= cnt + 1;
		if vmode(3) = '1' then ena_rgb <= cnt(0); else ena_rgb <= cnt(0) and cnt(1); end if;
	end if;
end process;
clk_rgb <= clk_bus and ena_rgb;

U_REF: entity work.overlay_ref
port map (
	CLK_BUS => clk_bus, CLK => clk_rgb, VMODE => vmode, RGB_I => rgb_i, RGB_O => rgb_ref, PIXEL_EN => pixel_en,
	FRAME_SYNC => frame_sync, STATUS_SD => st_sd, STATUS_CF => st_cf, STATUS_FD => st_fd, OSD_COMMAND => osd_command
);

U_NEW: entity work.overlay
port map (
	CLK_BUS => clk_bus, CLK => clk_rgb, VMODE => vmode, RGB_I => rgb_i, RGB_O => rgb_new, PIXEL_EN => pixel_en,
	FRAME_SYNC => frame_sync, STATUS_SD => st_sd, STATUS_CF => st_cf, STATUS_FD => st_fd, OSD_COMMAND => osd_command
);

-- the video side: frames of the size the overlay expects for the mode (h_end x v_end of overlay.vhd)
process (clk_rgb)
	variable h, v : integer := 0;
	variable r : unsigned(31 downto 0) := x"6B8B4567";
	variable h_end, v_end : integer;
begin
	if rising_edge(clk_rgb) then
		for k in 0 to 15 loop
			r := r(30 downto 0) & (r(31) xor r(21) xor r(1) xor r(0));
		end loop;
		if vmode(3) = '1' then h_end := 768; v_end := 312; else h_end := 448; v_end := 320; end if;
		rgb_i <= std_logic_vector(r(8 downto 0));
		pixel_en <= r(9);
		frame_sync <= '0';
		h := h + 1;
		if h = h_end then
			h := 0;
			v := v + 1;
			if v = v_end then
				v := 0;
				frame_sync <= '1';
				frame <= frame + 1;
			end if;
		end if;
		-- the icons stay on for 2^21 clocks after an access: short accesses now and then
		st_sd <= '0'; st_cf <= '0'; st_fd <= '0';
		if r(20 downto 10) = "00000000000" then st_sd <= '1'; end if;
		if r(20 downto 10) = "00000000001" then st_cf <= '1'; end if;
		if r(20 downto 10) = "00000000010" then st_fd <= '1'; end if;
	end if;
end process;

-- the MCU side: font, characters, OSD on / off, popup on / off, the video mode per frame
process
	variable r : unsigned(31 downto 0) := x"327B23C6";
	procedure rnd is
	begin
		for k in 0 to 31 loop
			r := r(30 downto 0) & (r(31) xor r(21) xor r(1) xor r(0));
		end loop;
	end procedure;
	procedure cmd(c : std_logic_vector(15 downto 0)) is
	begin
		-- the overlay takes a command when it differs from the last one: a different word in between
		osd_command <= x"FF00";
		for k in 1 to 2 loop wait until rising_edge(clk_bus); end loop;
		osd_command <= c;
		for k in 1 to 2 loop wait until rising_edge(clk_bus); end loop;
	end procedure;
	variable last_frame : integer := -1;
begin
	wait until rising_edge(clk_bus);
	cmd(x"2001");                                           -- font address reset
	for i in 0 to 2047 loop
		rnd;
		cmd(x"21" & std_logic_vector(r(7 downto 0)));       -- font byte
	end loop;
	for i in 0 to 32 * 26 - 1 loop
		rnd;
		cmd(x"10" & "000" & std_logic_vector(to_unsigned(i mod 32, 5)));
		cmd(x"11" & "000" & std_logic_vector(to_unsigned(i / 32, 5)));
		cmd(x"12" & std_logic_vector(r(7 downto 0)));
		cmd(x"13" & std_logic_vector(r(15 downto 8)));
	end loop;
	cmd(x"0101");                                           -- OSD on
	while frame < FRAMES loop
		wait until rising_edge(clk_bus);
		if frame /= last_frame then
			last_frame := frame;
			rnd;
			-- per frame: the popup on or off, the video mode (Profi 50 / 60, Pentagon, 128, +3, 48)
			if r(0) = '1' then cmd(x"0201"); else cmd(x"0200"); end if;
			case to_integer(r(3 downto 1)) is
				when 0 | 1 => vmode <= "1000";
				when 2 => vmode <= "1001";
				when 3 => vmode <= "0000";
				when 4 => vmode <= "0010";
				when 5 => vmode <= "0100";
				when others => vmode <= "0110";
			end case;
			-- a few characters change while the frame is shown
			for i in 0 to 7 loop
				rnd;
				cmd(x"10" & "000" & std_logic_vector(r(4 downto 0)));
				cmd(x"11" & "000" & std_logic_vector(unsigned(r(9 downto 5)) mod 26));
				cmd(x"12" & std_logic_vector(r(17 downto 10)));
				cmd(x"13" & std_logic_vector(r(25 downto 18)));
			end loop;
		end if;
	end loop;
	wait;
end process;

process (clk_rgb)
	variable errors, compared : integer := 0;
	variable osd_px : integer := 0;
	variable started : boolean := false;
begin
	if rising_edge(clk_rgb) then
		if not started and frame >= 1 and not is_x(rgb_ref) then
			started := true;
		end if;
		if started then
			compared := compared + 1;
			if rgb_new /= rgb_ref then
				errors := errors + 1;
				if errors <= 10 then
					report "tb_eq_overlay: RGB_O differs at " & time'image(now) & " frame " & integer'image(frame)
						severity error;
				end if;
			end if;
			-- a pixel of the OSD text or an icon: neither the input nor the input darkened under the OSD
			if rgb_ref /= rgb_i and rgb_ref /= ("00" & rgb_i(8) & "00" & rgb_i(5) & "00" & rgb_i(2)) then
				osd_px := osd_px + 1;
			end if;
		end if;
		if frame = FRAMES then
			report "tb_eq_overlay: pixels compared " & integer'image(compared) & ", of them OSD text / icons " &
				integer'image(osd_px);
			report "tb_eq_overlay: " & integer'image(errors) & " errors";
			assert false report "tb_eq_overlay: finished" severity failure;
		end if;
	end if;
end process;

end sim;
