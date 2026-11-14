-------------------------------------------------------------------------------
-- MCU HID keyboard / joystick parser / transformer
-------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_arith.conv_integer;
use IEEE.numeric_std.all;
use IEEE.std_logic_unsigned.all;

entity hid_parser is
	generic 
	(
		NUM_KEYS : integer range 1 to 6 := 6; -- number of simultaneously pressed keys to process (depracated)
		ALLOW_KEYCODE : boolean := true -- allow ps/2 keycode (tsconf standard)
	);
	port
	(
	 CLK			 : in std_logic;
	 RESET 		 : in std_logic;
	 
	 -- incoming usb hid report data
	 KB_STATUS : in std_logic_vector(7 downto 0);
	 KB_DAT0 : in std_logic_vector(7 downto 0);
	 KB_DAT1 : in std_logic_vector(7 downto 0);
	 KB_DAT2 : in std_logic_vector(7 downto 0);
	 KB_DAT3 : in std_logic_vector(7 downto 0);
	 KB_DAT4 : in std_logic_vector(7 downto 0);
	 KB_DAT5 : in std_logic_vector(7 downto 0);

	 -- joy data from mcu
	 JOY_TYPE_L : in std_logic_vector(2 downto 0);
	 JOY_TYPE_R : in std_logic_vector(2 downto 0);
	 JOY_L : in std_logic_vector(12 downto 0);
	 JOY_R : in std_logic_vector(12 downto 0);

	 -- cpu address for spectrum keyboard row address
	 A : in std_logic_vector(15 downto 8);
	 
	 -- keyboard type
	 KB_TYPE : in std_logic; -- 0=profi xt, 1=spectrum
	 
	 -- kempston joy output data
	 JOY_DO : out std_logic_vector(7 downto 0);

	 -- keyboard output data
	 KB_DO : out std_logic_vector(5 downto 0);
	 
	 -- tsconf ps/2 scancode to RTC reg F0
	 KEYCODE: out std_logic_vector(7 downto 0)
	);
end hid_parser;

