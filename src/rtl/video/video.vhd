-------------------------------------------------------------------------------
-- VIDEO Controller
-------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

entity video is
	generic (
		TEST : integer := 0
	);
	port (
		CLK_BUS	: in std_logic; -- 56
		CLK 		: in std_logic; -- 7 / 12 MHz
		RESET 	: in std_logic := '0';
		VMODE 	: in std_logic_vector(3 downto 0) := "0000";

		BORDER	: in std_logic_vector(7 downto 0);	-- bordr color (port #xxFE)
		TURBO 	: in std_logic_vector(2 downto 0) := "000"; -- 01 = turbo 2x mode, 10 - turbo 4x mode, 11 - turbo 8x mode, 00 = normal mode
		INTA		: in std_logic := '0'; -- int request for turbo mode
		INT		: out std_logic; -- int output
		ATTR_O	: out std_logic_vector(7 downto 0); -- attribute register output
		pFF_CS	: out std_logic; -- port FF select

		A 			: out std_logic_vector(13 downto 0); -- video mem address
		VID_RD	: out std_logic;
		DI			: in std_logic_vector(7 downto 0);	-- video data from memory

		VIDEO_R	: out std_logic_vector(2 downto 0);
		VIDEO_G	: out std_logic_vector(2 downto 0);
		VIDEO_B	: out std_logic_vector(2 downto 0);
		
		HSYNC		: out std_logic;
		VSYNC		: out std_logic;
		BLANK 	: out std_logic;
		
		ACTIVE 	: out std_logic;
		LOCK 		: out std_logic;
		
		CS7E 		: in std_logic := '0';
		BUS_A 	: in std_logic_vector(15 downto 8);
		BUS_D 	: in std_logic_vector(7 downto 0);
		BUS_WR_N : in std_logic;
		GX0 		: out std_logic;
		
		COUNT_BLOCK : out std_logic
	);
end entity;

architecture rtl of video is

	signal rgb 	 		: std_logic_vector(2 downto 0);
	signal i 			: std_logic;
	signal o_rgb 		: std_logic_vector(8 downto 0);
	
	type t_palette is array (0 to 15) of std_logic_vector(8 downto 0);
	signal palette		: t_palette := (
		0 => "000000000", 1 => "000000100", 2 =>  "000100000", 3 =>  "000100100", 4 =>  "100000000", 5 =>  "100000100", 6 =>  "100100000", 7 =>  "100100100",
		8 => "000000000", 9 => "000000110", 10 => "000110000", 11 => "000110110", 12 => "110000000", 13 => "110000110", 14 => "110110000", 15 => "110110110"
	);
	signal palette_a 	: std_logic_vector(3 downto 0);
	signal palette_wr_a 	: std_logic_vector(3 downto 0);
	signal palette_wr_data 	: std_logic_vector(7 downto 0);
	signal palette_wr : std_logic := '0';
	signal palette_need_wr : std_logic := '0';
	signal palette_grb: std_logic_vector(8 downto 0);
	signal palette_grb_reg: std_logic_vector(8 downto 0);
	signal palette_prev : std_logic_vector(15 downto 8);
	
	-- profi videocontroller signals
	signal vid_a_profi : std_logic_vector(13 downto 0);
	signal vid_rd_profi : std_logic;
	signal int_profi : std_logic;
	signal rgb_profi : std_logic_vector(2 downto 0);
	signal i_profi : std_logic;
	signal hsync_profi : std_logic;
	signal vsync_profi : std_logic;
	signal blank_profi : std_logic;
	signal pFF_CS_profi : std_logic;
	signal attr_o_profi : std_logic_vector(7 downto 0);
	
	signal active_profi : std_logic;
	signal lock_profi : std_logic;	
	
	-- spectrum videocontroller signals
	signal vid_a_spec : std_logic_vector(13 downto 0);
	signal vid_rd_spec : std_logic;
	signal int_spec : std_logic;
	signal rgb_spec : std_logic_vector(2 downto 0);
	signal i_spec : std_logic;
	signal hsync_spec : std_logic;
	signal vsync_spec : std_logic;
	signal blank_spec : std_logic;
	signal pFF_CS_spec : std_logic;
	signal attr_o_spec : std_logic_vector(7 downto 0);

	signal active_spec : std_logic;
	signal lock_spec : std_logic;

	signal ds80 : std_logic;

begin

	ds80 <= vmode(3);

	U_PENT: entity work.pentagon_video 
	generic map (
		TEST => TEST
	)
	port map (
		CLK => CLK, -- 7
		VMODE => VMODE,
		BORDER => BORDER(2 downto 0),
		TURBO => TURBO,
		INTA => INTA,
		INT => int_spec,
		pFF_CS => pFF_CS_spec,
		ATTR_O => attr_o_spec, 

		DI => DI,
		A => vid_a_spec,
		VID_RD => vid_rd_spec,

		RGB => rgb_spec,
		I 	 => i_spec,
		
		HSYNC => hsync_spec,
		VSYNC => vsync_spec,
		BLANK => blank_spec,

		ACTIVE => active_spec,
		LOCK => lock_spec,

		COUNT_BLOCK => COUNT_BLOCK
	);

	U_PROFI: entity work.profi_video 
	generic map (
		TEST => TEST
	)
	port map (
		CLK => CLK, -- 12
		VMODE => VMODE,

		TURBO => TURBO,
		BORDER => BORDER(3 downto 0),

		DI => DI,
		A => vid_a_profi,
		VID_RD => vid_rd_profi,

		INTA => INTA,
		INT => int_profi,
		pFF_CS => pFF_CS_profi,
		ATTR_O => attr_o_profi,

		RGB => rgb_profi,
		I 	 => i_profi,
		BLANK => blank_profi,

		ACTIVE => active_profi,
		LOCK => lock_profi,
		
		HSYNC => hsync_profi,
		VSYNC => vsync_profi
	);

	A <= vid_a_profi when ds80 = '1' else vid_a_spec;
	VID_RD <= vid_rd_profi when ds80 = '1' else vid_rd_spec;

	INT <= int_profi when ds80 = '1' else int_spec;

	rgb <= rgb_profi when ds80 = '1' else rgb_spec;
	i <= i_profi when ds80 = '1' else i_spec;

	HSYNC <= hsync_profi when ds80 = '1' else hsync_spec;
	VSYNC <= vsync_profi when ds80 = '1' else vsync_spec;	
	BLANK <= blank_profi when ds80 = '1' else blank_spec;
	ACTIVE <= active_profi when ds80 = '1' else active_spec;
	LOCK <= lock_profi when ds80 = '1' else lock_spec;
	
	ATTR_O <= attr_o_profi when ds80 = '1' else attr_o_spec;
	pFF_CS <= pFF_CS_profi when ds80 = '1' else pFF_CS_spec;
	
	-- Палитра profi:

	-- 1) палитра - это память на 16 ячеек. каждая ячейка - 8-битное значение цвета в виде GGGRRRBB
	-- 2) в палитру пишется инвертированное значение старшей половины адреса ША по адресу, заданному в порту #FE (тоже инвертированное значение)
	-- 3) строб записи по схеме формируется при обращении к порту палитры #7E в режиме DS80
	-- 4) при чтении адресом выступает код цвета от видеоконтроллера - YGRB
			
	-- запись палитры
	process(CLK_BUS, reset)
	begin
		if reset = '1' then 
			-- set default palette on reset
			palette <= (
				0 => "000000000", 1 => "000000100", 2 =>  "000100000", 3 =>  "000100100", 4 =>  "100000000", 5 =>  "100000100", 6 =>  "100100000", 7 =>  "100100100",
				8 => "000000000", 9 => "000000110", 10 => "000110000", 11 => "000110110", 12 => "110000000", 13 => "110000110", 14 => "110110000", 15 => "110110110"
			);
		elsif rising_edge(CLK_BUS) then 
			if palette_wr = '1' then
					palette(to_integer(unsigned(BORDER(3 downto 0) xor X"F"))) <= (not BUS_A) & BORDER(7);
			end if;
		end if;
	end process;
	
	palette_a <= i & rgb(1) & rgb(2) & rgb(0);
   palette_wr <= '1' when CS7E = '1' and BUS_WR_N = '0' and ds80 = '1' and reset = '0' else '0';

	-- чтение из палитры
	palette_grb <= palette(to_integer(unsigned(palette_a)));
	
	-- возвращаем наверх (top level) значение младшего разряда зеленого компонента палитры, это служит для отпределения наличия палитры в системе
	GX0 <= palette_grb(6) xor palette_grb(0) when ds80 = '1' else '1';
	
	-- применяем blank для профи, ибо в видеоконтроллере он после палитры
	process(blank_profi, vmode) 
	begin 
		if (blank_profi = '1' and VMODE(3) = '1') then
			palette_grb_reg <= (others => '0');
		else
			palette_grb_reg <= palette_grb;
		end if;
	end process;
	
	VIDEO_R <= palette_grb_reg(5 downto 3);
	VIDEO_G <= palette_grb_reg(8 downto 6);
	VIDEO_B <= palette_grb_reg(2 downto 0);

end architecture;