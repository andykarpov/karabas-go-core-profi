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
-- FPGA Profi (Karabas Pro) core (blackbox) for Karabas Go & Karabas Go Mini
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

entity profi is
generic(
	ENABLE_FDD: boolean := true;
	ENABLE_GS : boolean := true;
	ENABLE_SERIAL_MOUSE : boolean := true
);
port ( 
	 
	-- clock
	CLK_50MHZ : in  STD_LOGIC;
	CLK_BUS : buffer std_logic;
	CLK_SDR : buffer std_logic;
	CLK_12: buffer std_logic;
	CLK_8 : buffer std_logic;
	
	RESET : buffer std_logic;
	ARESET : buffer std_logic;
	KB_RESET : buffer std_logic;

	-- uart
	UART_RX 	: in   STD_LOGIC;
	UART_TX 	: out  STD_LOGIC;
	UART_CTS : out  STD_LOGIC;

	-- sram
	MA : out  STD_LOGIC_VECTOR (20 downto 0);
	MD : inout  STD_LOGIC_VECTOR (15 downto 0);
	MWR_N : out  STD_LOGIC_VECTOR (1 downto 0);
	MRD_N : out  STD_LOGIC_VECTOR (1 downto 0);

	-- sdram
	SDR_BA : out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_A : out  STD_LOGIC_VECTOR (12 downto 0);
	SDR_CLK : out  STD_LOGIC;
	SDR_DQM : out  STD_LOGIC_VECTOR (1 downto 0);
	SDR_WE_N : out  STD_LOGIC;
	SDR_CAS_N : out  STD_LOGIC;
	SDR_RAS_N : out  STD_LOGIC;
	SDR_DQ : inout  STD_LOGIC_VECTOR (15 downto 0);

	-- sd card
	SD_CS_N : out  STD_LOGIC := '1';
	SD_DI : out  STD_LOGIC := '1';
	SD_DO : in  STD_LOGIC;
	SD_CLK : out  STD_LOGIC := '1';
	SD_DET_N : in  STD_LOGIC;

	-- rgb
	RGB_CLK : buffer std_logic;
	VGA_CLK : buffer std_logic;
	RGB : buffer std_logic_vector(8 downto 0);
	RGB_HS : buffer std_logic;
	RGB_VS : buffer std_logic;
	RGB_BLANK : buffer std_logic;
	RGB_FRAME: out std_logic;
	RGB_PIXEL : out std_logic;
	SCANDOUBLER : out std_logic;
	VMODE : buffer std_logic_vector(3 downto 0);
	DVI_ONLY : out std_logic;

	-- cf card
	WA : out  STD_LOGIC_VECTOR (2 downto 0);
	WCS_N : out  STD_LOGIC_VECTOR(1 downto 0);
	WRD_N : out  STD_LOGIC;
	WWR_N : out  STD_LOGIC;
	WRESET_N : out  STD_LOGIC;
	WD : inout  STD_LOGIC_VECTOR (15 downto 0);

	-- audio
	TAPE_IN : in  STD_LOGIC;
	TAPE_OUT : out  STD_LOGIC;
	BEEPER	: out STD_LOGIC;
	AUDIO_L : out STD_LOGIC_VECTOR(15 downto 0);
	AUDIO_R : out STD_LOGIC_VECTOR(15 downto 0);

	-- adc
	ADC_CLK : out STD_LOGIC;
	ADC_L : in std_logic_vector(23 downto 0) := (others => '0');
	ADC_R : in std_logic_vector(23 downto 0) := (others => '0');
	
	-- esp32 i2s audio in
	ESP_L	: in std_logic_vector(15 downto 0) := (others => '0');
	ESP_R : in std_logic_vector(15 downto 0) := (others => '0');

	-- mcu
	MCU_CS_N : in  STD_LOGIC;
	MCU_SCK : in  STD_LOGIC;
	MCU_MOSI : in  STD_LOGIC;
	MCU_MISO : out  STD_LOGIC;
	MCU_IO : in  std_logic_vector(3 downto 0);

	-- midi
	MIDI_TX : out std_logic;
	MIDI_RESET_N : out std_logic;

	-- floppy
	FDC_INDEX : in  STD_LOGIC;
	FDC_DRIVE : out  STD_LOGIC_VECTOR (1 downto 0);
	FDC_MOTOR : out  STD_LOGIC;
	FDC_DIR : out  STD_LOGIC;
	FDC_STEP : out  STD_LOGIC;
	FDC_WDATA : out  STD_LOGIC;
	FDC_WGATE : out  STD_LOGIC;
	FDC_TR00 : in  STD_LOGIC;
	FDC_WPRT : in  STD_LOGIC;
	FDC_RDATA : in  STD_LOGIC;
	FDC_SIDE_N : out  STD_LOGIC
);
end profi;

architecture Behavioral of profi is

-- CPU
signal cpu_reset_n		: std_logic;
signal cpu_a_bus			: std_logic_vector(15 downto 0);
signal cpu_do_bus			: std_logic_vector(7 downto 0);
signal cpu_di_bus			: std_logic_vector(7 downto 0);
signal cpu_mreq_n			: std_logic;
signal cpu_iorq_n			: std_logic;
signal cpu_wr_n			: std_logic;
signal cpu_rd_n			: std_logic;
signal cpu_int_n			: std_logic;
signal cpu_inta_n			: std_logic;
signal cpu_m1_n			: std_logic;
signal cpu_rfsh_n			: std_logic;
signal cpu_mult			: std_logic_vector(1 downto 0);
signal cpu_mem_wr			: std_logic;
signal cpu_mem_rd			: std_logic;
signal cpu_nmi_n			: std_logic;
signal cpu_wait_n 		: std_logic := '1';
signal cpu_wait 			: std_logic;

-- Port
signal port_xxfe_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_7ffd_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_1ffd_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_dffd_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_xx7e_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_008b_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_018b_reg		: std_logic_vector(7 downto 0) := "00000000";
signal port_028b_reg		: std_logic_vector(7 downto 0) := "00000000";

-------------8B_PORT------------------
signal rom0					: std_logic;
signal rom1					: std_logic;
signal rom2					: std_logic;
signal rom3					: std_logic;
signal rom4					: std_logic;
signal rom5					: std_logic;
signal ram0					: std_logic;
signal ram1					: std_logic;
signal ram2					: std_logic;
signal ram3					: std_logic;
signal ram4					: std_logic;
signal ram5					: std_logic;
signal ram6					: std_logic;
signal ram7					: std_logic;
signal onrom				: std_logic;
signal unlock_128			: std_logic;
signal turbo_mode			: std_logic_vector(1 downto 0) := "00";
signal lock_dffd			: std_logic;
signal sound_off			: std_logic;
signal hdd_type			: std_logic;
signal fdc_swap			: std_logic;
signal turbo_fdc_off		: std_logic;
signal hdd_off				: std_logic;
signal hdd_active			: std_logic;

-- Keyboard
signal kb_do_bus			: std_logic_vector(5 downto 0);
--signal kb_reset 			: std_logic := '0'; -- outer
signal kb_gs_reset   	: std_logic := '0';
signal kb_nmi 				: std_logic := '0';
signal kb_turbo 			: std_logic_vector(1 downto 0) := "00";
signal kb_turbo_old		: std_logic_vector(1 downto 0) := "00";
signal kb_pause 			: std_logic := '0';
signal joy_type 			: std_logic := '0';
signal joy_mode 			: std_logic_vector(2 downto 0) := "000";
signal kb_loaded 			: std_logic := '0';
signal kb_screen_mode	: std_logic_vector(1 downto 0) := "00";

-- Kempston Joy
signal joy_bus 			: std_logic_vector(7 downto 0) := "00000000";

-- Absolute Mouse
signal ms_x					: std_logic_vector(7 downto 0);
signal ms_y					: std_logic_vector(7 downto 0);
signal ms_z					: std_logic_vector(3 downto 0);
signal ms_b					: std_logic_vector(2 downto 0);

-- USB HID Mouse report
signal hid_ms_x 			: std_logic_vector(7 downto 0);
signal hid_ms_y			: std_logic_vector(7 downto 0);
signal hid_ms_z			: std_logic_vector(3 downto 0);
signal hid_ms_b			: std_logic_vector(2 downto 0);
signal hid_ms_upd 		: std_logic;
signal ms_present 		: std_logic := '0';

-- Video
signal vid_a_bus			: std_logic_vector(13 downto 0);
signal vid_di_bus			: std_logic_vector(7 downto 0);
signal vid_do_bus 		: std_logic_vector(7 downto 0);
signal vid_rd 				: std_logic := '0';

signal vid_hsync			: std_logic;
signal vid_vsync			: std_logic;
signal vid_blank     	: std_logic;
signal vid_pix_start 	: std_logic;
signal vid_int				: std_logic;
signal vid_pff_cs			: std_logic;
signal vid_int_n        : std_logic;
signal vid_attr			: std_logic_vector(7 downto 0);
signal vid_rgb				: std_logic_vector(8 downto 0);
signal vid_rgb_osd 		: std_logic_vector(8 downto 0);
signal vid_scandoubler_enable : std_logic := '1';
signal vid_active 		: std_logic;
signal vid_lock 			: std_logic;
--signal vmode 				: std_logic_vector(3 downto 0) := "0000"; -- outer