architecture rtl of hid_parser is

	-- the keys of the matrix: the bit of the 40 keys + the 5th bit (Profi) in kb_data
	constant ZX_K_CS : natural := 0;
	constant ZX_K_A : natural := 1;
	constant ZX_K_Q : natural := 2;
	constant ZX_K_1 : natural := 3;
	constant ZX_K_0 : natural := 4;
	constant ZX_K_P : natural := 5;
	constant ZX_K_ENT : natural := 6;
	constant ZX_K_SP : natural := 7;
	constant ZX_K_Z : natural := 8;
	constant ZX_K_S : natural := 9;
	constant ZX_K_W : natural := 10;
	constant ZX_K_2 : natural := 11;
	constant ZX_K_9 : natural := 12;
	constant ZX_K_O : natural := 13;
	constant ZX_K_L : natural := 14;
	constant ZX_K_SS : natural := 15;
	constant ZX_K_X : natural := 16;
	constant ZX_K_D : natural := 17;
	constant ZX_K_E : natural := 18;
	constant ZX_K_3 : natural := 19;
	constant ZX_K_8 : natural := 20;
	constant ZX_K_I : natural := 21;
	constant ZX_K_K : natural := 22;
	constant ZX_K_M : natural := 23;
	constant ZX_K_C : natural := 24;
	constant ZX_K_F : natural := 25;
	constant ZX_K_R : natural := 26;
	constant ZX_K_4 : natural := 27;
	constant ZX_K_7 : natural := 28;
	constant ZX_K_U : natural := 29;
	constant ZX_K_J : natural := 30;
	constant ZX_K_N : natural := 31;
	constant ZX_K_V : natural := 32;
	constant ZX_K_G : natural := 33;
	constant ZX_K_T : natural := 34;
	constant ZX_K_5 : natural := 35;
	constant ZX_K_6 : natural := 36;
	constant ZX_K_Y : natural := 37;
	constant ZX_K_H : natural := 38;
	constant ZX_K_B : natural := 39;
	constant ZX_BIT5 : natural := 40;
	constant NO_KEY : natural := 63;

	constant SC_CTL_ON : natural := 0;
	constant SC_BTN_UP : natural := 1;
	constant SC_BTN_DOWN: natural := 2;
	constant SC_BTN_LEFT: natural := 3;
	constant SC_BTN_RIGHT: natural := 4;
	constant SC_BTN_START: natural := 5;
	constant SC_BTN_A : natural := 6;
	constant SC_BTN_B : natural := 7;
	constant SC_BTN_C : natural := 8;
	constant SC_BTN_X : natural := 9;
	constant SC_BTN_Y : natural := 10;
	constant SC_BTN_Z : natural := 11;
	constant SC_BTN_MODE : natural := 12;

	subtype kb_matrix is std_logic_vector(40 downto 0);
	signal kb_data, kb_data_latch : kb_matrix := (others => '0'); -- 40 keys + 5th bit

	-- the key map in a block ROM: the address { KB_TYPE, shift, scancode }, the word
	-- [5:0] key 1 + 1 (0 = none), [11:6] key 2 + 1, [12] CS used, [13] SS used,
	-- [14] macro (SS+CS, SS, then key 1 alone with CS)
	subtype km_word is std_logic_vector(17 downto 0);
	type km_rom is array(0 to 1023) of km_word;

	function km(k1, k2 : natural; cs, ss, mac : std_logic) return km_word is
		variable w : km_word := (others => '0');
	begin
		if k1 /= NO_KEY then w(5 downto 0) := std_logic_vector(to_unsigned(k1 + 1, 6)); end if;
		if k2 /= NO_KEY then w(11 downto 6) := std_logic_vector(to_unsigned(k2 + 1, 6)); end if;
		w(12) := cs; w(13) := ss; w(14) := mac;
		return w;
	end function;

	function k1(ka : natural) return km_word is begin return km(ka, NO_KEY, '0', '0', '0'); end function;
	function k2(ka, kb : natural) return km_word is begin return km(ka, kb, '0', '0', '0'); end function;
	function k2cs(ka, kb : natural) return km_word is begin return km(ka, kb, '1', '0', '0'); end function;
	function sel(c : boolean; ka, kb : natural) return natural is begin if c then return ka; else return kb; end if; end function;

	-- one scancode: the same cases as the old case statement (kt 0 = Profi XT, 1 = Spectrum)
	function km_entry(kt, shi, sc : natural) return km_word is
		constant profi : boolean := kt = 0;
		constant sh : boolean := shi = 1;
		variable shl : std_logic;
		constant none : km_word := (others => '0');
		type nat_arr is array(natural range <>) of natural;
		constant LK : nat_arr(0 to 25) := (ZX_K_A, ZX_K_B, ZX_K_C, ZX_K_D, ZX_K_E, ZX_K_F, ZX_K_G,
			ZX_K_H, ZX_K_I, ZX_K_J, ZX_K_K, ZX_K_L, ZX_K_M, ZX_K_N, ZX_K_O, ZX_K_P, ZX_K_Q, ZX_K_R,
			ZX_K_S, ZX_K_T, ZX_K_U, ZX_K_V, ZX_K_W, ZX_K_X, ZX_K_Y, ZX_K_Z);
		constant DK : nat_arr(0 to 9) := (ZX_K_1, ZX_K_2, ZX_K_3, ZX_K_4, ZX_K_5, ZX_K_6, ZX_K_7,
			ZX_K_8, ZX_K_9, ZX_K_0);
		constant FK : nat_arr(0 to 9) := (ZX_K_A, ZX_K_B, ZX_K_C, ZX_K_D, ZX_K_E, ZX_K_F, ZX_K_G,
			ZX_K_H, ZX_K_I, ZX_K_J);
	begin
		if sh then shl := '1'; else shl := '0'; end if;
		-- letters, digits, numpad digits
		if sc >= 16#04# and sc <= 16#1d# then return k1(LK(sc - 16#04#)); end if;
		if sc >= 16#1e# and sc <= 16#27# then return k1(DK(sc - 16#1e#)); end if;
		if sc >= 16#59# and sc <= 16#62# then return k1(DK(sc - 16#59#)); end if;
		-- F1..F10 (Profi)
		if sc >= 16#3a# and sc <= 16#43# then
			if profi then return k2(FK(sc - 16#3a#), ZX_BIT5); else return none; end if;
		end if;
		case sc is
			-- DEL -> SS + C (P + BIT5 for profi)
			when 16#4c# => if sh then return none; elsif profi then return k2(ZX_K_P, ZX_BIT5); else return k2(ZX_K_SS, ZX_K_C); end if;
			-- INS -> SS + A (O + BIT5 for profi)
			when 16#49# => if sh then return none; elsif profi then return k2(ZX_K_O, ZX_BIT5); else return k2(ZX_K_SS, ZX_K_A); end if;
			-- Cursor -> CS + 5,6,7,8
			when 16#50# => if sh then return none; else return k2cs(ZX_K_CS, ZX_K_5); end if;
			when 16#51# => if sh then return none; else return k2cs(ZX_K_CS, ZX_K_6); end if;
			when 16#52# => if sh then return none; else return k2cs(ZX_K_CS, ZX_K_7); end if;
			when 16#4f# => if sh then return none; else return k2cs(ZX_K_CS, ZX_K_8); end if;
			-- ESC -> CS + Space (CS + 1 for profi)
			when 16#29# => return k2cs(ZX_K_CS, sel(profi, ZX_K_1, ZX_K_SP));
			-- Backspace -> CS + 0
			when 16#2a# => return k2cs(ZX_K_CS, ZX_K_0);
			-- Enter, keypad Enter, Space
			when 16#28# | 16#58# => return k1(ZX_K_ENT);
			when 16#2c# => return k1(ZX_K_SP);
			-- '/" -> SS+P / SS+7 and the like: SS used when shifted
			when 16#34# => return km(ZX_K_SS, sel(sh, ZX_K_P, ZX_K_7), '0', shl, '0');
			when 16#36# => return km(ZX_K_SS, sel(sh, ZX_K_R, ZX_K_N), '0', shl, '0');
			when 16#37# => return km(ZX_K_SS, sel(sh, ZX_K_T, ZX_K_M), '0', shl, '0');
			when 16#33# => return km(ZX_K_SS, sel(sh, ZX_K_Z, ZX_K_O), '0', shl, '0');
			when 16#38# => return km(ZX_K_SS, sel(sh, ZX_K_C, ZX_K_V), '0', shl, '0');
			when 16#2E# => return km(ZX_K_SS, sel(sh, ZX_K_K, ZX_K_L), '0', shl, '0');
			when 16#2D# => return km(ZX_K_SS, sel(sh, ZX_K_0, ZX_K_J), '0', shl, '0');
			-- [,{ ],} \,| : SS + key for profi, a macro for Spectrum
			when 16#2F# => if profi then return k2(ZX_K_SS, sel(sh, ZX_K_F, ZX_K_Y)); else return km(sel(sh, ZX_K_F, ZX_K_Y), NO_KEY, '0', '0', '1'); end if;
			when 16#30# => if profi then return k2(ZX_K_SS, sel(sh, ZX_K_G, ZX_K_U)); else return km(sel(sh, ZX_K_G, ZX_K_U), NO_KEY, '0', '0', '1'); end if;
			when 16#31# => if profi then return k2(ZX_K_SS, sel(sh, ZX_K_S, ZX_K_D)); else return km(sel(sh, ZX_K_S, ZX_K_D), NO_KEY, '0', '0', '1'); end if;
			-- `,~ -> SS+X / macro SS+A
			when 16#35# => if sh then return km(ZX_K_A, NO_KEY, '0', '1', '1'); else return km(ZX_K_SS, ZX_K_X, '0', '1', '0'); end if;
			-- Keypad * - +
			when 16#55# => return k2(ZX_K_SS, ZX_K_B);
			when 16#56# => return k2(ZX_K_SS, ZX_K_J);
			when 16#57# => return k2(ZX_K_SS, ZX_K_K);
			-- Tab -> CS + I, CapsLock -> CS + SS
			when 16#2B# => return k2cs(ZX_K_CS, ZX_K_I);
			when 16#39# => return k2cs(ZX_K_SS, ZX_K_CS);
			-- PgUp / PgDown -> CS+3 / CS+4 for ZX (M / N + BIT5 for profi)
			when 16#4B# => if sh then return none; elsif profi then return k2(ZX_K_M, ZX_BIT5); else return k2cs(ZX_K_CS, ZX_K_3); end if;
			when 16#4E# => if sh then return none; elsif profi then return k2(ZX_K_N, ZX_BIT5); else return k2cs(ZX_K_CS, ZX_K_4); end if;
			-- Home / End -> K / L + BIT5 for profi
			when 16#4a# => if profi and not sh then return k2(ZX_K_K, ZX_BIT5); else return none; end if;
			when 16#4d# => if profi and not sh then return k2(ZX_K_L, ZX_BIT5); else return none; end if;
			-- F11 / F12 (Profi)
			when 16#44# => if profi then return k2(ZX_K_Q, ZX_K_SS); else return none; end if;
			when 16#45# => if profi then return k2(ZX_K_W, ZX_K_SS); else return none; end if;
			when others => return none;
		end case;
	end function;

	function km_init return km_rom is
		variable r : km_rom;
	begin
		for kt in 0 to 1 loop
			for sh in 0 to 1 loop
				for sc in 0 to 255 loop
					r(kt * 512 + sh * 256 + sc) := km_entry(kt, sh, sc);
				end loop;
			end loop;
		end loop;
		return r;
	end function;

	signal km_mem : km_rom := km_init;
	attribute rom_style : string;
	attribute rom_style of km_mem : signal is "block";

	signal km_q : km_word := (others => '0');
	signal km_addr : std_logic_vector(9 downto 0);
	signal shift_now, shift_r : std_logic := '0';
	signal st_d : std_logic_vector(7 downto 0) := (others => '0');
	signal kt_d : std_logic := '0';

	signal is_macros : std_logic := '0';
	type macros_machine is (MACRO_START, MACRO_CS_ON, MACRO_SS_ON, MACRO_SS_OFF, MACRO_KEY, MACRO_CS_OFF, MACRO_END);
	signal macros_key : natural range 0 to 63 := 0;
	signal macros_state : macros_machine := MACRO_START;
	signal macro_cnt : std_logic_vector(21 downto 0) := (others => '0');

	-- usb_idx picks the scancode read from the ROM, usb_ph (a clock later) is the step that
	-- applies it: the old one-clock steps, a clock later
	signal usb_idx, usb_ph, rd_idx : std_logic_vector(2 downto 0) := "000";
	signal cur_sc : std_logic_vector(7 downto 0);

begin 

	-- usb hid to ps/2 keycode
	G_PS2_LUT: if ALLOW_KEYCODE generate
	U_PS2_LUT: entity work.usb_ps2_lut
	port map(
		kb_status => KB_STATUS,
		kb_data => KB_DAT0,
		keycode => KEYCODE
	);
	end generate G_PS2_LUT;

	process( kb_data_latch, A)
	begin
		KB_DO(0) <=	not(( kb_data_latch(ZX_K_CS)  and not( A(8)  ) ) 
					or    ( kb_data_latch(ZX_K_A)  and not(   A(9)  ) ) 
					or    ( kb_data_latch(ZX_K_Q) and not(    A(10) ) ) 
					or    ( kb_data_latch(ZX_K_1) and not(    A(11) ) ) 
					or    ( kb_data_latch(ZX_K_0) and not(    A(12) ) ) 
					or    ( kb_data_latch(ZX_K_P) and not(    A(13) ) ) 
					or    ( kb_data_latch(ZX_K_ENT) and not(  A(14) ) ) 
					or    ( kb_data_latch(ZX_K_SP) and not(   A(15) ) )  );

		KB_DO(1) <=	not( ( kb_data_latch(ZX_K_Z)  and not(A(8) ) ) 
					or   ( kb_data_latch(ZX_K_S)  and not(A(9) ) ) 
					or   ( kb_data_latch(ZX_K_W) and not(A(10)) ) 
					or   ( kb_data_latch(ZX_K_2) and not(A(11)) ) 
					or   ( kb_data_latch(ZX_K_9) and not(A(12)) ) 
					or   ( kb_data_latch(ZX_K_O) and not(A(13)) ) 
					or   ( kb_data_latch(ZX_K_L) and not(A(14)) ) 
					or   ( kb_data_latch(ZX_K_SS) and not(A(15)) ) );

		KB_DO(2) <=		not( ( kb_data_latch(ZX_K_X) and not( A(8)) ) 
					or   ( kb_data_latch(ZX_K_D) and not( A(9)) ) 
					or   ( kb_data_latch(ZX_K_E) and not(A(10)) ) 
					or   ( kb_data_latch(ZX_K_3) and not(A(11)) ) 
					or   ( kb_data_latch(ZX_K_8) and not(A(12)) ) 
					or   ( kb_data_latch(ZX_K_I) and not(A(13)) ) 
					or   ( kb_data_latch(ZX_K_K) and not(A(14)) ) 
					or   ( kb_data_latch(ZX_K_M) and not(A(15)) ) );

		KB_DO(3) <=		not( ( kb_data_latch(ZX_K_C) and not( A(8)) ) 
					or   ( kb_data_latch(ZX_K_F) and not( A(9)) ) 
					or   ( kb_data_latch(ZX_K_R) and not(A(10)) ) 
					or   ( kb_data_latch(ZX_K_4) and not(A(11)) ) 
					or   ( kb_data_latch(ZX_K_7) and not(A(12)) ) 
					or   ( kb_data_latch(ZX_K_U) and not(A(13)) ) 
					or   ( kb_data_latch(ZX_K_J) and not(A(14)) ) 
					or   ( kb_data_latch(ZX_K_N) and not(A(15)) ) );

		KB_DO(4) <=		not( ( kb_data_latch(ZX_K_V) and not( A(8)) ) 
					or   ( kb_data_latch(ZX_K_G) and not( A(9)) ) 
					or   ( kb_data_latch(ZX_K_T) and not(A(10)) ) 
					or   ( kb_data_latch(ZX_K_5) and not(A(11)) ) 
					or   ( kb_data_latch(ZX_K_6) and not(A(12)) ) 
					or   ( kb_data_latch(ZX_K_Y) and not(A(13)) ) 
					or   ( kb_data_latch(ZX_K_H) and not(A(14)) ) 
					or   ( kb_data_latch(ZX_K_B) and not(A(15)) ) );
					
		KB_DO(5) <= not(kb_data_latch(ZX_BIT5));
	end process;

	-- the scancode of the step and the shift of the round (taken at its first scancode); during a
	-- macro the step that follows it (usb_idx has gone a step further)
	rd_idx <= usb_ph when is_macros = '1' else usb_idx;
	with rd_idx select cur_sc <=
		KB_DAT0 when "000",
		KB_DAT1 when "001",
		KB_DAT2 when "010",
		KB_DAT3 when "011",
		KB_DAT4 when "100",
		KB_DAT5 when others;
	shift_now <= (KB_STATUS(1) or KB_STATUS(5)) when rd_idx = "000" else shift_r;
	km_addr <= KB_TYPE & shift_now & cur_sc;

	-- the ROM read (also during a macro: the step after it gets the scancode of that moment), and
	-- the modifiers of the read step for the apply step
	process (CLK)
	begin
		if rising_edge(CLK) then
			km_q <= km_mem(to_integer(unsigned(km_addr)));
			if rd_idx = "000" then
				shift_r <= shift_now;
			end if;
			st_d <= KB_STATUS;
			kt_d <= KB_TYPE;
		end if;
	end process;

process (RESET, CLK)

	variable is_cs_used : std_logic := '0';
	variable is_ss_used : std_logic := '0';
	variable k1i, k2i : natural range 0 to 63;

	begin
		if RESET = '1' then
			kb_data <= (others => '0');
			kb_data_latch <= (others => '0');
			usb_idx <= (others => '0');
			usb_ph <= (others => '0');
			is_cs_used := '0';
			is_ss_used := '0';
			is_macros <= '0';
			macro_cnt <= (others => '0');
			macros_state <= MACRO_START;
			
		elsif CLK'event and CLK = '1' then
				
			-- macro state machine
			if is_macros = '1' then 
					macro_cnt <= macro_cnt + 1;
					if (macro_cnt = "1111111111111111111111") then 
					case macros_state is 
						when MACRO_START  =>kb_data_latch <= (others => '0'); macros_state <= MACRO_CS_ON;
						when MACRO_CS_ON  => kb_data_latch(ZX_K_CS) <= '1';    macros_state <= MACRO_SS_ON;
						when MACRO_SS_ON  => kb_data_latch(ZX_K_SS) <= '1';    macros_state <= MACRO_SS_OFF;
						when MACRO_SS_OFF => kb_data_latch(ZX_K_SS) <= '0';    macros_state <= MACRO_KEY;
						when MACRO_KEY    => kb_data_latch(macros_key) <= '1'; macros_state <= MACRO_CS_OFF;
						when MACRO_CS_OFF => kb_data_latch(ZX_K_CS) <= '0'; kb_data_latch(macros_key) <= '0'; macros_state <= MACRO_END;
						when MACRO_END    => kb_data_latch <= (others => '0'); is_macros <= '0';        macros_state <= MACRO_START;
						when others => null;
					end case;
					end if;
			else
				-- the read step
				if (usb_idx >= "101") then 
					usb_idx <= "000";
				else
					usb_idx <= usb_idx + 1;
				end if;
				usb_ph <= usb_idx;

				-- the apply step
				if (usb_ph = "000") then
					macro_cnt <= (others => '0');
					kb_data_latch <= kb_data; -- latch processed kb_data
					kb_data <= (others => '0');
					is_cs_used := '0';
					is_ss_used := '0';
				end if;
				
				if (usb_ph = "000") then
					-- L Shift -> CS (SS for profi)
					if st_d(1) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_SS) <= '1'; else kb_data(ZX_K_CS) <= '1'; end if; 
					end if;

					-- R Shift -> CS (SS for profi)
					if st_d(5) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_SS) <= '1'; else kb_data(ZX_K_CS) <= '1'; end if; 
					end if;
								
					-- L Ctrl -> SS (CS for profi)
					if st_d(0) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_CS) <= '1'; else kb_data(ZX_K_SS) <= '1'; end if; 
					end if;
					
					-- R Ctrl -> SS (CS for profi)
					if st_d(4) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_CS) <= '1'; else kb_data(ZX_K_SS) <= '1'; end if; 
					end if;
								
					-- L Alt -> SS+CS (SS+Enter for profi)
					if st_d(2) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_ENT) <= '1'; else kb_data(ZX_K_CS) <= '1'; end if; 
						kb_data(ZX_K_SS) <= '1'; 
						is_cs_used := '1'; 
					end if;

					-- R Alt -> SS+CS (SS+Space for profi)
					if st_d(6) = '1' then 
						if kt_d = '0' then kb_data(ZX_K_SP) <= '1'; else kb_data(ZX_K_CS) <= '1'; end if; 
						kb_data(ZX_K_SS) <= '1'; 
						is_cs_used := '1'; 
					end if;
				end if;

				-- the scancode of this step, from the ROM
				k1i := to_integer(unsigned(km_q(5 downto 0)));
				k2i := to_integer(unsigned(km_q(11 downto 6)));
				if km_q(14) = '1' then
					is_macros <= '1';
					macros_key <= k1i - 1;
				else
					for i in 0 to 40 loop
						if k1i = i + 1 or k2i = i + 1 then kb_data(i) <= '1'; end if;
					end loop;
				end if;
				if km_q(12) = '1' then is_cs_used := '1'; end if;
				if km_q(13) = '1' then is_ss_used := '1'; end if;
							
				-- map joysticks to keyboard
				-- sega joy:  Mode Z Y X C B A Start R L D U On
				if (usb_ph = "101") then
					-- sinclair 1
					if joy_type_l = "001" then 
						if (joy_l(SC_BTN_UP) = '1') then kb_data(ZX_K_4) <= '1'; end if; -- up
						if (joy_l(SC_BTN_DOWN) = '1') then kb_data(ZX_K_3) <= '1'; end if; -- down
						if (joy_l(SC_BTN_LEFT) = '1') then kb_data(ZX_K_1) <= '1'; end if; -- left
						if (joy_l(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_2) <= '1'; end if; -- right
						if (joy_l(SC_BTN_B) = '1') then kb_data(ZX_K_5) <= '1'; end if; -- fire
					end if;
					if joy_type_r = "001" then
						if (joy_r(SC_BTN_UP) = '1') then kb_data(ZX_K_4) <= '1'; end if; -- up
						if (joy_r(SC_BTN_DOWN) = '1') then kb_data(ZX_K_3) <= '1'; end if; -- down
						if (joy_r(SC_BTN_LEFT) = '1') then kb_data(ZX_K_1) <= '1'; end if; -- left
						if (joy_r(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_2) <= '1'; end if; -- right
						if (joy_r(SC_BTN_B) = '1') then kb_data(ZX_K_5) <= '1'; end if; -- fire					
					end if;
					
					-- sinclair 2
					if joy_type_l = "010" then 
						if (joy_l(SC_BTN_UP) = '1') then kb_data(ZX_K_9) <= '1'; end if; -- up
						if (joy_l(SC_BTN_DOWN) = '1') then kb_data(ZX_K_8) <= '1'; end if; -- down
						if (joy_l(SC_BTN_LEFT) = '1') then kb_data(ZX_K_6) <= '1'; end if; -- left
						if (joy_l(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_7) <= '1'; end if; -- right
						if (joy_l(SC_BTN_B) = '1') then kb_data(ZX_K_0) <= '1'; end if; -- fire	
					end if;
					if joy_type_r = "010" then
						if (joy_r(SC_BTN_UP) = '1') then kb_data(ZX_K_9) <= '1'; end if; -- up
						if (joy_r(SC_BTN_DOWN) = '1') then kb_data(ZX_K_8) <= '1'; end if; -- down
						if (joy_r(SC_BTN_LEFT) = '1') then kb_data(ZX_K_6) <= '1'; end if; -- left
						if (joy_r(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_7) <= '1'; end if; -- right
						if (joy_r(SC_BTN_B) = '1') then kb_data(ZX_K_0) <= '1'; end if; -- fire					
					end if;
					
					-- cursor
					if joy_type_l = "011" then 
						if (joy_l(SC_BTN_UP) = '1') then kb_data(ZX_K_7) <= '1'; end if; -- up
						if (joy_l(SC_BTN_DOWN) = '1') then kb_data(ZX_K_6) <= '1'; end if; -- down
						if (joy_l(SC_BTN_LEFT) = '1') then kb_data(ZX_K_5) <= '1'; end if; -- left
						if (joy_l(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_8) <= '1'; end if; -- right
						if (joy_l(SC_BTN_B) = '1') then kb_data(ZX_K_0) <= '1'; end if; -- fire	
					end if;
					if joy_type_r = "011" then
						if (joy_r(SC_BTN_UP) = '1') then kb_data(ZX_K_7) <= '1'; end if; -- up
						if (joy_r(SC_BTN_DOWN) = '1') then kb_data(ZX_K_6) <= '1'; end if; -- down
						if (joy_r(SC_BTN_LEFT) = '1') then kb_data(ZX_K_5) <= '1'; end if; -- left
						if (joy_r(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_8) <= '1'; end if; -- right
						if (joy_r(SC_BTN_B) = '1') then kb_data(ZX_K_0) <= '1'; end if; -- fire					
					end if;
					
					-- qaopm
					if joy_type_l = "100" then 
						if (joy_l(SC_BTN_UP) = '1') then kb_data(ZX_K_Q) <= '1'; end if; -- up
						if (joy_l(SC_BTN_DOWN) = '1') then kb_data(ZX_K_A) <= '1'; end if; -- down
						if (joy_l(SC_BTN_LEFT) = '1') then kb_data(ZX_K_O) <= '1'; end if; -- left
						if (joy_l(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_P) <= '1'; end if; -- right
						if (joy_l(SC_BTN_B) = '1') then kb_data(ZX_K_M) <= '1'; end if; -- fire	
					end if;
					if joy_type_r = "100" then
						if (joy_r(SC_BTN_UP) = '1') then kb_data(ZX_K_Q) <= '1'; end if; -- up
						if (joy_r(SC_BTN_DOWN) = '1') then kb_data(ZX_K_A) <= '1'; end if; -- down
						if (joy_r(SC_BTN_LEFT) = '1') then kb_data(ZX_K_O) <= '1'; end if; -- left
						if (joy_r(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_P) <= '1'; end if; -- right
						if (joy_r(SC_BTN_B) = '1') then kb_data(ZX_K_M) <= '1'; end if; -- fire					
					end if;

					-- quaps
					if joy_type_l = "101" then 
						if (joy_l(SC_BTN_UP) = '1') then kb_data(ZX_K_Q) <= '1'; end if; -- up
						if (joy_l(SC_BTN_DOWN) = '1') then kb_data(ZX_K_A) <= '1'; end if; -- down
						if (joy_l(SC_BTN_LEFT) = '1') then kb_data(ZX_K_O) <= '1'; end if; -- left
						if (joy_l(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_P) <= '1'; end if; -- right
						if (joy_l(SC_BTN_B) = '1') then kb_data(ZX_K_SP) <= '1'; end if; -- fire	
					end if;
					if joy_type_r = "101" then
						if (joy_r(SC_BTN_UP) = '1') then kb_data(ZX_K_Q) <= '1'; end if; -- up
						if (joy_r(SC_BTN_DOWN) = '1') then kb_data(ZX_K_A) <= '1'; end if; -- down
						if (joy_r(SC_BTN_LEFT) = '1') then kb_data(ZX_K_O) <= '1'; end if; -- left
						if (joy_r(SC_BTN_RIGHT) = '1') then kb_data(ZX_K_P) <= '1'; end if; -- right
						if (joy_r(SC_BTN_B) = '1') then kb_data(ZX_K_SP) <= '1'; end if; -- fire					
					end if;
				end if;

				
				-- cleanup CS key when SS is marked
				if (is_ss_used = '1' and is_cs_used = '0' and usb_ph = "101") then 
					kb_data(ZX_K_CS) <= '0';
				end if;
							
			end if;
		end if;
	end process;

	-- map L/R joysticks to kempston joy bus 
	process (RESET, CLK)
	begin
		if (RESET = '1') then 
			joy_do <= (others => '0');
		elsif rising_edge(CLK) then
			if joy_type_l = "000" then 
				joy_do(0) <= joy_l(SC_BTN_RIGHT);
				joy_do(1) <= joy_l(SC_BTN_LEFT);
				joy_do(2) <= joy_l(SC_BTN_DOWN);
				joy_do(3) <= joy_l(SC_BTN_UP);
				joy_do(4) <= joy_l(SC_BTN_B);
				joy_do(5) <= joy_l(SC_BTN_A);
				joy_do(6) <= joy_l(SC_BTN_X);
				joy_do(7) <= joy_l(SC_BTN_Y);
			elsif joy_type_r = "000" then
				joy_do(0) <= joy_r(SC_BTN_RIGHT);
				joy_do(1) <= joy_r(SC_BTN_LEFT);
				joy_do(2) <= joy_r(SC_BTN_DOWN);
				joy_do(3) <= joy_r(SC_BTN_UP);
				joy_do(4) <= joy_r(SC_BTN_B);
				joy_do(5) <= joy_r(SC_BTN_A);
				joy_do(6) <= joy_r(SC_BTN_X);
				joy_do(7) <= joy_r(SC_BTN_Y);
			else
				joy_do <= (others => '0');
			end if;
		end if;
	end process;

end rtl;