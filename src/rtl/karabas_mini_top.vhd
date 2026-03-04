-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######                                         ############### ############### 
--                                                                                 #               #             # 
--                                                                                 #   ########### #             # 
--                                                                                 #             # #             # 
-- https://github.com/andykarpov/karabas-go                                        ############### ############### 
--
-- FPGA Profi (Karabas Pro) core for Karabas-Go Mini
--
-- @author Andy Karpov <https://github.com/andykarpov>
-- @author Oleh Starychenko <https://github.com/solegstar>
-- @author Oleh Chastukhin <https://github.com/Caasper911>
-- @author Alexander Sharihin <https://github.com/nihirash>
-- @author Doctor Max <https://github.com/drmax-gc>
-- EU, 2024, 2025, 2026

------------------------------------------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

library unisim;
use unisim.vcomponents.all;

entity karabas_mini is
port (
	CLK_50MHZ 		: in  STD_LOGIC;

	UART_RX 			: inout  STD_LOGIC;
	UART_TX 			: inout  STD_LOGIC;
	UART_CTS 		: inout  STD_LOGIC;
	ESP_RESET_N 	: inout  STD_LOGIC;
	ESP_BOOT_N 		: inout  STD_LOGIC;

	MA 				: out  STD_LOGIC_VECTOR (20 downto 0);
	MD 				: inout  STD_LOGIC_VECTOR (15 downto 0);
	MWR_N 			: out  STD_LOGIC_VECTOR (1 downto 0);
	MRD_N 			: out  STD_LOGIC_VECTOR (1 downto 0);

	SDR_BA 			: out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_A 			: out  STD_LOGIC_VECTOR (12 downto 0);
	SDR_CLK 			: out  STD_LOGIC;
	SDR_DQM 			: out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_WE_N 		: out  STD_LOGIC;
	SDR_CAS_N 		: out  STD_LOGIC;
	SDR_RAS_N 		: out  STD_LOGIC;
	SDR_DQ 			: inout  STD_LOGIC_VECTOR (15 downto 0);

	SD_CS_N 			: out  STD_LOGIC := '1';
	SD_DI 			: out  STD_LOGIC := '1';
	SD_DO 			: in  STD_LOGIC;
	SD_CLK 			: out  STD_LOGIC := '1';
	SD_DET_N 		: in  STD_LOGIC;

	VGA_R 			: in  STD_LOGIC_VECTOR (7 downto 0);
	VGA_G 			: in  STD_LOGIC_VECTOR (7 downto 0);
	VGA_B 			: in  STD_LOGIC_VECTOR (7 downto 0);
	VGA_HS 			: in  STD_LOGIC;
	VGA_VS 			: in  STD_LOGIC;

	TMDS_P 			: out STD_LOGIC_VECTOR(3 downto 0);
	TMDS_N 			: out STD_LOGIC_VECTOR(3 downto 0);

	FT_SPI_CS_N 	: out  STD_LOGIC;
	FT_SPI_SCK 		: out  STD_LOGIC;
	FT_SPI_MISO 	: inout  STD_LOGIC;
	FT_SPI_MOSI 	: inout  STD_LOGIC;
	FT_INT_N 		: inout  STD_LOGIC;
	FT_CLK 			: inout  STD_LOGIC;
	FT_AUDIO 		: in STD_LOGIC;
	FT_DE 			: in STD_LOGIC;
	FT_DISP 			: in STD_LOGIC;
	FT_RESET 		: out STD_LOGIC;
	FT_CLK_OUT 		: out STD_LOGIC;

	WA 				: out  STD_LOGIC_VECTOR (2 downto 0);
	WCS_N 			: out  STD_LOGIC_VECTOR(1 downto 0);
	WRD_N 			: out  STD_LOGIC;
	WWR_N 			: out  STD_LOGIC;
	WRESET_N 		: out  STD_LOGIC;
	WD 				: inout  STD_LOGIC_VECTOR (15 downto 0);

	TAPE_IN 			: in  STD_LOGIC;
	TAPE_OUT 		: out  STD_LOGIC;
	AUDIO_L 			: out STD_LOGIC;
	AUDIO_R 			: out STD_LOGIC;

	ADC_CLK 			: out STD_LOGIC;
	ADC_BCK 			: out STD_LOGIC;
	ADC_LRCK 		: out STD_LOGIC;
	ADC_DOUT 		: in STD_LOGIC;

	MCU_CS_N 		: in  STD_LOGIC;
	MCU_SCK 			: in  STD_LOGIC;
	MCU_MOSI 		: in  STD_LOGIC;
	MCU_MISO 		: out  STD_LOGIC;
	MCU_IO 			: in  std_logic_vector(3 downto 0);

	MIDI_TX 			: out std_logic;
	MIDI_CLK 		: out std_logic;
	MIDI_RESET_N 	: out std_logic;

	FLASH_CS_N 		: out std_logic;
	FLASH_DO 		: in std_logic;
	FLASH_DI 		: out std_logic;
	FLASH_SCK 		: out std_logic;
	FLASH_WP_N 		: out std_logic;
	FLASH_HOLD_N 	: out std_logic
);
end karabas_mini;