signal hdmi_blank			: std_logic;
signal hdmi_vsync			: std_logic;
signal hdmi_hsync 		: std_logic;
signal hdmi_rgb			: std_logic_vector(23 downto 0);

-- OSD overlay
signal osd_command 		: std_logic_vector(15 downto 0);

-- SOFT switches command
signal softsw_command	: std_logic_vector(15 downto 0);

-- loader
signal loader_act			: std_logic := '0';
signal loader_ram_do		: std_logic_vector(7 downto 0);
signal loader_ram_a		: std_logic_vector(31 downto 0);
signal loader_ram_wr 	: std_logic := '0';

-- Z-Controller
signal zc_do_bus			: std_logic_vector(7 downto 0);
signal zc_spi_start		: std_logic;
signal zc_wr_en			: std_logic;
signal zc_rd_en			: std_logic;
signal port77_wr			: std_logic;
signal zc_busy				: std_logic;

signal zc_cs_n				: std_logic;
signal zc_sclk				: std_logic;
signal zc_mosi				: std_logic;
signal zc_miso				: std_logic;

-- Nemo IDE
signal nemoide_en 		: std_logic;

--- DivMMC
signal divmmc_en			: std_logic;
signal automap				: std_logic;
signal port_e3_reg   	: std_logic_vector(7 downto 0);
signal mapterm 			: std_logic;
signal map3DXX 			: std_logic; 
signal map1F00 			: std_logic;
signal mapcond 			: std_logic;

-- MC146818A RTC
signal mc146818_wr		: std_logic;
signal mc146818_rd		: std_logic;
signal mc146818_a_bus	: std_logic_vector(7 downto 0);
signal mc146818_do_bus	: std_logic_vector(7 downto 0);
signal mc146818_busy		: std_logic;
signal port_eff7_reg		: std_logic_vector(7 downto 0);

-- Port selectors
signal fd_port 			: std_logic;
signal fd_sel 				: std_logic;
signal cs_xxfe 			: std_logic := '0'; 
signal cs_eff7 			: std_logic := '0';
signal cs_7ffd 			: std_logic := '0';
signal cs_1ffd 			: std_logic := '0';
signal cs_dffd 			: std_logic := '0';
signal cs_fffd 			: std_logic := '0';
signal cs_xxfd 			: std_logic := '0';
signal cs_xx7e 			: std_logic := '0';
signal cs_xx87 			: std_logic := '0';
signal cs_xxA7 			: std_logic := '0';
signal cs_xxC7 			: std_logic := '0';
signal cs_xxE7 			: std_logic := '0';
signal cs_xx67 			: std_logic := '0';
signal cs_rtc_ds 			: std_logic := '0';
signal cs_rtc_as 			: std_logic := '0';
signal cs_008b				: std_logic := '0';
signal cs_018b				: std_logic := '0';
signal cs_028b				: std_logic := '0';

-- Profi FDD ports
signal fdd_cs_pff_n		: std_logic;
signal fdd_cs_n			: std_logic;

-- TurboSound
signal ts_do_bus			: std_logic_vector(7 downto 0);
signal ssg_cn0_a			: std_logic_vector(7 downto 0);
signal ssg_cn0_b			: std_logic_vector(7 downto 0);
signal ssg_cn0_c			: std_logic_vector(7 downto 0);
signal ssg_cn1_a			: std_logic_vector(7 downto 0);
signal ssg_cn1_b			: std_logic_vector(7 downto 0);
signal ssg_cn1_c			: std_logic_vector(7 downto 0);
signal ssg_cn0_fm			: std_logic_vector(15 downto 0);
signal ssg_cn1_fm			: std_logic_vector(15 downto 0);
signal ssg_fm_ena 		: std_logic;
signal ts_bdir 			: std_logic;
signal ts_bc1				: std_logic;

-- Covox
signal covox_a				: std_logic_vector(7 downto 0);
signal covox_b				: std_logic_vector(7 downto 0);
signal covox_c				: std_logic_vector(7 downto 0);
signal covox_d				: std_logic_vector(7 downto 0);
signal covox_fb			: std_logic_vector(7 downto 0);

-- Output audio
signal audio_mix_l		: std_logic_vector(15 downto 0);
signal audio_mix_r		: std_logic_vector(15 downto 0);

-- SAA1099
signal saa_wr_n			: std_logic;
signal saa_out_l			: std_logic_vector(7 downto 0);
signal saa_out_r			: std_logic_vector(7 downto 0);

-- gs
signal gs_l 				: std_logic_vector(14 downto 0);
signal gs_r 				: std_logic_vector(14 downto 0);
signal gs_oe 				: std_logic := '0';
signal gs_do_bus	 		: std_logic_vector(7 downto 0);

-- gs memory
signal gs_mem_a			: std_logic_vector(20 downto 0);
signal gs_mem_di			: std_logic_vector(7 downto 0);
signal gs_mem_do			: std_logic_vector(7 downto 0);
signal gs_mem_rd_n		: std_logic;
signal gs_mem_wr_n		: std_logic;
signal gs_mem_rfsh_n		: std_logic;

-- adc
--signal adc_l 				: std_logic_vector(23 downto 0); -- outer
--signal adc_r 				: std_logic_vector(23 downto 0); -- outer

-- CLOCK
--signal clk_bus				: std_logic; -- outer
signal clk_16 				: std_logic;
--signal clk_8 				: std_logic; -- outer
signal clk_vid 			: std_logic;
--signal clk_sdr 			: std_logic; -- outer
--signal clk_12        	: std_logic; -- outer
signal clk_rgb 			: std_logic;
signal clk_vga 			: std_logic;
signal clk_adc				: std_logic;
signal clk_cpu          : std_logic;

signal ena_div2			: std_logic := '0';
signal ena_div4			: std_logic := '0';
signal ena_div8			: std_logic := '0';
signal ena_div16			: std_logic := '0';
signal ena_div2n			: std_logic := '0';
signal ena_div4n			: std_logic := '0';
signal ena_div8n			: std_logic := '0';
signal ena_div16n			: std_logic := '0';
signal ena_cpu 			: std_logic := '0';
signal ena_cpu_n			: std_logic := '0';
signal ena_rgb				: std_logic := '0';
signal ce_14				: std_logic := '0';

-- System
--signal reset				: std_logic; -- outer
--signal areset				: std_logic; -- outer
signal dos_act				: std_logic := '1';
signal selector			: std_logic_vector(7 downto 0);
signal mux					: std_logic_vector(3 downto 0);
signal speaker 			: std_logic := '0';
signal ram_do_bus 		: std_logic_vector(7 downto 0);
signal ram_oe_n 			: std_logic := '1';
signal ext_rom_bank  	: std_logic_vector(1 downto 0) := "00";
signal ext_rom_bank_pq	: std_logic_vector(1 downto 0) := "00";
signal max_turbo 			: std_logic_vector(1 downto 0) := "11";

signal port_xx87_reg 	: std_logic_vector(7 downto 0);
signal port_xxA7_reg 	: std_logic_vector(7 downto 0);
signal port_xxC7_reg 	: std_logic_vector(7 downto 0);
signal port_xxE7_reg 	: std_logic_vector(7 downto 0);
signal port_xx67_reg 	: std_logic_vector(7 downto 0);

-- ZXUNO regs / UART ports
signal zxuno_regrd      : std_logic;
signal zxuno_regwr      : std_logic;
signal zxuno_addr       : std_logic_vector(7 downto 0);
signal zxuno_regaddr_changed : std_logic;
signal zxuno_addr_oe_n  : std_logic;
signal zxuno_addr_to_cpu: std_logic_vector(7 downto 0);
signal zxuno_uart_do_bus : std_logic_vector(7 downto 0);
signal zxuno_uart_oe_n   : std_logic;
signal zxuno_uart_tx     : std_logic;
signal zxuno_uart_cts    : std_logic;

-- ZIFI UART 
signal zifi_do_bus 		: std_logic_vector(7 downto 0);
signal zifi_oe_n   		: std_logic := '1';
signal zifi_uart_tx 		: std_logic;
signal zifi_uart_cts 	: std_logic;
signal zifi_api_enabled : std_logic;

-- USB UART
signal usb_uart_rx_data : std_logic_vector(7 downto 0);
signal usb_uart_rx_idx 	: std_logic_vector(7 downto 0);
signal usb_uart_tx_data : std_logic_vector(7 downto 0);
signal usb_uart_tx_wr 	: std_logic;

-- serial mouse 
signal serial_ms_do_bus : std_logic_vector(7 downto 0);
signal serial_ms_oe_n 	: std_logic := '1';
signal serial_ms_int_n 	: std_logic := '1';

-- profi special signals
signal cpm 					: std_logic := '0';
signal worom 				: std_logic := '0';
signal ds80 				: std_logic := '0';
signal scr 					: std_logic := '0';
signal sco 					: std_logic := '0';
signal rom14 				: std_logic := '0';
signal gx0 					: std_logic := '0';

