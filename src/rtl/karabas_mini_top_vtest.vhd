-------------------------------------------------------------------------------------------------------------------
-- TEST PROFI VIDEO -> HDMI
------------------------------------------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

library unisim;
use unisim.vcomponents.all;

entity karabas_mini is
    port ( CLK_50MHZ : in  STD_LOGIC;
           
           UART_RX : inout  STD_LOGIC;
           UART_TX : inout  STD_LOGIC;
           UART_CTS : inout  STD_LOGIC;
			  ESP_RESET_N : inout  STD_LOGIC;
           ESP_BOOT_N : inout  STD_LOGIC;

			  MA : out  STD_LOGIC_VECTOR (20 downto 0);
           MD : inout  STD_LOGIC_VECTOR (15 downto 0);
           MWR_N : out  STD_LOGIC_VECTOR (1 downto 0);
           MRD_N : out  STD_LOGIC_VECTOR (1 downto 0);

			  SDR_BA : out  STD_LOGIC_VECTOR (1 downto 0);
           SDR_A : out  STD_LOGIC_VECTOR (12 downto 0);
           SDR_CLK : out  STD_LOGIC;
           SDR_DQM : out  STD_LOGIC_VECTOR (1 downto 0);
           SDR_WE_N : out  STD_LOGIC;
           SDR_CAS_N : out  STD_LOGIC;
           SDR_RAS_N : out  STD_LOGIC;
           SDR_DQ : inout  STD_LOGIC_VECTOR (15 downto 0);
			  
			  SD_CS_N : out  STD_LOGIC := '1';
           SD_DI : out  STD_LOGIC := '1';
           SD_DO : in  STD_LOGIC;
           SD_CLK : out  STD_LOGIC := '1';
           SD_DET_N : in  STD_LOGIC;
			  
			  VGA_R : in  STD_LOGIC_VECTOR (7 downto 0);
           VGA_G : in  STD_LOGIC_VECTOR (7 downto 0);
           VGA_B : in  STD_LOGIC_VECTOR (7 downto 0);
           VGA_HS : in  STD_LOGIC;
           VGA_VS : in  STD_LOGIC;

			  TMDS_P : out STD_LOGIC_VECTOR(3 downto 0);
			  TMDS_N : out STD_LOGIC_VECTOR(3 downto 0);
			  
			  FT_SPI_CS_N : out  STD_LOGIC;
           FT_SPI_SCK : out  STD_LOGIC;
           FT_SPI_MISO : inout  STD_LOGIC;
           FT_SPI_MOSI : inout  STD_LOGIC;
           FT_INT_N : inout  STD_LOGIC;
           FT_CLK : inout  STD_LOGIC;
			  FT_AUDIO : in STD_LOGIC;
			  FT_DE : in STD_LOGIC;
			  FT_DISP : in STD_LOGIC;
			  FT_RESET : out STD_LOGIC;
			  FT_CLK_OUT : out STD_LOGIC;

           WA : out  STD_LOGIC_VECTOR (2 downto 0);
           WCS_N : out  STD_LOGIC_VECTOR(1 downto 0);
           WRD_N : out  STD_LOGIC;
           WWR_N : out  STD_LOGIC;
           WRESET_N : out  STD_LOGIC;
           WD : inout  STD_LOGIC_VECTOR (15 downto 0);

			  TAPE_IN : in  STD_LOGIC;
           TAPE_OUT : out  STD_LOGIC;
			  AUDIO_L : out STD_LOGIC;
			  AUDIO_R : out STD_LOGIC;
			  
			  ADC_CLK : out STD_LOGIC;
			  ADC_BCK : inout STD_LOGIC;
			  ADC_LRCK : inout STD_LOGIC;
			  ADC_DOUT : in STD_LOGIC;
           
           
			  MCU_CS_N : in  STD_LOGIC;
           MCU_SCK : in  STD_LOGIC;
           MCU_MOSI : in  STD_LOGIC;
           MCU_MISO : out  STD_LOGIC;
			  MCU_IO : in  std_logic_vector(3 downto 0);
			  
			  MIDI_TX : out std_logic;
			  MIDI_CLK : out std_logic;
			  MIDI_RESET_N : out std_logic;
			  
			  FLASH_CS_N : out std_logic;
			  FLASH_DO : in std_logic;
			  FLASH_DI : out std_logic;
			  FLASH_SCK : out std_logic;
			  FLASH_WP_N : out std_logic;
			  FLASH_HOLD_N : out std_logic
			  );