architecture Behavioral of karabas_mini is

-- signals
signal clk_bus, clk_rgb, clk_vga, clk_adc, clk_sdr, clk_12, clk_8 : std_logic;
signal areset, reset, kb_reset : std_logic;

signal vid_rgb : std_logic_vector(8 downto 0);
signal vid_hs, vid_vs, vid_frame, vid_pixel, vid_blank, vid_scandoubler_en : std_logic;
signal vmode : std_logic_vector(3 downto 0);

signal audio_mix_l, audio_mix_r : std_logic_vector(15 downto 0);
signal adc_l, adc_r : std_logic_vector(23 downto 0);

signal hdmi_rgb : std_logic_vector(23 downto 0);
signal hdmi_hsync, hdmi_vsync, hdmi_blank : std_logic;
signal dvi_only : std_logic;

begin

U1: entity work.profi
generic map(
	ENABLE_FDD		=> false
)
port map(
		-- clock
	CLK_50MHZ 		=> CLK_50MHZ,
	CLK_BUS			=> clk_bus,
	CLK_SDR			=> clk_sdr,
	CLK_12			=> clk_12,
	CLK_8 			=> clk_8,
	
	RESET 			=> reset,
	ARESET 			=> areset,
	KB_RESET			=> kb_reset,

	-- uart
	UART_RX			=> UART_RX,
	UART_TX			=> UART_TX,
	UART_CTS			=> UART_CTS, 

	-- sram
	MA 				=> MA,
	MD					=> MD, 
	MWR_N				=> MWR_N,
	MRD_N				=> MRD_N,

	-- sdram
	SDR_BA 			=> SDR_BA,
	SDR_A				=> SDR_A,
	SDR_DQM			=> SDR_DQM,
	SDR_WE_N 		=> SDR_WE_N,
	SDR_CAS_N		=> SDR_CAS_N,
	SDR_RAS_N 		=> SDR_RAS_N,
	SDR_DQ			=> SDR_DQ,

	-- sd card
	SD_CS_N 			=> SD_CS_N,
	SD_DI 			=> SD_DI,
	SD_DO 			=> SD_DO,
	SD_CLK 			=> SD_CLK,
	SD_DET_N			=> SD_DET_N,

	-- rgb
	RGB_CLK 			=> clk_rgb,
	VGA_CLK			=> clk_vga,
	RGB 				=> vid_rgb,
	RGB_HS 			=> vid_hs,
	RGB_VS 			=> vid_vs,
	RGB_BLANK		=> vid_blank,
	RGB_FRAME		=> vid_frame,
	RGB_PIXEL 		=> vid_pixel,
	SCANDOUBLER 	=> vid_scandoubler_en,
	VMODE				=> vmode,
	DVI_ONLY			=> dvi_only,

	-- cf card
	WA 				=> WA,
	WCS_N 			=> WCS_N, 
	WRD_N 			=> WRD_N, 
	WWR_N				=> WWR_N,
	WRESET_N 		=> WRESET_N,
	WD 				=> WD,

	-- audio
	TAPE_IN 			=> TAPE_IN,
	TAPE_OUT 		=> TAPE_OUT,
	BEEPER			=> open, 
	AUDIO_L 			=> audio_mix_l,
	AUDIO_R 			=> audio_mix_r,

	-- adc
	ADC_CLK 			=> clk_adc,
	ADC_L 			=> adc_l,
	ADC_R				=> adc_r,

	-- mcu
	MCU_CS_N 		=> MCU_CS_N,
	MCU_SCK 			=> MCU_SCK,
	MCU_MOSI 		=> MCU_MOSI,
	MCU_MISO 		=> MCU_MISO,
	MCU_IO 			=> MCU_IO,

	-- midi
	MIDI_TX 			=> MIDI_TX,
	MIDI_RESET_N 	=> MIDI_RESET_N,

	-- floppy
	FDC_INDEX 		=> '1',
	FDC_DRIVE 		=> open, 
	FDC_MOTOR 		=> open,
	FDC_DIR 			=> open, 
	FDC_STEP 		=> open,
	FDC_WDATA 		=> open,
	FDC_WGATE 		=> open,
	FDC_TR00 		=> '1',
	FDC_WPRT 		=> '1', 
	FDC_RDATA 		=> '1', 
	FDC_SIDE_N 		=> open
);