-- memory contention
signal count_block 		: std_logic := '0';
signal memory_contention : std_logic := '0';

-- usb hid keyboard
signal hid_kb_status 	: std_logic_vector(7 downto 0);
signal hid_kb_dat0 		: std_logic_vector(7 downto 0);
signal hid_kb_dat1 		: std_logic_vector(7 downto 0);
signal hid_kb_dat2 		: std_logic_vector(7 downto 0);
signal hid_kb_dat3 		: std_logic_vector(7 downto 0);
signal hid_kb_dat4 		: std_logic_vector(7 downto 0);
signal hid_kb_dat5 		: std_logic_vector(7 downto 0);

-- sega gamepads / atari joy from mcu
signal joy_l 				: std_logic_vector(12 downto 0);
signal joy_r 				: std_logic_vector(12 downto 0);

-- keyboard switches
signal kb_vsync 			: std_logic := '0'; -- 50 Hz only in mini go
signal kb_joy_type_l 	: std_logic_vector(2 downto 0) := "000";
signal kb_joy_type_r 	: std_logic_vector(2 downto 0) := "000";
signal kb_keycode 		: std_logic_vector(7 downto 0) := x"FF";
signal kb_rom_bank 		: std_logic_vector(1 downto 0) := "00";
signal prev_kb_rom_bank : std_logic_vector(1 downto 0) := "00";
signal rom_bank_reset 	: std_logic := '0';
signal kb_turbofdc 		: std_logic := '0'; -- disabled in mini go
signal kb_covox 			: std_logic := '0';
signal kb_psg_mix 		: std_logic_vector(1 downto 0) := "00";
signal kb_psg_type 		: std_logic := '0';
signal kb_video 			: std_logic := '0'; -- 31 kHz only in mini go
signal kb_swap_fdd 		: std_logic := '0'; -- disabled in mini go
signal kb_divmmc_en 		: std_logic := '0';
signal kb_nemoide_en 	: std_logic := '0';
signal kb_type 			: std_logic := '0';
signal mcu_busy 			: std_logic := '1';

-- HDD signals
signal ide_do_bus 		: std_logic_vector(7 downto 0);
signal ide_oe_n			: std_logic := '1';
signal ide_busy 			: std_logic := '0';

-- FDD signals
signal fdd_do_bus 		: std_logic_vector(7 downto 0);
signal fdd_oe_n 			: std_logic := '1';
signal fdd_mode 			: std_logic_vector(1 downto 0);

signal loa 					: std_logic_vector(7 downto 0);
signal hia					: std_logic_vector(15 downto 8);
signal io_rd				: std_logic := '0';

component zxunoregs
port (
	clk             : in std_logic;
	rst_n           : in std_logic;
	a               : in std_logic_vector(15 downto 0);
	iorq_n          : in std_logic;
	rd_n            : in std_logic;
	wr_n            : in std_logic;
	din             : in std_logic_vector(7 downto 0);
	dout            : out std_logic_vector(7 downto 0);
	oe_n            : out std_logic;
	addr            : out std_logic_vector(7 downto 0);
	read_from_reg   : out std_logic;
	write_to_reg    : out std_logic;
	regaddr_changed : out std_logic);
end component;

component zxunouart
generic (
	UARTDATA        : std_logic_vector(7 downto 0) := x"C6";
	UARTSTAT        : std_logic_vector(7 downto 0) := x"C7"
);
port (
	clk_bus         : in std_logic;
	ds80            : in std_logic;
	enabled         : in std_logic;
	zxuno_addr      : in std_logic_vector(7 downto 0);
	zxuno_regrd     : in std_logic;
	zxuno_regwr     : in std_logic;
	din             : in std_logic_vector(7 downto 0);
	dout            : out std_logic_vector(7 downto 0);
	oe_n            : out std_logic;
	uart_tx         : out std_logic;
	uart_rx         : in std_logic;
	uart_rts        : out std_logic);
end component;

component uart 
port ( 
	clk_bus         : in std_logic;
	ds80            : in std_logic;
	enabled         : in std_logic;
	txdata          : in std_logic_vector(7 downto 0);
	txbegin         : in std_logic;
	txbusy          : out std_logic;
	rxdata          : out std_logic_vector(7 downto 0);
	rxrecv          : out std_logic;
	data_read       : in std_logic;
	rx              : in std_logic;
	tx              : out std_logic;
	rts             : out std_logic);
end component;

begin

-- Clock generator
U1: entity work.clock
port map(
	CLK 				=> CLK_50MHZ,	
	ARESET 			=> areset,
	
	DS80 				=> ds80,
	
	CLK_BUS 			=> clk_bus, -- 28 / 24
	CLK_16 			=> clk_16,
	CLK_8 			=> clk_8,
	CLK_SDR  		=> clk_sdr, -- 84
	CLK_12   		=> clk_12,
	CLK_RGB  		=> clk_rgb,
	CLK_VGA			=> clk_vga,
	CLK_ADC			=> clk_adc,
   CLK_CPU        => clk_cpu,

	ENA_DIV2 		=> ena_div2, -- 14 / 12 p
	ENA_DIV4 		=> ena_div4, -- 7 / 6 p
	ENA_DIV8 		=> ena_div8, -- 3.5 / 3 p
	ENA_DIV16 		=> ena_div16, -- 1.75 / 1.5 p

	ENA_DIV2N 		=> ena_div2n, -- 14 / 12 n
	ENA_DIV4N 		=> ena_div4n, -- 7 / 6 n
	ENA_DIV8N 		=> ena_div8n, -- 3.5 / 3 n 
	ENA_DIV16N 		=> ena_div16n, -- 1.75 / 1.5 n
	
	ENA_CPU 			=> ena_cpu,
	ENA_CPU_N		=> ena_cpu_n,
	ENA_RGB 			=> ena_rgb,
	
	CE_14 			=> ce_14,
	
	TURBO 			=> turbo_mode,
	WAIT_CPU 		=> cpu_wait
	
);

-- Zilog Z80A CPU
U2: entity work.T80pa
port map (
	RESET_n			=> cpu_reset_n,
	CLK				=> clk_bus,
	CEN_p				=> ena_cpu,
	CEN_n				=> ena_cpu_n,
	WAIT_n			=> cpu_wait_n,
	INT_n				=> cpu_int_n,
	NMI_n				=> cpu_nmi_n,
	BUSRQ_n			=> '1',
	M1_n				=> cpu_m1_n,
	MREQ_n			=> cpu_mreq_n,
	IORQ_n			=> cpu_iorq_n,
	RD_n				=> cpu_rd_n,
	WR_n				=> cpu_wr_n,
	RFSH_n			=> cpu_rfsh_n,
	HALT_n			=> open,
	BUSAK_n			=> open,
	OUT0				=> '1',
	A					=> cpu_a_bus,
	DI					=> cpu_di_bus,
	DO					=> cpu_do_bus
);

-- memory manager
U3: entity work.memory 
port map ( 
	CLK_BUS 			=> clk_bus,
	CLK_SDR			=> clk_sdr,
	ARESET			=> areset,
	ENA_CPU 			=> ena_cpu,
	ENA_GS			=> ena_div2, -- 14

	-- cpu signals
	A 					=> cpu_a_bus,
	D 					=> cpu_do_bus,
	N_MREQ 			=> cpu_mreq_n,
	N_IORQ 			=> cpu_iorq_n,
	N_WR 				=> cpu_wr_n,
	N_RD 				=> cpu_rd_n,
	N_M1 				=> cpu_m1_n,
	
	-- gs signals
	GS_A				=> gs_mem_a,
	GS_D				=> gs_mem_di,
	GS_DO				=> gs_mem_do,
	GS_N_RD			=> gs_mem_rd_n,
	GS_N_WR			=> gs_mem_wr_n,
	GS_N_RFSH		=> gs_mem_rfsh_n,
	
	-- loader signals
	loader_act 		=> loader_act,
	loader_ram_a 	=> loader_ram_a,
	loader_ram_do 	=> loader_ram_do,
	loader_ram_wr 	=> loader_ram_wr,

	-- sram phy
	MA 				=> MA,
	MD 				=> MD,
	N_MRD 			=> MRD_N,
	N_MWR 			=> MWR_N,
	
	-- sdram phy
	SDR_A				=> SDR_A,
	SDR_BA			=> SDR_BA,
	SDR_DQM			=> SDR_DQM,
	SDR_WE_N			=> SDR_WE_N,
	SDR_CAS_N		=> SDR_CAS_N,
	SDR_RAS_N		=> SDR_RAS_N,
	SDR_DQ			=> SDR_DQ,

	-- ram out to cpu
	DO 				=> ram_do_bus,
	N_OE 				=> ram_oe_n,	

	-- ram pages
	RAM_BANK 		=> port_7ffd_reg(2 downto 0),
	RAM_EXT 			=> port_dffd_reg(2 downto 0), -- seg A3 - seg A5

	-- TRDOS 
	TRDOS 			=> dos_act,	

	-- video
	VA 				=> vid_a_bus,
	VID_PAGE 		=> port_7ffd_reg(3), -- seg A0 - seg A2
	VID_DO 			=> vid_do_bus,
	VID_RD 			=> vid_rd, 		-- read attribute or pixel	

	-- system siglans
	DS80 				=> ds80,
	CPM 				=> cpm,
	SCO 				=> sco,
	SCR 				=> scr,
	WOROM 			=> worom,

	-- rom
	ROM_BANK 		=> rom14,      -- 0 B128, 1 B48
	EXT_ROM_BANK   => ext_rom_bank_pq,
	
	-- contended memory signals
	COUNT_BLOCK		=> count_block,
	CONTENDED 		=> memory_contention,

	-- OCH: added to not contend in turbo mode
	TURBO_MODE 		=> turbo_mode,
	
	-- DIVMMC signals
   DIVMMC_EN		=> divmmc_en,
	AUTOMAP			=> automap,
	REG_E3		   => port_e3_reg
);