end karabas_mini;

architecture Behavioral of karabas_mini is

-- USB HID Mouse report
signal hid_ms_x 		: std_logic_vector(7 downto 0);
signal hid_ms_y		: std_logic_vector(7 downto 0);
signal hid_ms_z		: std_logic_vector(3 downto 0);
signal hid_ms_b		: std_logic_vector(2 downto 0);
signal hid_ms_upd 	: std_logic;

-- Video
signal vid_hsync		: std_logic;
signal vid_vsync		: std_logic;
signal vid_blank     : std_logic;
signal vid_rgb			: std_logic_vector(8 downto 0);
signal vid_rgb_osd 	: std_logic_vector(8 downto 0);
signal vid_scandoubler_enable : std_logic := '1';
signal vid_active 	: std_logic;
signal vid_lock 		: std_logic;
signal vmode 			: std_logic_vector(3 downto 0) := "0000";

signal host_vga_r    : std_logic_vector(7 downto 0);
signal host_vga_g    : std_logic_vector(7 downto 0);
signal host_vga_b    : std_logic_vector(7 downto 0);
signal host_vga_hs   : std_logic;
signal host_vga_vs   : std_logic;
signal host_vga_blank : std_logic;

signal hdmi_blank		: std_logic;
signal hdmi_vsync		: std_logic;
signal hdmi_hsync 	: std_logic;
signal hdmi_rgb		: std_logic_vector(23 downto 0);
signal hdmi_frame_reset : std_logic;	

-- OSD overlay
signal osd_command 	: std_logic_vector(15 downto 0);

-- SOFT switches command
signal softsw_command: std_logic_vector(15 downto 0);

-- Output audio
signal audio_mix_l			: std_logic_vector(15 downto 0);
signal audio_mix_r			: std_logic_vector(15 downto 0);

-- CLOCK
signal clk_bus			: std_logic;
signal clk_16 			: std_logic;
signal clk_8 			: std_logic;
signal clk_vid 		: std_logic;
signal clk_sdr 		: std_logic;
signal clk_12        : std_logic;
signal clk_rgb 		: std_logic;
signal clk_vga 		: std_logic;

signal ena_div2	: std_logic := '0';
signal ena_div4	: std_logic := '0';
signal ena_div8	: std_logic := '0';
signal ena_div16	: std_logic := '0';
signal ena_div32  : std_logic := '0';
signal ena_cpu 	: std_logic := '0';
signal ena_rgb		: std_logic := '0';
signal ena_rgb_clk : std_logic := '0';

-- System
signal reset			: std_logic;
signal areset			: std_logic;

-- usb hid keyboard
signal hid_kb_status : std_logic_vector(7 downto 0);
signal hid_kb_dat0 : std_logic_vector(7 downto 0);
signal hid_kb_dat1 : std_logic_vector(7 downto 0);
signal hid_kb_dat2 : std_logic_vector(7 downto 0);
signal hid_kb_dat3 : std_logic_vector(7 downto 0);
signal hid_kb_dat4 : std_logic_vector(7 downto 0);
signal hid_kb_dat5 : std_logic_vector(7 downto 0);
signal mcu_busy : std_logic;

-- sega gamepads / atari joy from mcu
signal joy_l : std_logic_vector(12 downto 0);
signal joy_r : std_logic_vector(12 downto 0);

-- keyboard switches
signal kb_ds80 	: std_logic := '0';
signal kb_60hz		: std_logic := '0';
signal kb_screen  : std_logic_vector(1 downto 0) := "00";
signal kb_reset 	: std_logic := '0';

begin

-- Global signals
reset <= areset or kb_reset or mcu_busy; -- hot reset

-- Clock generator
U1: entity work.clock
port map(
	CLK => CLK_50MHZ,	
	ARESET => areset,
	
	DS80 => kb_ds80,
	
	CLK_BUS => clk_bus, -- 56 / 48
	CLK_16 	=> clk_16,
	CLK_8 	=> clk_8,
	CLK_SDR  => clk_sdr, -- 84
	CLK_12   => clk_12,

	ENA_DIV2 => ena_div2, -- 28 / 24
	ENA_DIV4 => ena_div4, -- 14 / 12
	ENA_DIV8 => ena_div8, -- 7 / 6
	ENA_DIV16 => ena_div16, -- 3.5 / 3
	ENA_DIV32 => ena_div32, -- 1.75 / 1.5
	ENA_CPU => ena_cpu,
	
	TURBO => "000",
	WAIT_CPU => '0'
	
);