-- HDMI Scandoubler
U2: entity work.hdmi_frame
port map(
	clk_rgb 			=> clk_rgb,
	clk_vga 			=> clk_vga,
	reset 			=> areset,
	vmode 			=> vmode,

	rgb 				=> vid_rgb,
	rgb_active 		=> vid_pixel,
	frame_lock 		=> vid_frame,
	
	hdmi_rgb 		=> hdmi_rgb,
	hdmi_hs 			=> hdmi_hsync,
	hdmi_vs 			=> hdmi_vsync,
	hdmi_blank 		=> hdmi_blank,
	hdmi_frame_reset => open
);

-- HDMI encoder
U_HDMI: entity work.zhdmi_top
generic map(
	SAMPLERATE 		=> 44100
)
port map(
	clk				=> clk_vga,
	ds80 				=> vmode(3),
	reset 			=> areset or kb_reset,
	vga_rgb 			=> hdmi_rgb,
	vga_hs 			=> hdmi_hsync,
	vga_vs 			=> hdmi_vsync,
	vga_de 			=> not hdmi_blank,
	audio_en 		=> not dvi_only,
	audio_l 			=> audio_mix_l,
	audio_r 			=> audio_mix_r,
	tmds_p 			=> TMDS_P,
	tmds_n 			=> TMDS_N
);

-- Audio PWM
U_DAC_L: entity work.dac
port map(
	I_CLK 			=> clk_bus,
	I_RESET 			=> areset,
	I_DATA 			=> not(audio_mix_l(15)) & audio_mix_l(14 downto 0),
	O_DAC 			=> AUDIO_L
);

U_DAC_R: entity work.dac
port map(
	I_CLK 			=> clk_bus,
	I_RESET 			=> areset,
	I_DATA 			=> not(audio_mix_r(15)) & audio_mix_r(14 downto 0),
	O_DAC 			=> AUDIO_R
);

-- ADC
U_ADC: entity work.i2s_transceiver
generic map(
	mclk_sclk_ratio => 4 -- 28 / 4 = 7
)
port map(
	reset_n 			=> not areset,
	mclk 				=> clk_bus,
	sclk 				=> ADC_BCK,
	ws					=> ADC_LRCK,
	sd_rx 			=> ADC_DOUT,
	l_data_tx 		=> (others => '0'),
	r_data_tx 		=> (others => '0'),
	l_data_rx 		=> adc_l,
	r_data_rx 		=> adc_r
);

-- ADC_CLK output buf
U_ADC_CLK: ODDR2 
port map(
	Q 					=> ADC_CLK, 
	C0 				=> clk_adc, -- 28
	C1 				=> not clk_adc, 
	CE 				=> '1',
	D0 				=> '1',
	D1 				=> '0',
	R 					=> '0',
	S 					=> '0'
);

-- unused signals
ESP_RESET_N 		<= 'Z';
ESP_BOOT_N 			<= 'Z';

FT_SPI_CS_N 		<= '1';
FT_SPI_SCK 			<= '0';
FT_RESET 			<= not reset;
u_ft_clk: ODDR2 port map(Q => FT_CLK_OUT, C0 => clk_8, C1 => not clk_8, CE => '1', D0 => '1', D1 => '0', R => '0', S => '0');
u_midi_clk: ODDR2 port map(Q => MIDI_CLK, C0 => clk_12, C1 => not clk_12, CE => '1', D0 => '1', D1 => '0', R => '0', S => '0');

FLASH_CS_N 			<= '1';
FLASH_DI 			<= '1';
FLASH_SCK 			<= '1';
FLASH_WP_N 			<= '1';
FLASH_HOLD_N 		<= '1';

u_sdr_clk: ODDR2 -- negative DDR clock
generic map(
	DDR_ALIGNMENT 	=> "NONE",
	INIT				=> '0',
	SRTYPE			=> "SYNC"
)
port map(
	Q 					=> SDR_CLK, 
	C0 				=> clk_sdr, 
	C1 				=> not(clk_sdr), 
	CE 				=> '1', 
	D0 				=> '0', 
	D1 				=> '1', 
	R 					=> '0', 
	S 					=> '0'
);

end Behavioral;