-- Video Spectrum/Pentagon
U4: entity work.video
port map (
	CLK_BUS 			=> clk_bus, 	-- 28 / 24
	CLK 				=> clk_rgb,		-- 7 / 12
	RESET 			=> reset,
	VMODE				=> vmode,
	
	BORDER 			=> port_xxfe_reg(7 downto 0),
	TURBO 			=> turbo_mode,	-- turbo signal for int length
	INTA 				=> cpu_inta_n,
	INT 				=> vid_int_n,
	pFF_CS			=> vid_pff_cs, -- port FF select
	ATTR_O 			=> vid_attr,  -- attribute register output

	A 					=> vid_a_bus,
	VID_RD 			=> vid_rd,
	DI 				=> vid_do_bus,
	
	CS7E				=> cs_xx7e,
	BUS_A 			=> hia,
	BUS_D 			=> cpu_do_bus,
	BUS_WR_N 		=> cpu_wr_n,
	GX0 				=> gx0,	
	VIDEO_R 			=> vid_rgb(8 downto 6),
	VIDEO_G 			=> vid_rgb(5 downto 3),
	VIDEO_B 			=> vid_rgb(2 downto 0),	
	HSYNC 			=> vid_hsync,
	VSYNC 			=> vid_vsync,
	BLANK 			=> vid_blank,
	COUNT_BLOCK 	=> count_block,
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
	STATUS_FD		=> not(fdd_cs_n) and (not(cpu_rd_n) or not(cpu_wr_n)),
	STATUS_SD 		=> zc_spi_start and zc_wr_en,
	STATUS_CF 		=> hdd_active,
	
	OSD_COMMAND 	=> osd_command
);

-- MCU
U7: entity work.mcu
port map(
	CLK 				=> clk_bus,
	N_RESET 			=> not areset,
	
	MCU_MOSI 		=> MCU_MOSI,
	MCU_MISO 		=> MCU_MISO,
	MCU_SCK 			=> MCU_SCK,
	MCU_SS 			=> MCU_CS_N,
	MCU_SPI_FT_SS 	=> MCU_IO(3),
	MCU_SPI_SD2_SS => MCU_IO(2),
	
	MS_X 				=> hid_ms_x,
	MS_Y 				=> hid_ms_y,
	MS_Z 				=> hid_ms_z,
	MS_B 				=> hid_ms_b,
	MS_UPD 			=> hid_ms_upd,
	
	KB_STATUS 		=> hid_kb_status,
	KB_DAT0 			=> hid_kb_dat0,
	KB_DAT1 			=> hid_kb_dat1,
	KB_DAT2 			=> hid_kb_dat2,
	KB_DAT3 			=> hid_kb_dat3,
	KB_DAT4 			=> hid_kb_dat4,
	KB_DAT5 			=> hid_kb_dat5,
	
	JOY_L 			=> joy_l,
	JOY_R 			=> joy_r,
	
	RTC_A 			=> mc146818_a_bus,
	RTC_DI 			=> cpu_do_bus,
	RTC_DO 			=> mc146818_do_bus,
	RTC_CS 			=> '1',
	RTC_WR_N 		=> not mc146818_wr,
	
	UART_RX_DATA 	=> usb_uart_rx_data,
	UART_RX_IDX		=> usb_uart_rx_idx,
	UART_TX_DATA 	=> usb_uart_tx_data,
	UART_TX_WR 		=> usb_uart_tx_wr,
	
	ROMLOADER_ACTIVE => loader_act,
	ROMLOAD_ADDR 	=> loader_ram_a,
	ROMLOAD_DATA 	=> loader_ram_do,
	ROMLOAD_WR 		=> loader_ram_wr,
	
	SOFTSW_COMMAND => softsw_command,	
	OSD_COMMAND 	=> osd_command,

	-- ft by mcu isn't supported by this core
	FT_VGA_ON 		=> open,
	FT_SPI_ON 		=> open,
	FT_CS_N 			=> open,
	FT_MOSI			=> open,
	FT_MISO 			=> '1',
	FT_SCK 			=> open,

	-- sd2 isn't supported by this core
	SD2_CS_N 		=> open,
	SD2_MOSI 		=> open,
	SD2_MISO 		=> '1',
	SD2_SCK 			=> open,
	
	HWID				=> open,
	DVI_ONLY			=> DVI_ONLY,
	
	BUSY 				=> mcu_busy
	
);

-- USB HID parser / transformer to 8x5 matrix + joy mapper on keyboard
U8: entity work.hid_parser
port map (
	CLK 				=> clk_bus,
	RESET 			=> areset,	

	-- hid keyboard input
	KB_STATUS 		=> hid_kb_status,
	KB_DAT0 			=> hid_kb_dat0,
	KB_DAT1 			=> hid_kb_dat1,
	KB_DAT2 			=> hid_kb_dat2,
	KB_DAT3 			=> hid_kb_dat3,
	KB_DAT4 			=> hid_kb_dat4,
	KB_DAT5 			=> hid_kb_dat5,	

	-- joy inputs
	JOY_TYPE_L 		=> kb_joy_type_l(2 downto 0),
	JOY_TYPE_R 		=> kb_joy_type_r(2 downto 0),
	JOY_L 			=> joy_l,
	JOY_R 			=> joy_r,
	
	-- cpu a
	A 					=> hia,	
	
	-- keyboard type Profi XT = '0' / Spectrum = '1'
	KB_TYPE 			=> kb_type,
	
	-- outputs
	JOY_DO 			=> joy_bus,
	KB_DO 			=> kb_do_bus,
	KEYCODE 			=> kb_keycode
);

-- Soft switches parser from MCU
U9: entity work.soft_switches
port map (
	CLK 				=> clk_bus,
	
	SOFTSW_COMMAND => softsw_command,
	
	ROM_BANK 		=> kb_rom_bank,
	TURBO_FDC 		=> kb_turbofdc,
	COVOX 			=> kb_covox,
	PSG_MIX 			=> kb_psg_mix,
	PSG_TYPE 		=> kb_psg_type,
	VIDEO 			=> kb_video,
	VSYNC 			=> kb_vsync,
	TURBO 			=> kb_turbo,
	SWAP_FDD 		=> kb_swap_fdd,
	JOY_TYPE_L 		=> kb_joy_type_l,
	JOY_TYPE_R 		=> kb_joy_type_r,
	MODE 				=> kb_screen_mode,
	DIVMMC_EN 		=> kb_divmmc_en,
	NEMOIDE_EN 		=> kb_nemoide_en,
	KB_TYPE 			=> kb_type,
	PAUSE 			=> kb_pause,
	GS_RESET 		=> kb_gs_reset,
	NMI 				=> kb_nmi,
	RESET 			=> kb_reset	
);

-- USB HID mouse transformer to absolute coords
U10: entity work.cursor
port map(
	CLK 				=> clk_bus,
	RESET 			=> areset,
	
	-- inputs from usb hid mouse
	MS_X 				=> hid_ms_x,
	MS_Y 				=> hid_ms_y,
	MS_Z 				=> hid_ms_z,
	MS_B 				=> hid_ms_b,
	MS_UPD 			=> hid_ms_upd,
	
	-- output delta
	OUT_X 			=> ms_x,
	OUT_Y 			=> ms_y,
	OUT_Z 			=> ms_z,
	OUT_B 			=> ms_b
	
);

ms_present <= '1';

-- TurboSound
U12: entity work.turbosound
port map (
	RESET 			=> reset,
	CLK 				=> clk_bus,
	CE					=> ena_div8, -- 3.5
	BDIR 				=> ts_bdir,
	BC 				=> ts_bc1,
	DI					=> cpu_do_bus,
	DO 				=> ts_do_bus,
	AY_MODE 			=> kb_psg_type,
	
	SSG0_AUDIO_A	=> ssg_cn0_a,
	SSG0_AUDIO_B	=> ssg_cn0_b,
	SSG0_AUDIO_C	=> ssg_cn0_c,
	
	SSG1_AUDIO_A	=> ssg_cn1_a,
	SSG1_AUDIO_B	=> ssg_cn1_b,
	SSG1_AUDIO_C	=> ssg_cn1_c,
	
	SSG0_AUDIO_FM  => ssg_cn0_fm,
	SSG1_AUDIO_FM  => ssg_cn1_fm,
	SSG_FM_ENA     => ssg_fm_ena,
	MIDI_TX        => MIDI_TX
);