ena_rgb <= ena_div2 and ena_div4 when kb_ds80 = '1' else ena_div2 and ena_div4 and ena_div8;
U_CLK_RGB: BUFGCE port map(I => clk_bus, O => clk_rgb, CE => ena_rgb);
U_CLK_VGA: BUFGCE port map(I => clk_bus, O => clk_vga, CE => ena_div2);

vmode <= kb_ds80 & kb_screen & kb_60hz;

-- Video Spectrum/Pentagon
U4: entity work.video
generic map (
	TEST => 1
)
port map (
	CLK_BUS			=> clk_bus,
	CLK 				=> clk_rgb,
	RESET 			=> reset,	
	VMODE				=> vmode,

	BORDER 			=> "01010101",
	TURBO 			=> "000",	-- turbo signal for int length
	INTA 				=> '1',
	INT 				=> open,
	pFF_CS			=> open,      -- port FF select
	ATTR_O 			=> open,  -- attribute register output

	A 					=> open,
	VID_RD 			=> open,
	DI 				=> (others => '0'),

	CS7E				=> '0',
	BUS_A 			=> (others => '0'),
	BUS_D 			=> (others => '0'),
	BUS_WR_N 		=> '1',
	GX0 				=> open,	
	VIDEO_R 			=> vid_rgb(8 downto 6),
	VIDEO_G 			=> vid_rgb(5 downto 3),
	VIDEO_B 			=> vid_rgb(2 downto 0),	
	HSYNC 			=> vid_hsync,
	VSYNC 			=> vid_vsync,
	BLANK 			=> vid_blank,
	COUNT_BLOCK 	=> open,

	ACTIVE			=> vid_active,
	LOCK 				=> vid_lock
);

-- osd overlay
U5: entity work.overlay
port map (
	CLK_BUS			=> clk_bus,
	CLK 				=> clk_rgb,
	VMODE				=> vmode,
	RGB_I 			=> vid_rgb,
	RGB_O 			=> vid_rgb_osd,
	PIXEL_EN			=> vid_active,
	FRAME_SYNC		=> vid_lock,

	-- icons
	STATUS_FD		=> '1',
	STATUS_SD 		=> '1',
	STATUS_CF 		=> '1',
	
	OSD_COMMAND 	=> osd_command
);

-- HDMI Scandoubler
U6: entity work.hdmi_frame
port map(
	clk => clk_bus,
	clk_rgb => clk_rgb,
	clk_vga => clk_vga,
	reset => areset,
	vmode => vmode,

	rgb => vid_rgb_osd,
	rgb_active => vid_active,
	frame_lock => vid_lock,
	
	hdmi_rgb => hdmi_rgb,
	hdmi_hs => hdmi_hsync,
	hdmi_vs => hdmi_vsync,
	hdmi_blank => hdmi_blank,
	hdmi_frame_reset => hdmi_frame_reset
);

-- HDMI encoder
U_HDMI: entity work.hdmi_top
generic map(
	SAMPLERATE => 44100
)
port map(
	clk	=> clk_bus,
	clk28en => ena_div2,
	clk_ref => clk_bus,
	ds80 => kb_ds80,
	reset => areset or kb_reset,
	vga_rgb => hdmi_rgb,
	vga_hs => hdmi_hsync,
	vga_vs => hdmi_vsync,
	vga_de => not hdmi_blank,
	audio_en => '1',
	audio_l => audio_mix_l,
	audio_r => audio_mix_r,
	tmds_p => TMDS_P,
	tmds_n => TMDS_N,
	freq => open,
	clk_pix => open
);