ts_bdir	<= '1' when (cpu_m1_n = '1' and cpu_iorq_n = '0' and cpu_wr_n = '0' and hia(15) = '1' and loa(1) = '0') else '0';
ts_bc1	<= '1' when (cpu_m1_n = '1' and cpu_iorq_n = '0' and hia(15 downto 14) = "11" and loa(1) = '0') else '0';

-- Covox / Soundrive
U13: entity work.covox
port map (
	I_RESET			=> reset,
	I_CLK				=> clk_bus,
	I_CS				=> kb_covox,
	I_WR_N			=> cpu_wr_n,
	I_ADDR			=> loa,
	I_DATA			=> cpu_do_bus,
	I_IORQ_N			=> cpu_iorq_n,
	I_DOS				=> dos_act,
	I_CPM 			=> cpm,
	I_ROM14 			=> rom14,
	O_A				=> covox_a,
	O_B				=> covox_b,
	O_C				=> covox_c,
	O_D				=> covox_d,
	O_FB 				=> covox_fb
);

-- SAA1099 sound generator
U14: entity work.saa1099
port map(
	clk				=> clk_8,
	ena				=> '1',
	rst_n				=> not reset,
	cs_n				=> '0',
	a0					=> hia(8),		-- 0=data, 1=address
	wr_n				=> saa_wr_n,
	din				=> cpu_do_bus,
	out_l				=> saa_out_l,
	out_r				=> saa_out_r
);

	
-- Serial mouse emulation
G_SERIAL_MOUSE: if ENABLE_SERIAL_MOUSE generate
U15: entity work.serial_mouse
port map(
	CLK 				=> clk_bus,
	CLKEN 			=> ena_cpu,
	N_RESET 			=> not(reset),
	A 					=> cpu_a_bus,
	DI					=> cpu_do_bus,
	WR_N 				=> cpu_wr_n,
	RD_N 				=> cpu_rd_n,
	IORQ_N 			=> cpu_iorq_n,
	M1_N 				=> cpu_m1_n,
	DS80				=> ds80,
	CPM 				=> cpm,
	DOS 				=> dos_act,
	ROM14 			=> rom14,
	
	MS_X 				=> ms_x,
	MS_Y				=> ms_y,
	MS_BTNS 			=> ms_b,
	MS_PRESET 		=> ms_present,
	MS_EVENT 		=> hid_ms_upd,
	
	DO 				=> serial_ms_do_bus,
	INT_N 			=> serial_ms_int_n,
	OE_N 				=> serial_ms_oe_n
);
end generate;

G_NO_SERIAL_MOUSE: if not(ENABLE_SERIAL_MOUSE) generate
	serial_ms_oe_n <= '1';
	serial_ms_int_n <= '1';
end generate;

-- ZXUNO UART
U16: zxunoregs 
port map(
	clk            => clk_bus,
	rst_n          => not(reset),
	a              => cpu_a_bus,
	iorq_n         => cpu_iorq_n,
	rd_n           => cpu_rd_n,
	wr_n           => cpu_wr_n,
	din            => cpu_do_bus,
	dout           => zxuno_addr_to_cpu,
	oe_n           => zxuno_addr_oe_n,
	addr           => zxuno_addr,
	read_from_reg  => zxuno_regrd,
	write_to_reg   => zxuno_regwr,
	regaddr_changed=> zxuno_regaddr_changed
);

U17: zxunouart 
port map(
	clk_bus        => clk_bus,
	ds80           => ds80,
	enabled        => not zifi_api_enabled,
	zxuno_addr     => zxuno_addr,
	zxuno_regrd    => zxuno_regrd,
	zxuno_regwr    => zxuno_regwr,
	din            => cpu_do_bus,
	dout           => zxuno_uart_do_bus,
	oe_n           => zxuno_uart_oe_n,
	uart_tx        => zxuno_uart_tx,
	uart_rx        => UART_RX,
	uart_rts       => zxuno_uart_cts
);

-- ZIFI for ESP8266 and USB UART
U18: entity work.zifi 
port map (
	CLK    			=> clk_bus,
	ENA_CPU			=> ena_cpu,
	RESET  			=> areset,
	DS80   			=> DS80,

	A      			=> cpu_a_bus,
	DI     			=> cpu_do_bus,
	DO     			=> zifi_do_bus,
	IORQ_N 			=> cpu_iorq_n,
	RD_N   			=> cpu_rd_n,
	WR_N   			=> cpu_wr_n,
	ZIFI_OE_N 		=> zifi_oe_n,
	
	ENABLED 			=> zifi_api_enabled,

	UART_RX   		=> UART_RX,
	UART_TX   		=> zifi_uart_tx,
	UART_CTS  		=> zifi_uart_cts,
	
	USB_UART_RX_DATA => usb_uart_rx_data,
	USB_UART_RX_IDX  => usb_uart_rx_idx,
	USB_UART_TX_DATA => usb_uart_tx_data,
	USB_UART_TX_WR   => usb_uart_tx_wr
);

UART_TX <= zifi_uart_tx when zifi_api_enabled = '1' else zxuno_uart_tx;
UART_CTS <= zifi_uart_cts when zifi_api_enabled = '1' else zxuno_uart_cts;

-- IDE controller
U19: entity work.ide_controller
port map(
	CLK 				=> clk_bus,
	RESET 			=> reset,
	
	PROFIDE_EN 		=> '1',
	NEMOIDE_EN 		=> nemoide_en,

	A 					=> cpu_a_bus,
	DI 				=> cpu_do_bus,
	IORQ_N 			=> cpu_iorq_n,
	MREQ_N 			=> cpu_mreq_n,
	M1_N 				=> cpu_m1_n,
	RD_N 				=> cpu_rd_n,
	WR_N 				=> cpu_wr_n,
	
	CPM				=> cpm,
	ROM14				=> rom14,
	DOS				=> dos_act,
	HDD_OFF			=> hdd_off,

	DO 				=> ide_do_bus,
	ACTIVE			=> hdd_active,
	OE_N 				=> ide_oe_n,

	IDE_A 			=> WA,
	IDE_D 			=> WD,
	IDE_CS_N 		=> WCS_N,
	IDE_RD_N 		=> WRD_N,
	IDE_WR_N 		=> WWR_N,
	IDE_RESET_N 	=> WRESET_N,
	IDE_BUSY 		=> ide_busy
);

-- FDD controller
G_FDD: if ENABLE_FDD generate
U20: entity work.firefly_fdc
port map(
	clk 				=> clk_bus,
	clk_16 			=> clk_16,
	reset 			=> reset,

	a 					=> cpu_a_bus,
	d 					=> cpu_do_bus,
	m1_n 				=> cpu_m1_n,
	wr_n 				=> cpu_wr_n,
	rd_n 				=> cpu_rd_n,
	iorq_n 			=> cpu_iorq_n,

	cs_n 				=> fdd_cs_n,
	csff_n 			=> fdd_cs_pff_n,

	oe_n 				=> fdd_oe_n,
	dout 				=> fdd_do_bus,
	
	FDC_SIDE1 		=> FDC_SIDE_N,
	FDC_RDATA 		=> FDC_RDATA,
	FDC_WPRT 		=> FDC_WPRT,
	FDC_TR00 		=> FDC_TR00,
	FDC_INDEX 		=> FDC_INDEX,
	FDC_WG 			=> FDC_WGATE,
	FDC_WR_DATA 	=> FDC_WDATA,
	FDC_STEP 		=> FDC_STEP,
	FDC_DIR 			=> FDC_DIR,
	FDC_MOTOR 		=> FDC_MOTOR,
	FDC_DS 			=> FDC_DRIVE
);
end generate G_FDD;

G_NOFDD: if not(ENABLE_FDD) generate
	FDC_DRIVE      <= "ZZ";
	FDC_MOTOR      <= 'Z';
	FDC_DIR        <= 'Z';
	FDC_STEP       <= 'Z';
	FDC_WDATA      <= 'Z';
	FDC_WGATE      <= 'Z';
	FDC_SIDE_N     <= 'Z';
	fdd_oe_n       <= '1';
end generate G_NOFDD;