-- MCU
U7: entity work.mcu
port map(
	CLK => clk_bus,
	N_RESET => not areset,
	
	MCU_MOSI => MCU_MOSI,
	MCU_MISO => MCU_MISO,
	MCU_SCK => MCU_SCK,
	MCU_SS => MCU_CS_N,
	MCU_SPI_FT_SS => MCU_IO(3),
	MCU_SPI_SD2_SS => MCU_IO(2),
	
	MS_X => hid_ms_x,
	MS_Y => hid_ms_y,
	MS_Z => hid_ms_z,
	MS_B => hid_ms_b,
	MS_UPD => hid_ms_upd,
	
	KB_STATUS => hid_kb_status,
	KB_DAT0 => hid_kb_dat0,
	KB_DAT1 => hid_kb_dat1,
	KB_DAT2 => hid_kb_dat2,
	KB_DAT3 => hid_kb_dat3,
	KB_DAT4 => hid_kb_dat4,
	KB_DAT5 => hid_kb_dat5,
	
	JOY_L => joy_l,
	JOY_R => joy_r,
	
	RTC_A => (others => '0'),
	RTC_DI => (others => '0'),
	RTC_DO => open,
	RTC_CS => '0',
	RTC_WR_N => '1',
	
	UART_RX_DATA => open,
	UART_RX_IDX	=> open,
	UART_TX_DATA => (others => '0'),
	UART_TX_WR => '0',
	UART_TX_MODE => '0',
	UART_DLM => (others => '0'),
	UART_DLL => (others => '0'),
	UART_DLM_WR => '0',
	UART_DLL_WR => '0',
	
	ROMLOADER_ACTIVE => open,
	ROMLOAD_ADDR => open,
	ROMLOAD_DATA => open,
	ROMLOAD_WR => open,
	
	SOFTSW_COMMAND => softsw_command,	
	OSD_COMMAND => osd_command,

	-- ft by mcu isn't supported by this core
	FT_VGA_ON => open,
	FT_SPI_ON => open,
	FT_CS_N => open,
	FT_MOSI => open,
	FT_MISO => '1',
	FT_SCK => open,

	-- sd2 isn't supported by this core
	SD2_CS_N => open,
	SD2_MOSI => open,
	SD2_MISO => '1',
	SD2_SCK => open,
	
	BUSY => mcu_busy
	
);

-- Soft switches parser from MCU
U9: entity work.soft_switches
port map (
	CLK => clk_bus,
	
	SOFTSW_COMMAND => softsw_command,
	
	ROM_BANK => open,
	COVOX => open,
	PSG_MIX => open,
	PSG_TYPE => open,
	TURBO => open,
	JOY_TYPE_L => open,
	JOY_TYPE_R => open,
	MODE => kb_screen,
	DIVMMC_EN => open,
	NEMOIDE_EN => open,
	KB_TYPE => open,
	PAUSE => open,
	GS_RESET => open,
	NMI => open,
	RESET => kb_reset	
);

-------- unused

MA <= (others => '0');
MD <= (others => 'Z');
MRD_N <= "11";
MWR_N <= "11";
AUDIO_L <= '0';
AUDIO_R <= '0';
ADC_BCK <= '0';
ADC_LRCK <= '0';
ADC_CLK <= '0';
MIDI_TX <= '0';
UART_TX <= '0'; 
UART_CTS <= '0'; 
ESP_RESET_N <= 'Z';
ESP_BOOT_N <= 'Z';
WA <= (others => '0');
WCS_N <= (others => '0');
WRD_N <= '1';
WWR_N <= '1';
WRESET_N <= '1';
SDR_CLK <= '0';
SDR_DQ <= (others => 'Z');
SDR_A <= (others => '0');
SDR_DQM <= (others => '0');
SDR_BA <= (others => '0');
SDR_WE_N <= '1';
SDR_RAS_N <= '1';
SDR_CAS_N <= '1';
SD_CS_N	<= '1';
SD_CLK 	<= '1';
SD_DI 	<= '1';
TAPE_OUT <= '0';
FT_SPI_CS_N <= '1';
FT_SPI_SCK <= '0';
FT_CLK_OUT <= '0';
FT_RESET <= '1';
FLASH_CS_N <= '1';
FLASH_DI <= '1';
FLASH_SCK <= '1';
FLASH_WP_N <= '1';
FLASH_HOLD_N <= '1';
MIDI_RESET_N <= not reset;

u_midi_clk: ODDR2 
port map(Q => MIDI_CLK, C0 => clk_12, C1 => not clk_12, CE => '1', D0 => '1', D1 => '0', R => '0', S => '0');

end Behavioral;