-- Audio mixer
U21: entity work.audio_mixer
port map(
	clk 				=> clk_bus,

	mute 				=> loader_act or kb_pause or sound_off,
	mode 				=> kb_psg_mix,

	speaker 			=> speaker,
	tape_in 			=> TAPE_IN,

	ssg0_a 			=> ssg_cn0_a,
	ssg0_b 			=> ssg_cn0_b,
	ssg0_c 			=> ssg_cn0_c,

	ssg1_a 			=> ssg_cn1_a,
	ssg1_b 			=> ssg_cn1_b,
	ssg1_c 			=> ssg_cn1_c,

	covox_a 			=> covox_a,
	covox_b 			=> covox_b,
	covox_c 			=> covox_c,
	covox_d 			=> covox_d,
	covox_fb 		=> covox_fb,
	
	saa_l 			=> saa_out_l,
	saa_r 			=> saa_out_r,
	
	gs_l 				=> gs_l,
	gs_r 				=> gs_r,
	
	fm_l 				=> ssg_cn0_fm,
	fm_r 				=> ssg_cn1_fm,
	fm_ena 			=> ssg_fm_ena,
	
	adc_l				=> adc_l(23 downto 8),
	adc_r				=> adc_r(23 downto 8),
	
	esp_l				=> esp_l,
	esp_r				=> esp_r,
	
	audio_l 			=> audio_mix_l,
	audio_r 			=> audio_mix_r
);

-- General Sound
G_GS: if ENABLE_GS generate
U22: entity work.gs_top
port map(
	clk_bus 			=> clk_bus, -- 28/24
	ce 				=> ena_div2, -- 14 n
	ds80				=> ds80,

	reset 			=> areset or kb_gs_reset or loader_act or mcu_busy,
	areset 			=> areset,
	
	a 					=> cpu_a_bus,
	di 				=> cpu_do_bus,
	mreq_n 			=> cpu_mreq_n,
	iorq_n 			=> cpu_iorq_n,
	m1_n 				=> cpu_m1_n,
	rd_n 				=> cpu_rd_n,
	wr_n 				=> cpu_wr_n,
	
	oe 				=> gs_oe,
	do_bus 			=> gs_do_bus,

	ram_a				=> gs_mem_a,
	ram_di			=> gs_mem_di,
	ram_do			=> gs_mem_do,
	ram_rd_n			=> gs_mem_rd_n,
	ram_wr_n			=> gs_mem_wr_n,
	ram_rfsh_n  	=> gs_mem_rfsh_n,
	
	out_l 			=> gs_l,
	out_r 			=> gs_r
	
);
end generate G_GS;

G_NOGS: if not(ENABLE_GS) generate
	gs_oe          <= '0';
	gs_mem_rd_n    <= '1';
	gs_mem_wr_n    <= '1';
	gs_mem_rfsh_n  <= '1';
end generate G_NOGS;

-------------------------------------------------------------------------------
-- Global signals

reset <= areset or kb_reset or loader_act or mcu_busy or rom_bank_reset; -- hot reset

hia <= cpu_a_bus(15 downto 8); -- high cpu address
loa <= cpu_a_bus(7 downto 0);  -- low cpu address
io_rd <= '1' when cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' else '0';

-- CPU reset
process (clk_bus)
begin
	if rising_edge(clk_bus) then 
		cpu_reset_n <= not(reset); 
	end if;
end process;

-- int ack signal
cpu_inta_n <= cpu_iorq_n or cpu_m1_n;	-- INTA

-- int signal
cpu_int_n <= vid_int_n and serial_ms_int_n;

-- nmi signal
cpu_nmi_n <= mapcond when kb_nmi = '1' and divmmc_en = '1' else 
	'0' when divmmc_en = '0' and kb_nmi = '1' and ((cpu_m1_n = '0' and cpu_mreq_n = '0' and hia(15 downto 14) /= "00") or DS80 = '1') else 
	'1';

-- wait always disabled
-- actual wait signal is controlled by ena_cpu
cpu_wait_n <= '1';

-- cpu wait condition
cpu_wait <= '1' when zc_busy = '1' or 
							ide_busy = '1' or 
							kb_pause = '1' or  
							(kb_screen_mode = "01" and memory_contention = '1' and automap = '0' and DS80 = '0') 
							else '0';

-------------------------------------------------------------------------------
-- SD Card

SD_CS_N	<= zc_cs_n;
SD_CLK 	<= zc_sclk when zc_cs_n = '0' else '1';
SD_DI 	<= zc_mosi when zc_cs_n = '0' else '1';

-------------------------------------------------------------------------------
-- Ports

-- #FD port correction
-- IN A, (#FD) - read a value from a hardware port (opcode DB FD)
-- OUT (#FD), A - writes the value of the second operand into the port given by the first operand (opcode D3 FD)
fd_sel <= '0' when (
	cpu_do_bus = x"DB" or cpu_do_bus = x"D3" or 
	cpu_di_bus = x"DB" or cpu_di_bus = x"D3") else '1'; 

process(fd_sel, reset, cpu_m1_n)
begin
	if reset='1' then
		fd_port <= '1';
	elsif rising_edge(cpu_m1_n) then -- latch opcode after M1 cycle
		fd_port <= fd_sel;
	end if;
end process;

-- Config PORT X"008B"
cs_008b <='1' when cpu_a_bus(15 downto 0)=X"008B" and cpu_iorq_n='0' and cpu_m1_n = '1' and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0')) else '0';

rom0 <= port_008b_reg(0);											-- 0 - ROM64Kb PAGE bit 0 Change
rom1 <= port_008b_reg(1);											-- 1 - ROM64Kb PAGE bit 1 Change
rom2 <= port_008b_reg(2);											-- 2 - ROM64Kb PAGE bit 2 Change
rom3 <= port_008b_reg(3);											-- 3 - ROM64Kb PAGE bit 3 Change
rom4 <= port_008b_reg(4); 											-- 4 - ROM64Kb PAGE bit 4 Change
rom5 <= port_008b_reg(5);										 	-- 5 - ROM64Kb PAGE bit 5 Change
onrom <= port_008b_reg(6);											-- 6 - Forced activation of the signal "DOS"
unlock_128 <= port_008b_reg(7);									-- 7 - Unlock 128 ROM page for DOS

-- Config PORT X"018B"
cs_018b <='1' when cpu_a_bus(15 downto 0)=X"018B" and cpu_iorq_n='0' and cpu_m1_n = '1' and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0')) else '0';

ram0 <= port_018b_reg(0);											-- 0 - RAM PAGE bit 0
ram1 <= port_018b_reg(1); 											-- 1 - RAM PAGE bit 1
ram2 <= port_018b_reg(2);										 	-- 2 - RAM PAGE bit 2
ram3 <= port_018b_reg(3);											-- 3 - RAM PAGE bit 3
ram4 <= port_018b_reg(4);											-- 3 - RAM PAGE bit 4
ram5 <= port_018b_reg(5);											-- 3 - RAM PAGE bit 5
ram6 <= port_018b_reg(6);											-- 3 - RAM PAGE bit 6
ram7 <= port_018b_reg(7);											-- 3 - RAM PAGE bit 7

-- Config PORT X"028B"
cs_028b <='1' when cpu_a_bus(15 downto 0)=X"028B" and cpu_iorq_n='0' and cpu_m1_n = '1' else '0';

hdd_off <= port_028b_reg(0);										-- 0 	- HDD_off
hdd_type <= port_028b_reg(1);										-- 1 	- HDD type Profi/Nemo
turbo_fdc_off <= not port_028b_reg(2) and kb_turbofdc;	-- 2 	- TURBO_FDC_off
fdc_swap <= port_028b_reg(3) or kb_swap_fdd;					-- 3 	- Floppy Disk Drive Selector Change
sound_off <= port_028b_reg(4);									-- 4 	- Sound_off
turbo_mode <= port_028b_reg(6 downto 5);				      -- 6,5 - Turbo Mode Selector 
lock_dffd <= port_028b_reg(7);								 	-- 7 	- Lock port DFFD

ext_rom_bank_pq <= ext_rom_bank when rom0 = '0' else "01";	-- ROMBANK ALT

rom14 <= port_7ffd_reg(4); -- rom bank
cpm 	<= port_dffd_reg(5); -- 1 - блокирует работу контроллера из ПЗУ TR-DOS и включает порты на доступ из ОЗУ (ROM14=0); При ROM14=1 - мод. доступ к расширен. периферии
worom <= port_dffd_reg(4); -- 1 - отключает блокировку порта 7ffd и выключает ПЗУ, помещая на его место ОЗУ из seg 00
ds80 	<= port_dffd_reg(7); -- 0 = seg05 spectrum bitmap, 1 = profi bitmap seg06 & seg 3a & seg 04 & seg 38
scr 	<= port_dffd_reg(6); -- памяти CPU на место seg 02, при этом бит D3 CMR0 должен быть в 1 (#8000-#BFFF)
sco 	<= port_dffd_reg(3); -- Выбор положения окна проецирования сегментов:
									-- 0 - окно номер 1 (#C000-#FFFF)
									-- 1 - окно номер 2 (#4000-#7FFF)

-- OCH: change decoding of #FE port when Nemo enabled
cs_xxfe <= '1' when (cpu_iorq_n = '0' and loa(0) = '0' and nemoide_en = '0') or 
						  (cpu_iorq_n = '0' and loa(6 downto 0) = "1111110" and nemoide_en = '1') else '0';
cs_xx7e <= '1' when cs_xxfe = '1' and loa(7) = '0' else '0';
cs_eff7 <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"EFF7" else '0';
cs_fffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"FFFD" and fd_port = '1' else '0';
cs_dffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"DFFD" and fd_port = '1' and lock_dffd = '0' else '0';
cs_7ffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"7FFD" and fd_port = '1' else '0';
cs_1ffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"1FFD" and fd_port = '1' else '0';
-- OCH: change decoding of #FD port when Nemo enabled
cs_xxfd <= '1' when (cpu_iorq_n = '0' and cpu_m1_n = '1' and hia(15) = '0' and loa(1) = '0' and nemoide_en = '0') or
						  (cpu_iorq_n = '0' and cpu_m1_n = '1' and hia(15) = '0' and loa = x"FD" and nemoide_en = '1') else '0';						  


-- RTC AS reg (address)
cs_rtc_as <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and
							((loa = x"FF" or loa = x"BF") and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0'))) --  
				     else '0';
-- RTC DS reg (data)
cs_rtc_ds <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and 
							((loa = x"DF" or loa = x"9F") and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0'))) --  
				     else '0';
					  
-- port #7E - write by cpu_wr_n front
port_xxfe_reg <= cpu_do_bus when cs_xxfe = '1' and (cpu_wr_n'event and cpu_wr_n = '1');

--  Profi FDD

-- 1F 3F 5F 7F FF -- spectrum bdi
-- 1F 3F 5F 7F BF -- основная периферия в короткой адресации
-- 83 A3 C3 E3 3F -- расш периферия Profi 2+, 3+

-- fdd BDI RQ port FF (3F,BF)
fdd_cs_pff_n <= '0' when ((loa=x"FF" and cpu_iorq_n='0') and ((cpm='0' and dos_act='1' and rom14='1'))) or					  -- FF
								 ((loa=x"BF" and cpu_iorq_n='0') and ((cpm='1' and dos_act='0' and rom14='0'))) or 					  -- BF
								 ((loa=x"3F" and cpu_iorq_n='0') and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0')))    -- 3F								 
								 else '1';

-- fdd control ports 1F,3F,5F,7F (83,A3,C3,E3)
fdd_cs_n <= '0' when ((loa=x"1F" or loa=x"3F" or loa=x"5F" or loa=x"7F") and cpu_iorq_n='0' and cpm='0' and dos_act='1' and rom14='1') or -- bdi
							((loa=x"1F" or loa=x"3F" or loa=x"5F" or loa=x"7F") and cpu_iorq_n='0' and cpm='1' and dos_act='0' and rom14='0') or -- main
							((loa=x"83" or loa=x"A3" or loa=x"C3" or loa=x"E3") and cpu_iorq_n='0' and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0'))) -- ext
							else '1';
-- Ports
process (reset, areset, clk_bus, ena_cpu, cpu_a_bus, dos_act, cs_xxfe, cs_eff7, cs_7ffd, cs_xxfd, port_7ffd_reg, port_1ffd_reg, cpu_mreq_n, cpu_m1_n, cpu_wr_n, cpu_do_bus, fd_port, cs_008b, kb_turbo, kb_turbo_old)
begin
	if reset = '1' then
		port_eff7_reg <= (others => '0');
		port_7ffd_reg <= (others => '0');
		port_1ffd_reg <= (others => '0');
		port_dffd_reg <= (others => '0');
		port_xxC7_reg <= (others => '0');
		port_xx87_reg <= (others => '0');
		port_xxA7_reg <= (others => '0');
		port_xxE7_reg <= (others => '0');
		port_xx67_reg <= (others => '0');
		port_008b_reg <= (others => '0');
		port_018b_reg <= (others => '0');
		port_028b_reg <= (others => '0');
		dos_act <= '1';
		kb_turbo_old <= "00";
		port_e3_reg(5 downto 0) <= (others => '0');
		port_e3_reg(7) <= '0';
		
	elsif rising_edge(clk_bus) then
			-- #xxE3
			if (cpu_iorq_n = '0' and cpu_wr_n = '0' and loa = x"E3" and cpm = '0' and divmmc_en = '1') then	
				port_e3_reg <=cpu_do_bus(7) & (port_e3_reg(6) or cpu_do_bus(6)) & cpu_do_bus(5 downto 0);
			end if;		
			
			-- #EFF7
			if cs_eff7 = '1' and cpu_wr_n = '0' then 
				port_eff7_reg <= cpu_do_bus; 
			end if;
			
			-- profi RTC #BF / #FF
			if cs_rtc_as = '1' and cpu_wr_n = '0' then 
				mc146818_a_bus <= cpu_do_bus(7 downto 0); 
			end if;

			-- #DFFD
			if cs_dffd = '1' and cpu_wr_n = '0' then
				port_dffd_reg <= cpu_do_bus;
			end if;
			
			-- #7FFD
			if cs_xxfd = '1' and cpu_wr_n = '0' and (port_7ffd_reg(5) = '0' or port_dffd_reg(4)='1') then -- short #FD
			   port_7ffd_reg(5 downto 0) <= cpu_do_bus(5 downto 0);
			end if;
			
			if cs_7ffd = '1' and cpu_wr_n = '0' and (port_7ffd_reg(5) = '0' or port_dffd_reg(4)='1') then -- full #7FFD
			   port_7ffd_reg(7 downto 6) <= cpu_do_bus(7 downto 6);
			end if;
			
			-- #1FFD
			if cs_1ffd = '1' and cpu_wr_n = '0' then
			   port_1ffd_reg <= cpu_do_bus;
			end if;

			-- #xxC7
			if cs_xxC7 = '1' and cpu_wr_n = '0' then
				port_xxC7_reg <= cpu_do_bus;
			end if;

			-- #xx87
			if cs_xx87 = '1' and cpu_wr_n = '0' then
				port_xx87_reg <= cpu_do_bus;
			end if;

			-- #xxA7
			if cs_xxA7 = '1' and cpu_wr_n = '0' then
				port_xxA7_reg <= cpu_do_bus;
			end if;

			-- #xxE7
			if cs_xxE7 = '1' and cpu_wr_n = '0' then
				port_xxE7_reg <= cpu_do_bus;
			end if;

			-- #xx67
			if cs_xx67 = '1' and cpu_wr_n = '0' then
				port_xx67_reg <= cpu_do_bus;
			end if;
			
			-- #008B
			if cs_008b = '1' and cpu_wr_n='0' then
				port_008b_reg <= cpu_do_bus;
			end if;
			
			-- #018B
			if cs_018b = '1' and cpu_wr_n='0' then
				port_018b_reg <= cpu_do_bus;
			end if;

			-- #028B
			if cs_028b = '1' and cpu_wr_n='0' then
				port_028b_reg <= cpu_do_bus;
			elsif kb_turbo /= kb_turbo_old then
				port_028b_reg (6 downto 5) <= kb_turbo (1 downto 0);
				kb_turbo_old <= kb_turbo;
			end if;
			
			-- TR-DOS FLAG
			if (((cpu_m1_n = '0' and cpu_mreq_n = '0' and hia = X"3D" and (rom14 = '1' or unlock_128 = '1')) or 
			(cpu_nmi_n = '0'  and DS80 = '0')) and port_dffd_reg(4) = '0') or (onrom = '1') then dos_act <= '1';
			elsif ((cpu_m1_n = '0' and cpu_mreq_n = '0' and hia(15 downto 14) /= "00") or (port_dffd_reg(4) = '1')) then dos_act <= '0'; end if;
				
	end if;
end process;

-------------------------------------------------------------------------------
-- Audio 

speaker <= port_xxfe_reg(4);
TAPE_OUT <= port_xxfe_reg(3);
				
-- SAA1099
saa_wr_n <= '0' when (cpu_iorq_n = '0' and cpu_wr_n = '0' and loa = x"FF" and dos_act = '0') else '1';

---------------------------------------------------------------------------------
-- Port I/O

mc146818_wr <= '1' when (cs_rtc_ds = '1' and cpu_iorq_n = '0' and cpu_wr_n = '0' and cpu_m1_n = '1') else '0';


-- SPI Z-controller + DivMMC 
zc_spi_start <= '1' when (loa = x"57" or (loa = x"EB" and cpm = '0' and divmmc_en = '1')) and cpu_iorq_n='0' and cpu_m1_n='1' and loader_act='0' else '0';
zc_wr_en <= '1' when zc_spi_start = '1' and cpu_wr_n='0' else '0';
zc_rd_en <= '1' when zc_spi_start = '1' and cpu_rd_n='0' else '0';
port77_wr <= '1' when (loa = x"77" or (loa = x"E7" and divmmc_en = '1')) and cpu_iorq_n='0' and cpu_m1_n='1' and cpu_wr_n='0' and loader_act='0' else '0';

process (port77_wr, loader_act, reset, clk_bus)
	begin
		if loader_act='1' or reset='1' then
			zc_cs_n <= '1';
		elsif clk_bus'event and clk_bus='1' then
			if port77_wr='1' then
				if loa = x"E7" then
					zc_cs_n <= cpu_do_bus(0);
				else
					zc_cs_n <= cpu_do_bus(1);
				end if;
			end if;
		end if;
end process;

U_ZC_SPI: entity work.zc_spi
port map(
	clk_sys       => clk_bus, -- 28/24
	ena           => '1', -- 28
	tx            => zc_wr_en,
	rx            => zc_rd_en,
	din           => cpu_do_bus,
	dout          => zc_do_bus,
	spi_clk       => zc_sclk,
	spi_di        => SD_DO,
	spi_do        => zc_mosi,
	spi_wait      => zc_busy
);

------------------------ divmmc-----------------------------
-- Engineer:   Mario Prato
-- 11.07.2013:OCH: adapted by me
-- i take this implementation to correctly and easy make nmi 

process (reset, divmmc_en, cpu_a_bus)
begin
	if reset = '1' or divmmc_en = '0' then 
		mapterm <= '0';
		map3DXX <= '0';
		map1F00 <= '1';
	else
		 if cpu_a_bus(15 downto 0) = x"0000"   or 
			 cpu_a_bus(15 downto 0) = x"0008"   or 
			 cpu_a_bus(15 downto 0) = x"0038"   or 
			 cpu_a_bus(15 downto 0) = x"0066"   or 
			 cpu_a_bus(15 downto 0) = x"04c6"   or 
			 cpu_a_bus(15 downto 0) = x"0562" then 
			mapterm <= '1';
		else 
			mapterm <= '0';
		end if;	

		-- mappa 3D00 - 3DFF
		if hia(15 downto 8) = "00111101" then 
			map3DXX <= '1'; 
		else 
			map3DXX <= '0';
		end if; 

		-- 1ff8 - 1fff
		if cpu_a_bus(15 downto 3) =   "0001111111111" then 
			map1F00 <= '0';
		else 
			map1F00 <= '1';
		end if; 
	end if;
end process;

process(reset, divmmc_en, cpu_mreq_n, cpu_m1_n, mapcond, mapterm, map3DXX, map1F00, automap)
begin
	if reset = '1' or divmmc_en = '0' then 
		mapcond <= '0';
		automap <= '0';
   elsif falling_edge(cpu_mreq_n) then
		   if cpu_m1_n = '0' then
				 mapcond <= (mapterm or map3DXX or (mapcond and map1F00)) and divmmc_en;
				 automap <= (mapcond or map3DXX) and divmmc_en;
		  end if;
	end if;	  
end process; 

-------------------------------------------------------------------------------
-- CPU Data bus

process (selector, cpu_a_bus, gx0, serial_ms_do_bus, ram_do_bus, mc146818_do_bus, kb_do_bus, zc_do_bus, ts_do_bus, port_7ffd_reg, port_dffd_reg,
			vid_attr, port_eff7_reg, joy_bus, ms_z, ms_b, ms_x, ms_y, port_xxC7_reg, port_008b_reg,
			port_018b_reg, port_028b_reg, gs_do_bus, ide_do_bus, fdd_do_bus, TAPE_IN, 
			zifi_do_bus, zxuno_uart_do_bus, zxuno_addr_to_cpu)
begin
	case selector is
		when x"00" => cpu_di_bus <= ram_do_bus;
		when x"01" => cpu_di_bus <= mc146818_do_bus;
		when x"02" => cpu_di_bus <= GX0 & not(TAPE_IN) & kb_do_bus;
		when x"03" => cpu_di_bus <= zc_do_bus;
		when x"04" => cpu_di_bus <= "11111100";	
		when x"05" => cpu_di_bus <= joy_bus;
		when x"06" => cpu_di_bus <= ts_do_bus;
		when x"08" => cpu_di_bus <= port_dffd_reg;
		when x"09" => cpu_di_bus <= port_7ffd_reg;
		when x"0A" => cpu_di_bus <= ms_z(3 downto 0) & '1' & not(ms_b(2)) & not(ms_b(0)) & not(ms_b(1)); -- D0=right, D1 = left, D2 = middle, D3 = fourth, D4..D7 - wheel
		when x"0B" => cpu_di_bus <= ms_x;
		when x"0C" => cpu_di_bus <= ms_y;
		when x"0D" => cpu_di_bus <= x"FF"; -- zxuno uart 2 stub
		when x"0E" => cpu_di_bus <= serial_ms_do_bus;
		when x"0F" => cpu_di_bus <= zxuno_addr_to_cpu;
		when x"10" => cpu_di_bus <= zxuno_uart_do_bus;
		when x"11" => cpu_di_bus <= "0000" & port_xxC7_reg(3) & port_xxC7_reg(2) & '1' & '0';
		when x"12" => cpu_di_bus <= x"FF"; -- flash do bus stub
		when x"13" => cpu_di_bus <= port_008b_reg;
		when x"14" => cpu_di_bus <= port_018b_reg;
		when x"15" => cpu_di_bus <= port_028b_reg;
		when x"16" => cpu_di_bus <= zifi_do_bus;
		when x"17" => cpu_di_bus <= vid_attr;
		when x"18" => cpu_di_bus <= fdd_do_bus;
		when x"19" => cpu_di_bus <= ide_do_bus;
		when x"1A" => cpu_di_bus <= gs_do_bus;
		when others => cpu_di_bus <= (others => '1');
	end case;
end process;

selector <= 
	x"00" when (ram_oe_n = '0') else -- ram / rom
	x"01" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cs_rtc_ds = '1') else -- rtc
	x"02" when (cs_xxfe = '1' and cpu_rd_n = '0') else 	-- Keyboard, port #FE
 	x"03" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and (loa = x"57" or (loa = x"EB" and cpm = '0' and divmmc_en = '1')) ) else 	-- Z-Controller + DivMMC
	x"04" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and loa = x"77") else 	-- Z-Controller
	x"05" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and loa = x"1F" and dos_act = '0' and cpm = '0' and joy_mode = "000") else -- Joystick, port #1F
	x"06" when (cs_fffd = '1' and cpu_rd_n = '0' and cpu_a_bus = x"FFFD") else 	-- TurboSound
	x"08" when (cs_dffd = '1' and cpu_rd_n = '0' and cpu_a_bus = x"DFFD") else		-- port #DFFD
	x"09" when (cs_7ffd = '1' and cpu_rd_n = '0' and cpu_a_bus = x"7FFD") else		-- port #7FFD
	x"0A" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = x"FADF" and cpm='0') else	-- Mouse z,b
	x"0B" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = x"FBDF" and cpm='0') else	-- Mouse x
	x"0C" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = x"FFDF" and cpm='0') else	-- Mouse y 
	x"0E" when (serial_ms_oe_n = '0' and ds80 = '1') else -- Serial mouse - конфликт с GS
	x"0F" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and zxuno_addr_oe_n = '0') else -- ZX UNO Register
	x"10" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and zxuno_uart_oe_n = '0') else -- ZX UNO UART
	x"11" when (cs_xxC7 = '1' and cpu_rd_n = '0') else
	x"12" when (cs_xxE7 = '1' and cpu_rd_n = '0') else
	x"13" when (cs_008b = '1' and cpu_rd_n = '0') else										-- port #008B
	x"14" when (cs_018b = '1' and cpu_rd_n = '0') else										-- port #018B
	x"15" when (cs_028b = '1' and cpu_rd_n = '0') else										-- port #028B
	x"16" when zifi_oe_n = '0' and cpu_iorq_n = '0' and cpu_rd_n = '0' else  		-- zifi
	x"17" when (vid_pff_cs = '1' and cpu_iorq_n = '0' and cpu_rd_n = '0' and loa = x"FF") and dos_act='0' and cpm = '0' and ds80 = '0' else -- Port FF select
	x"18" when (fdd_oe_n = '0' and cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1') else 		-- fdd
	x"19" when (ide_oe_n = '0' and cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1') else 		-- ide	
	x"1A" when (gs_oe = '1' and cpu_iorq_n = '0' and cpu_rd_n = '0' and ds80 = '0') else 				-- gs
	(others => '1');

ext_rom_bank <= kb_rom_bank;

-- trigger a reset signal on rom bank switch
process (CLK_BUS)
begin
	if rising_edge(CLK_BUS) then
		rom_bank_reset <= '0';
		if (prev_kb_rom_bank /= kb_rom_bank) then
			rom_bank_reset <= '1';
			prev_kb_rom_bank <= kb_rom_bank;
		end if;
	end if;
end process;

vid_scandoubler_enable <= not(kb_video);
divmmc_en   <= kb_divmmc_en;
nemoide_en  <= kb_nemoide_en;

-- midi clk and reset
MIDI_RESET_N <= not reset;

-- video out
RGB_CLK      <= clk_rgb;
VGA_CLK      <= clk_vga;
RGB          <= vid_rgb_osd;
RGB_HS       <= vid_hsync;
RGB_VS       <= vid_vsync;
RGB_BLANK    <= vid_blank;
RGB_FRAME    <= vid_lock;
RGB_PIXEL    <= vid_active;
SCANDOUBLER  <= vid_scandoubler_enable;
VMODE        <= ds80 & kb_screen_mode & kb_vsync;

-- audio out
AUDIO_L      <= audio_mix_l;
AUDIO_R      <= audio_mix_r;
ADC_CLK      <= clk_adc;
BEEPER       <= speaker;

end Behavioral;

