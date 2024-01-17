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
-- FPGA Profi (Karabas Pro) core for Karabas-Go
--
-- @author Andy Karpov <https://github.com/andykarpov>
-- @author Oleh Starychenko <https://github.com/solegstar>
-- @author Oleh Chastukhin <https://github.com/Caasper911>
-- @author Alexander Sharihin <https://github.com/nihirash>
-- @author Doctor Max <https://github.com/drmax-gc>
-- EU, 2024

-- TODO:
-- 1. serial mouse test
-- 2. NMI button (hotkey + button)
-- 3. UNO UART, ZIFI, CTS
-- 4. Fix OSD Menu+ESC (don't send ESC 200ms after release)
-- 5. OSD popups test (implement on MCU side)
-- 6. GS
-- 7. Turbo 56 MHz (system clock 56 or 112 ?)
------------------------------------------------------------------------------------------------------------------

library IEEE; 
use IEEE.std_logic_1164.all; 
use IEEE.std_logic_unsigned.all;
use IEEE.numeric_std.all; 

library unisim;
use unisim.vcomponents.all;

entity karabas_go is
    Port ( CLK_50MHZ : in  STD_LOGIC;
           TAPE_IN : in  STD_LOGIC;
           TAPE_OUT : out  STD_LOGIC;
           BEEPER : out  STD_LOGIC;
           DAC_LRCK : out  STD_LOGIC;
           DAC_DAT : out  STD_LOGIC;
           DAC_BCK : out  STD_LOGIC;
           DAC_MUTE : out  STD_LOGIC;
           ESP_RESET_N : out  STD_LOGIC;
           ESP_BOOT_N : out  STD_LOGIC;
           UART_RX : inout  STD_LOGIC;
           UART_TX : inout  STD_LOGIC;
           UART_CTS : out  STD_LOGIC;
           WA : out  STD_LOGIC_VECTOR (2 downto 0);
           WCS_N : out  STD_LOGIC_VECTOR(1 downto 0);
           WRD_N : out  STD_LOGIC;
           WWR_N : out  STD_LOGIC;
           WRESET_N : out  STD_LOGIC;
           WD : inout  STD_LOGIC_VECTOR (15 downto 0);
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
           SD_CS_N : out  STD_LOGIC;
           SD_DI : inout  STD_LOGIC;
           SD_DO : inout  STD_LOGIC;
           SD_CLK : out  STD_LOGIC;
           SD_DET_N : in  STD_LOGIC;

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
           FDC_SIDE_N : out  STD_LOGIC;

           FT_SPI_CS_N : out  STD_LOGIC;
           FT_SPI_SCK : out  STD_LOGIC;
           FT_SPI_MISO : inout  STD_LOGIC;
           FT_SPI_MOSI : inout  STD_LOGIC;
           FT_INT_N : inout  STD_LOGIC;
           FT_CLK : inout  STD_LOGIC;
           FT_OE_N : out  STD_LOGIC;
           VGA_R : out  STD_LOGIC_VECTOR (7 downto 0);
           VGA_G : out  STD_LOGIC_VECTOR (7 downto 0);
           VGA_B : out  STD_LOGIC_VECTOR (7 downto 0);
           VGA_HS : out  STD_LOGIC;
           VGA_VS : out  STD_LOGIC;
           V_CLK : out  STD_LOGIC;
           MCU_CS_N : in  STD_LOGIC;
           MCU_SCK : in  STD_LOGIC;
           MCU_MOSI : in  STD_LOGIC;
           MCU_MISO : out  STD_LOGIC);
end karabas_go;

architecture Behavioral of karabas_go is

-- CPU
signal cpu_reset_n	: std_logic;
signal cpu_a_bus		: std_logic_vector(15 downto 0);
signal cpu_do_bus		: std_logic_vector(7 downto 0);
signal cpu_di_bus		: std_logic_vector(7 downto 0);
signal cpu_mreq_n		: std_logic;
signal cpu_iorq_n		: std_logic;
signal cpu_wr_n		: std_logic;
signal cpu_rd_n		: std_logic;
signal cpu_int_n		: std_logic;
signal cpu_inta_n		: std_logic;
signal cpu_m1_n		: std_logic;
signal cpu_rfsh_n		: std_logic;
signal cpu_mult		: std_logic_vector(1 downto 0);
signal cpu_mem_wr		: std_logic;
signal cpu_mem_rd		: std_logic;
signal cpu_nmi_n		: std_logic;
signal cpu_wait_n 	: std_logic := '1';
signal cpu_wait 		: std_logic;

-- Port
signal port_xxfe_reg	: std_logic_vector(7 downto 0) := "00000000";
signal port_7ffd_reg	: std_logic_vector(7 downto 0) := "00000000";
signal port_1ffd_reg	: std_logic_vector(7 downto 0) := "00000000";
signal port_dffd_reg : std_logic_vector(7 downto 0) := "00000000";
signal port_xx7e_reg : std_logic_vector(7 downto 0) := "00000000";
signal port_xx7e_a   : std_logic_vector(15 downto 8) := "00000000";
signal port_xx7e_aprev   : std_logic_vector(15 downto 8) := "00000000";
signal port_008b_reg	: std_logic_vector(7 downto 0) := "00000000";
signal port_018b_reg	: std_logic_vector(7 downto 0) := "00000000";
signal port_028b_reg	: std_logic_vector(7 downto 0) := "00000000";

-------------8B_PORT------------------
signal rom0				: std_logic;
signal rom1				: std_logic;
signal rom2				: std_logic;
signal rom3				: std_logic;
signal rom4				: std_logic;
signal rom5				: std_logic;
signal ram0				: std_logic;
signal ram1				: std_logic;
signal ram2				: std_logic;
signal ram3				: std_logic;
signal ram4				: std_logic;
signal ram5				: std_logic;
signal ram6				: std_logic;
signal ram7				: std_logic;
signal onrom			: std_logic;
signal unlock_128		: std_logic;
signal turbo_mode		: std_logic_vector(1 downto 0) := "00";
signal lock_dffd		: std_logic;
signal sound_off		: std_logic;
signal hdd_type		: std_logic;
signal fdc_swap		: std_logic;
signal turbo_fdc_off	: std_logic;
signal hdd_off			: std_logic;
signal hdd_active		: std_logic;

-- Keyboard
signal kb_do_bus		: std_logic_vector(5 downto 0);
signal kb_reset 		: std_logic := '0';
signal kb_nmi 		: std_logic := '0';
signal kb_turbo 		: std_logic_vector(1 downto 0) := "00";
signal kb_turbo_old	: std_logic_vector(1 downto 0) := "00";
signal kb_pause 		: std_logic := '0';
signal joy_type 		: std_logic := '0';
signal joy_mode 		: std_logic_vector(2 downto 0) := "000";
signal kb_loaded 		: std_logic := '0';
signal kb_screen_mode: std_logic_vector(1 downto 0) := "00";

-- Joy
signal joy_bus 		: std_logic_vector(7 downto 0) := "00000000";

-- Mouse
signal ms_x				: std_logic_vector(7 downto 0);
signal ms_y				: std_logic_vector(7 downto 0);
signal ms_z				: std_logic_vector(3 downto 0);
signal ms_b				: std_logic_vector(2 downto 0);

signal hid_ms_x 		: std_logic_vector(7 downto 0);
signal hid_ms_y		: std_logic_vector(7 downto 0);
signal hid_ms_z		: std_logic_vector(3 downto 0);
signal hid_ms_b		: std_logic_vector(2 downto 0);
signal hid_ms_upd 	: std_logic;
signal ms_present 	: std_logic := '0';

-- Video
signal vid_a_bus		: std_logic_vector(13 downto 0);
signal vid_di_bus		: std_logic_vector(7 downto 0);
signal vid_do_bus 	: std_logic_vector(7 downto 0);
signal vid_rd 			: std_logic := '0';

signal vid_hsync		: std_logic;
signal vid_vsync		: std_logic;
signal vid_int			: std_logic;
signal vid_pff_cs		: std_logic;
signal vid_attr		: std_logic_vector(7 downto 0);
signal vid_rgb			: std_logic_vector(8 downto 0);
signal vid_rgb_osd 	: std_logic_vector(8 downto 0);
signal vid_invert 	: std_logic;
signal vid_hcnt 		: std_logic_vector(9 downto 0);
signal vid_vcnt 		: std_logic_vector(8 downto 0);
signal vid_ispaper   : std_logic;
signal vid_scandoubler_enable : std_logic := '1';
signal blink 			: std_logic;

-- OSD overlay
signal osd_command 	: std_logic_vector(15 downto 0);

-- SOFT switches command
signal softsw_command: std_logic_vector(15 downto 0);

-- loader
signal loader_act		: std_logic := '0';
signal loader_ram_do	: std_logic_vector(7 downto 0);
signal loader_ram_a	: std_logic_vector(31 downto 0);
signal loader_ram_wr : std_logic := '0';

-- Z-Controller
signal zc_do_bus		: std_logic_vector(7 downto 0);
signal zc_spi_start	: std_logic;
signal zc_wr_en		: std_logic;
signal port77_wr		: std_logic;

signal zc_cs_n			: std_logic;
signal zc_sclk			: std_logic;
signal zc_mosi			: std_logic;
signal zc_miso			: std_logic;

signal nemoide_en 		: std_logic;

--- DivMMC
signal divmmc_en		: std_logic;
signal automap			: std_logic;
--signal detect			: std_logic;
signal port_e3_reg   : std_logic_vector(7 downto 0);
signal mapterm 		: std_logic;
signal map3DXX 		: std_logic; 
signal map1F00 		: std_logic;
signal mapcond 		: std_logic;


-- MC146818A
signal mc146818_wr		: std_logic;
signal mc146818_rd		: std_logic;
signal mc146818_a_bus	: std_logic_vector(7 downto 0);
signal mc146818_do_bus	: std_logic_vector(7 downto 0);
signal mc146818_busy		: std_logic;
signal port_eff7_reg		: std_logic_vector(7 downto 0);

-- Port selectors
signal fd_port 		: std_logic;
signal fd_sel 			: std_logic;
signal cs_xxfe 		: std_logic := '0'; 
signal cs_eff7 		: std_logic := '0';
signal cs_7ffd 		: std_logic := '0';
signal cs_1ffd 		: std_logic := '0';
signal cs_dffd 		: std_logic := '0';
signal cs_fffd 		: std_logic := '0';
signal cs_xxfd 		: std_logic := '0';
signal cs_xx7e 		: std_logic := '0';
signal cs_xx87 		: std_logic := '0';
signal cs_xxA7 		: std_logic := '0';
signal cs_xxC7 		: std_logic := '0';
signal cs_xxE7 		: std_logic := '0';
signal cs_xx67 		: std_logic := '0';
signal cs_rtc_ds 		: std_logic := '0';
signal cs_rtc_as 		: std_logic := '0';
signal cs_008b			: std_logic := '0';
signal cs_018b			: std_logic := '0';
signal cs_028b			: std_logic := '0';

-- Profi FDD ports
signal RT_F2_1			:std_logic;
signal RT_F2_2			:std_logic;
signal RT_F2_3			:std_logic;
signal fdd_cs_pff_n	:std_logic;
signal RT_F1_1			:std_logic;
signal RT_F1_2			:std_logic;
signal RT_F1			:std_logic;
signal P0				:std_logic;
signal fdd_cs_n		:std_logic;

-- TurboSound
signal ssg_sel			: std_logic;
signal ssg_cn0_bus	: std_logic_vector(7 downto 0);
signal ssg_cn0_a		: std_logic_vector(7 downto 0);
signal ssg_cn0_b		: std_logic_vector(7 downto 0);
signal ssg_cn0_c		: std_logic_vector(7 downto 0);
signal ssg_cn1_bus	: std_logic_vector(7 downto 0);
signal ssg_cn1_a		: std_logic_vector(7 downto 0);
signal ssg_cn1_b		: std_logic_vector(7 downto 0);
signal ssg_cn1_c		: std_logic_vector(7 downto 0);

-- Covox
signal covox_a			: std_logic_vector(7 downto 0);
signal covox_b			: std_logic_vector(7 downto 0);
signal covox_c			: std_logic_vector(7 downto 0);
signal covox_d			: std_logic_vector(7 downto 0);
signal covox_fb		: std_logic_vector(7 downto 0);

-- Output audio
signal audio_l			: std_logic_vector(15 downto 0);
signal audio_r			: std_logic_vector(15 downto 0);
signal audio_mono		: std_logic_vector(15 downto 0);

-- SAA1099
signal saa_wr_n		: std_logic;
signal saa_out_l		: std_logic_vector(7 downto 0);
signal saa_out_r		: std_logic_vector(7 downto 0);

-- CLOCK
signal clk_bus			: std_logic;
signal clk_16 			: std_logic;
signal clk_8 			: std_logic;

signal ena_div2	: std_logic := '0';
signal ena_div4	: std_logic := '0';
signal ena_div8	: std_logic := '0';
signal ena_div16	: std_logic := '0';
signal ena_cpu 	: std_logic := '0';

-- System
signal reset			: std_logic;
signal areset			: std_logic;
signal dos_act			: std_logic := '1';
signal selector		: std_logic_vector(7 downto 0);
signal mux				: std_logic_vector(3 downto 0);
signal speaker 		: std_logic := '0';
signal ram_ext 		: std_logic_vector(2 downto 0) := "000";
signal ram_do_bus 	: std_logic_vector(7 downto 0);
signal ram_oe_n 		: std_logic := '1';
signal ext_rom_bank  : std_logic_vector(1 downto 0) := "00";
signal ext_rom_bank_pq	: std_logic_vector(1 downto 0) := "00";
signal max_turbo 		: std_logic_vector(1 downto 0) := "11";

signal port_xx87_reg : std_logic_vector(7 downto 0);
signal port_xxA7_reg : std_logic_vector(7 downto 0);
signal port_xxC7_reg : std_logic_vector(7 downto 0);
signal port_xxE7_reg : std_logic_vector(7 downto 0);
signal port_xx67_reg : std_logic_vector(7 downto 0);

-- ZXUNO regs / UART ports
signal zxuno_regrd : std_logic;
signal zxuno_regwr : std_logic;
signal zxuno_addr : std_logic_vector(7 downto 0);
signal zxuno_regaddr_changed : std_logic;
signal zxuno_addr_oe_n : std_logic;
signal zxuno_addr_to_cpu : std_logic_vector(7 downto 0);
signal zxuno_uart_do_bus 	: std_logic_vector(7 downto 0);
signal zxuno_uart_oe_n 		: std_logic;
signal zxuno_uart2_do_bus 	: std_logic_vector(7 downto 0);
signal zxuno_uart2_oe_n 		: std_logic;
signal uart2_tx : std_logic;
signal uart2_rx : std_logic;
signal uart2_cts : std_logic;
signal zxuno_uart_tx : std_logic;
signal zxuno_uart_cts : std_logic;

-- ZIFI UART 
signal zifi_do_bus : std_logic_vector(7 downto 0);
signal zifi_oe_n   : std_logic := '1';
signal zifi_uart_tx : std_logic;
signal zifi_uart_cts : std_logic;
signal zifi_api_enabled : std_logic;

-- serial mouse 
signal serial_ms_do_bus : std_logic_vector(7 downto 0);
signal serial_ms_oe_n : std_logic := '1';
signal serial_ms_int : std_logic := '1';

-- profi special signals
signal cpm 				: std_logic := '0';
signal worom 			: std_logic := '0';
signal ds80 			: std_logic := '0';
signal scr 				: std_logic := '0';
signal sco 				: std_logic := '0';
signal rom14 			: std_logic := '0';
signal gx0 				: std_logic := '0';

-- memory contention
signal count_block 		: std_logic := '0';
signal memory_contention : std_logic := '0';

-- wait signal
signal WAIT_C			:std_logic_vector(1 downto 0);
signal WAIT_IO			:std_logic;
signal WAIT_EN			:std_logic;
signal WAIT_C_STOP	:std_logic;

-- hid
signal hid_kb_status : std_logic_vector(7 downto 0);
signal hid_kb_dat0 : std_logic_vector(7 downto 0);
signal hid_kb_dat1 : std_logic_vector(7 downto 0);
signal hid_kb_dat2 : std_logic_vector(7 downto 0);
signal hid_kb_dat3 : std_logic_vector(7 downto 0);
signal hid_kb_dat4 : std_logic_vector(7 downto 0);
signal hid_kb_dat5 : std_logic_vector(7 downto 0);
signal joy_l : std_logic_vector(11 downto 0);
signal joy_r : std_logic_vector(11 downto 0);
signal joy_usb: std_logic_vector(11 downto 0);

signal kb_vsync : std_logic := '0';
signal kb_joy_type_l : std_logic_vector(2 downto 0) := "000";
signal kb_joy_type_r : std_logic_vector(2 downto 0) := "000";
signal kb_keycode : std_logic_vector(7 downto 0) := x"FF";
signal kb_rom_bank : std_logic_vector(1 downto 0) := "00";
signal prev_kb_rom_bank : std_logic_vector(1 downto 0) := "00";
signal rom_bank_reset : std_logic := '0';
signal kb_turbofdc : std_logic := '0';
signal kb_covox : std_logic := '0';
signal kb_psg_mix : std_logic_vector(1 downto 0) := "00";
signal kb_psg_type : std_logic := '0';
signal kb_video : std_logic := '0';
signal kb_swap_fdd : std_logic := '0';
signal kb_divmmc_en : std_logic := '0';
signal kb_nemoide_en : std_logic := '0';
signal kb_type : std_logic := '0';
signal mcu_busy : std_logic := '1';

signal ide_do_bus : std_logic_vector(7 downto 0);
signal ide_oe_n	: std_logic := '1';

signal fdd_do_bus : std_logic_vector(7 downto 0);
signal fdd_oe_n : std_logic := '1';

begin

U1: entity work.clock
port map(
	CLK => CLK_50MHZ,	
	ARESET => areset,
	
	DS80 => ds80,
	
	CLK_BUS => clk_bus,
	CLK_16 	=> clk_16,
	CLK_8 	=> clk_8,
	
	ENA_DIV2 => ena_div2,
	ENA_DIV4 => ena_div4,
	ENA_DIV8 => ena_div8,
	ENA_DIV16 => ena_div16,
	ENA_CPU => ena_cpu,
	
	TURBO => turbo_mode,
	WAIT_CPU => cpu_wait
	
);

-- Zilog Z80A CPU
U2: entity work.T80a
port map (
	RESET_n			=> cpu_reset_n,
	CLK_n				=> not clk_bus,
	CEN				=> ena_cpu,
	WAIT_n			=> cpu_wait_n,
	INT_n				=> cpu_int_n and serial_ms_int,
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
	A					=> cpu_a_bus,
	DIN				=> cpu_di_bus,
	DOUT				=> cpu_do_bus
);

-- memory manager
U3: entity work.memory 
port map ( 
	CLK_BUS 			=> clk_bus,
	ENA_CPU 			=> ena_cpu,

	-- cpu signals
	A 					=> cpu_a_bus,
	D 					=> cpu_do_bus,
	N_MREQ 			=> cpu_mreq_n,
	N_IORQ 			=> cpu_iorq_n,
	N_WR 				=> cpu_wr_n,
	N_RD 				=> cpu_rd_n,
	N_M1 				=> cpu_m1_n,
	
	-- loader signals
	loader_act 		=> loader_act,
	loader_ram_a 	=> loader_ram_a(20 downto 0),
	loader_ram_do 	=> loader_ram_do,
	loader_ram_wr 	=> loader_ram_wr,

	-- ram 
	MA 				=> MA,
	MD 				=> MD,
	N_MRD 			=> MRD_N,
	N_MWR 			=> MWR_N,
	-- ram out to cpu
	DO 				=> ram_do_bus,
	N_OE 				=> ram_oe_n,	
	-- ram pages
	RAM_BANK 		=> port_7ffd_reg(2 downto 0),
	RAM_EXT 			=> ram_ext, -- seg A3 - seg A5

	-- TRDOS 
	TRDOS 			=> dos_act,	

	-- video
	VA 				=> vid_a_bus,
	VID_PAGE 		=> port_7ffd_reg(3), -- seg A0 - seg A2
	VID_DO 			=> vid_do_bus,
	VID_RD 			=> vid_rd, 		-- read attribute or pixel	

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
	ENA_14 			=> ena_div2, 	-- 14 / 12
	ENA_7 			=> ena_div4, 	-- 7 / 6
	RESET 			=> reset,	
	BORDER 			=> port_xxfe_reg(7 downto 0),
	TURBO 			=> turbo_mode,	-- turbo signal for int length
	INTA 				=> cpu_inta_n,
	INT 				=> cpu_int_n,
	pFF_CS			=> vid_pff_cs, -- port FF select
	ATTR_O 			=> vid_attr,  -- attribute register output

	A 					=> vid_a_bus,
	VID_RD 			=> vid_rd,
	DI 				=> vid_do_bus,
	
	MODE60			=> kb_vsync,
	DS80 				=> ds80,
	CS7E				=> cs_xx7e,
	BUS_A 			=> cpu_a_bus(15 downto 8),
	BUS_D 			=> cpu_do_bus,
	BUS_WR_N 		=> cpu_wr_n,
	GX0 				=> gx0,	
	VIDEO_R 			=> vid_rgb(8 downto 6),
	VIDEO_G 			=> vid_rgb(5 downto 3),
	VIDEO_B 			=> vid_rgb(2 downto 0),	
	HSYNC 			=> vid_hsync,
	VSYNC 			=> vid_vsync,
	HCNT 				=> vid_hcnt,
	VCNT 				=> vid_vcnt,
	ISPAPER 			=> vid_ispaper,
	BLINK 			=> blink,
	SCREEN_MODE    => kb_screen_mode,
	COUNT_BLOCK 	=> count_block
);

-- osd overlay
U5: entity work.overlay
port map (
	CLK 				=> clk_bus,
	ENA_14 			=> ena_div2,
	DS80				=> ds80,
	RGB_I 			=> vid_rgb,
	RGB_O 			=> vid_rgb_osd,
	HCNT_I 			=> vid_hcnt,
	VCNT_I 			=> vid_vcnt,
	PAPER_I 			=> vid_ispaper,
	BLINK 			=> blink,

	-- icons
	STATUS_FD		=> not(fdd_cs_n) and (not(cpu_rd_n) or not(cpu_wr_n)),
	STATUS_SD 		=> zc_spi_start and zc_wr_en,
	STATUS_CF 		=> hdd_active,
	
	OSD_COMMAND 	=> osd_command
);

-- Scandoubler	
U6: entity work.vga_scandoubler
port map(
	clk => clk_bus,
	clk14en => ena_div2,
	enable_scandoubling => vid_scandoubler_enable,
	disable_scaneffect => '1',
	ri => vid_rgb_osd(8 downto 6),
	gi => vid_rgb_osd(5 downto 3),
	bi => vid_rgb_osd(2 downto 0),
	hsync_ext_n => vid_hsync,
	vsync_ext_n => vid_vsync,
	csync_ext_n => vid_hsync xor vid_vsync,
	ro => VGA_R(7 downto 2),
	go => VGA_G(7 downto 2),
	bo => VGA_B(7 downto 2),
	hsync => VGA_HS,
	vsync => VGA_VS
);

VGA_R(1 downto 0) <= (others => '0');
VGA_G(1 downto 0) <= (others => '0');
VGA_B(1 downto 0) <= (others => '0');

-- MCU
U7: entity work.mcu
port map(
	CLK => clk_bus,
	N_RESET => not areset,
	
	MCU_MOSI => MCU_MOSI,
	MCU_MISO => MCU_MISO,
	MCU_SCK => MCU_SCK,
	MCU_SS => MCU_CS_N,
	
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
	JOY_USB => joy_usb,
	
	RTC_A => mc146818_a_bus,
	RTC_DI => cpu_do_bus,
	RTC_DO => mc146818_do_bus,
	RTC_CS => '1',
	RTC_WR_N => not mc146818_wr,
	
	ROMLOADER_ACTIVE => loader_act,
	ROMLOAD_ADDR => loader_ram_a,
	ROMLOAD_DATA => loader_ram_do,
	ROMLOAD_WR => loader_ram_wr,
	
	SOFTSW_COMMAND => softsw_command,	
	OSD_COMMAND => osd_command,
	
	BUSY => mcu_busy
	
);

U8: entity work.hid_parser
port map (
	CLK => clk_bus,
	RESET => areset,	

	-- hid keyboard input
	KB_STATUS => hid_kb_status,
	KB_DAT0 => hid_kb_dat0,
	KB_DAT1 => hid_kb_dat1,
	KB_DAT2 => hid_kb_dat2,
	KB_DAT3 => hid_kb_dat3,
	KB_DAT4 => hid_kb_dat4,
	KB_DAT5 => hid_kb_dat5,	

	-- joy inputs
	JOY_TYPE_L => kb_joy_type_l(2 downto 0),
	JOY_TYPE_R => kb_joy_type_r(2 downto 0),
	JOY_L => joy_l,
	JOY_R => joy_r,
	
	-- cpu a
	A => cpu_a_bus(15 downto 8),	
	
	-- keyboard type Profi XT = '0' / Spectrum = '1'
	KB_TYPE => kb_type,
	
	-- outputs
	JOY_DO => joy_bus,
	KB_DO => kb_do_bus,
	KEYCODE => kb_keycode
);

U9: entity work.soft_switches
port map (
	CLK => clk_bus,
	
	SOFTSW_COMMAND => softsw_command,
	
	ROM_BANK => kb_rom_bank,
	TURBO_FDC => kb_turbofdc,
	COVOX => kb_covox,
	PSG_MIX => kb_psg_mix,
	PSG_TYPE => kb_psg_type,
	VIDEO => kb_video,
	VSYNC => kb_vsync,
	TURBO => kb_turbo,
	SWAP_FDD => kb_swap_fdd,
	JOY_TYPE_L => kb_joy_type_l,
	JOY_TYPE_R => kb_joy_type_r,
	MODE => kb_screen_mode,
	DIVMMC_EN => kb_divmmc_en,
	NEMOIDE_EN => kb_nemoide_en,
	KB_TYPE => kb_type,
	PAUSE => kb_pause,
	NMI => kb_nmi,
	RESET => kb_reset	
);

U10: entity work.cursor
port map(
	CLK => clk_bus,
	RESET => areset,
	
	-- inputs from usb hid mouse
	MS_X => hid_ms_x,
	MS_Y => hid_ms_y,
	MS_Z => hid_ms_z,
	MS_B => hid_ms_b,
	MS_UPD => hid_ms_upd,
	
	-- output delta
	OUT_X => ms_x,
	OUT_Y => ms_y,
	OUT_Z => ms_z,
	OUT_B => ms_b
	
);

ms_present <= '1';

U11: entity work.PCM5102
port map (
	clk => clk_bus,
	left => audio_l,
	right => audio_r,
	din => DAC_DAT,
	bck => DAC_BCK,
	lrck => DAC_LRCK
);
DAC_MUTE <= '1';

-- TurboSound
U12: entity work.turbosound
port map (
	I_CLK				=> clk_bus,
	I_ENA				=> ena_div16,
	I_ADDR			=> cpu_a_bus,
	I_DATA			=> cpu_do_bus,
	I_WR_N			=> cpu_wr_n,
	I_IORQ_N			=> cpu_iorq_n,
	I_M1_N			=> cpu_m1_n,
	I_RESET_N		=> cpu_reset_n,
	I_BDIR 			=> '1', 
	I_BC1 			=> '1', 
	O_SEL				=> ssg_sel,
	I_MODE 			=> kb_psg_type,
	-- ssg0
	O_SSG0_DA		=> ssg_cn0_bus,
	O_SSG0_AUDIO_A	=> ssg_cn0_a,
	O_SSG0_AUDIO_B	=> ssg_cn0_b,
	O_SSG0_AUDIO_C	=> ssg_cn0_c,
	-- ssg1
	O_SSG1_DA		=> ssg_cn1_bus,
	O_SSG1_AUDIO_A	=> ssg_cn1_a,
	O_SSG1_AUDIO_B	=> ssg_cn1_b,
	O_SSG1_AUDIO_C	=> ssg_cn1_c);
	
-- Covox
U13: entity work.covox
port map (
	I_RESET			=> reset,
	I_CLK				=> clk_bus,
	I_CS				=> kb_covox,
	I_WR_N			=> cpu_wr_n,
	I_ADDR			=> cpu_a_bus(7 downto 0),
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

U14: entity work.saa1099
port map(
	clk				=> clk_8,
	rst_n				=> not reset,
	cs_n				=> '0',
	a0					=> cpu_a_bus(8),		-- 0=data, 1=address
	wr_n				=> saa_wr_n,
	din				=> cpu_do_bus,
	out_l				=> saa_out_l,
	out_r				=> saa_out_r
);

	
-- Serial mouse emulation
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
	CPM 				=> cpm,
	DOS 				=> dos_act,
	ROM14 			=> rom14,
	
	MS_X 				=> ms_x,
	MS_Y				=> ms_y,
	MS_BTNS 			=> ms_b,
	MS_PRESET 		=> ms_present,
	MS_EVENT 		=> hid_ms_upd,
	
	DO 				=> serial_ms_do_bus,
	INT_N 			=> serial_ms_int,
	OE_N 				=> serial_ms_oe_n
);

U16: entity work.zifi 
port map (
	CLK    => clk_bus,
	RESET  => areset,
	DS80   => DS80,

	A      => cpu_a_bus,
	DI     => cpu_do_bus,
	DO     => zifi_do_bus,
	IORQ_N => cpu_iorq_n,
	RD_N   => cpu_rd_n,
	WR_N   => cpu_wr_n,
	ZIFI_OE_N => zifi_oe_n,
	
	ENABLED => zifi_api_enabled,

	UART_RX   => UART_RX,
	UART_TX   => zifi_uart_tx,
	UART_CTS  => zifi_uart_cts	
);

UART_TX <= zifi_uart_tx; -- when zifi_api_enabled = '1' else zxuno_uart_tx;
UART_CTS <= zifi_uart_cts; -- when zifi_api_enabled = '1' else zxuno_uart_cts;
ESP_RESET_N <= 'Z';
ESP_BOOT_N <= 'Z';

U17: entity work.ide_controller
port map(
	CLK 		=> clk_bus,
	ENA_CPU	=> ena_cpu,
	RESET 	=> reset,
	
	NEMOIDE_EN => nemoide_en,

	A 			=> cpu_a_bus,
	DI 		=> cpu_do_bus,
	IORQ_N 	=> cpu_iorq_n,
	MREQ_N 	=> cpu_mreq_n,
	M1_N 		=> cpu_m1_n,
	RD_N 		=> cpu_rd_n,
	WR_N 		=> cpu_wr_n,
	
	CPM		=> cpm,
	ROM14		=> rom14,
	DOS		=> dos_act,
	HDD_OFF	=> hdd_off,

	DO 		=> ide_do_bus,
	ACTIVE	=> hdd_active,
	OE_N 		=> ide_oe_n,

	IDE_A 	=> WA,
	IDE_D 	=> WD,
	IDE_CS_N => WCS_N,
	IDE_RD_N => WRD_N,
	IDE_WR_N => WWR_N,
	IDE_RESET_N => WRESET_N
);

U18: entity work.firefly_fdc
port map(
	clk => clk_bus,
	clk_16 => clk_16,
	reset => reset,

	a => cpu_a_bus,
	d => cpu_do_bus,
	m1_n => cpu_m1_n,
	wr_n => cpu_wr_n,
	rd_n => cpu_rd_n,
	iorq_n => cpu_iorq_n,

	cs_n => fdd_cs_n,
	csff_n => fdd_cs_pff_n,

	oe_n => fdd_oe_n,
	dout => fdd_do_bus,
	
	FDC_SIDE1 => FDC_SIDE_N,
	FDC_RDATA => FDC_RDATA,
	FDC_WPRT => FDC_WPRT,
	FDC_TR00 => FDC_TR00,
	FDC_INDEX => FDC_INDEX,
	FDC_WG => FDC_WGATE,
	FDC_WR_DATA => FDC_WDATA,
	FDC_STEP => FDC_STEP,
	FDC_DIR => FDC_DIR,
	FDC_MOTOR => FDC_MOTOR,
	FDC_DS => FDC_DRIVE
);

-- заглушки
--FDC_SIDE_N <= '0';
--FDC_DRIVE <= "00";
--FDC_MOTOR <= '0';
--FDC_WDATA <= '0';
--FDC_WGATE <= '0';
--FDC_STEP <= '0';
--FDC_DIR <= '0';

-------------------------------------------------------------------------------
-- Global signals

reset <= areset or kb_reset or loader_act or mcu_busy or rom_bank_reset; -- hot reset

-- CPU reset
process (clk_bus)
begin
	if rising_edge(clk_bus) then 
		cpu_reset_n <= not(reset); 
	end if;
end process;

cpu_inta_n <= cpu_iorq_n or cpu_m1_n;	-- INTA

-- 11.07.2013:OCH: implementation of nmi signal for DIVMMC
cpu_nmi_n <= mapcond when kb_nmi = '1' and divmmc_en = '1' else 
	'0' when divmmc_en = '0' and kb_nmi = '1' and ((cpu_m1_n = '0' and cpu_mreq_n = '0' and cpu_a_bus(15 downto 14) /= "00") or DS80 = '1') else 
	'1';
cpu_wait_n <= '1';

-- cpu wait condition
cpu_wait <= '1' when kb_pause = '1' or  (kb_screen_mode = "01" and memory_contention = '1' and automap = '0' and DS80 = '0') else '0';

-------------------------------------------------------------------------------
-- SD

SD_CS_N	<= zc_cs_n;
sd_CLK 	<= zc_sclk;
SD_DI 	<= zc_mosi;

-------------------------------------------------------------------------------
-- Ports

-- #FD port correction
-- IN A, (#FD) - read a value from a hardware port 
-- OUT (#FD), A - writes the value of the second operand into the port given by the first operand.
fd_sel <= '0' when (
	(cpu_do_bus(7 downto 4) = "1101" and cpu_do_bus(2 downto 0) = "011") or 
	(cpu_di_bus(7 downto 4) = "1101" and cpu_di_bus(2 downto 0) = "011")) else '1'; 

process(fd_sel, reset, cpu_m1_n)
begin
	if reset='1' then
		fd_port <= '1';
	elsif rising_edge(cpu_m1_n) then 
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
turbo_fdc_off <= not port_028b_reg(2) and kb_turbofdc;		-- 2 	- TURBO_FDC_off
fdc_swap <= port_028b_reg(3) or kb_swap_fdd;					-- 3 	- Floppy Disk Drive Selector Change
sound_off <= port_028b_reg(4);									-- 4 	- Sound_off
turbo_mode <= port_028b_reg(6 downto 5);						-- 5,6- Turbo Mode Selector 
lock_dffd <= port_028b_reg(7);								 	-- 7 	- Lock port DFFD
ext_rom_bank_pq <= ext_rom_bank when rom0 = '0' else "01";	-- ROMBANK ALT

rom14 <= port_7ffd_reg(4); -- rom bank
cpm 	<= port_dffd_reg(5); -- 1 -      TR-DOS        (ROM14=0);  ROM14=1 - .   . 
worom <= port_dffd_reg(4); -- 1 -    7ffd   ,       seg 00
ds80 	<= port_dffd_reg(7); -- 0 = seg05 spectrum bitmap, 1 = profi bitmap seg06 & seg 3a & seg 04 & seg 38
scr 	<= port_dffd_reg(6); --  CPU   seg 02,    D3 CMR0    1 (#8000-#BFFF)
sco 	<= port_dffd_reg(3); --     :
									-- 0 -   1 (#C000-#FFFF)
									-- 1 -   2 (#4000-#7FFF)

-- Extended memory for 1MB
ram_ext <= port_dffd_reg(2 downto 0); -- profi 1024

-- OCH: change decoding of #FE port when Nemo enabled  
cs_xxfe <= '1' when (cpu_iorq_n = '0' and cpu_a_bus(0) = '0' and nemoide_en = '0') or 
						  (cpu_iorq_n = '0' and cpu_a_bus(6 downto 0) = "1111110" and nemoide_en = '1') else '0';
cs_xx7e <= '1' when cs_xxfe = '1' and cpu_a_bus(7) = '0' else '0';
cs_eff7 <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"EFF7" else '0';
cs_fffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"FFFD" and fd_port = '1' else '0';
cs_dffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"DFFD" and fd_port = '1' and lock_dffd = '0' else '0';
cs_7ffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"7FFD" and fd_port = '1' else '0';
cs_1ffd <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus = X"1FFD" and fd_port = '1' else '0';
-- OCH: change decoding of #FD port when Nemo enabled
cs_xxfd <= '1' when (cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus(15) = '0' and cpu_a_bus(1) = '0' and nemoide_en = '0') or
						  (cpu_iorq_n = '0' and cpu_m1_n = '1' and cpu_a_bus(15) = '0' and cpu_a_bus(7 downto 0) = x"FD" and nemoide_en = '1') else '0';						  

--  AS 
cs_rtc_as <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and
							((cpu_a_bus(7 downto 0) = X"FF" or cpu_a_bus(7 downto 0) = X"BF") and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0'))) --  
				     else '0';
--
--  DS 					  
cs_rtc_ds <= '1' when cpu_iorq_n = '0' and cpu_m1_n = '1' and 
							((cpu_a_bus(7 downto 0) = X"DF" or cpu_a_bus(7 downto 0) = X"9F") and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0'))) --  
				     else '0';
					  
--  #7e -    /wr
port_xxfe_reg <= cpu_do_bus when cs_xxfe = '1' and (cpu_wr_n'event and cpu_wr_n = '1');

--  Profi FDD
RT_F2_1 <='0' when (cpu_a_bus(7 downto 5)="001" and cpu_a_bus(1 downto 0)="11" and cpu_iorq_n='0') and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0')) else '1'; --6D
RT_F2_2 <='0' when cpu_a_bus(7 downto 5)="101" and cpu_a_bus(1 downto 0)="11" and cpu_iorq_n='0' and cpm='1' and dos_act='0' and rom14='0' else '1'; --75
RT_F2_3 <='0' when cpu_a_bus(7 downto 5)="111" and cpu_a_bus(1 downto 0)="11" and cpu_iorq_n='0' and cpm='0' and dos_act='1' and rom14='1' else '1'; --F3 and FB
fdd_cs_pff_n <= RT_F2_1 and RT_F2_2 and RT_F2_3;

RT_F1_1 <= '0' when cpu_a_bus(7)='0' and cpu_a_bus(1 downto 0)="11" and cpu_iorq_n='0' and cpm='1' and dos_act='0' and rom14='0' else '1';
RT_F1_2 <= '0' when cpu_a_bus(7)='0' and cpu_a_bus(1 downto 0)="11" and cpu_iorq_n='0' and cpm='0' and dos_act='1' and rom14='1' else '1';
RT_F1 <= RT_F1_1 and RT_F1_2;
P0 <='0' when (cpu_a_bus(7)='1' and cpu_a_bus(4 downto 0)="00011" and cpu_iorq_n='0') and ((cpm='1' and rom14='1') or (dos_act='1' and rom14='0')) else '1';
fdd_cs_n <= RT_F1 and P0;

-- Ports
process (reset, areset, clk_bus, cpu_a_bus, dos_act, cs_xxfe, cs_eff7, cs_7ffd, cs_xxfd, port_7ffd_reg, port_1ffd_reg, cpu_mreq_n, cpu_m1_n, cpu_wr_n, cpu_do_bus, fd_port, cs_008b, kb_turbo, kb_turbo_old)
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
--- 06.07.2023:OCH: DIVMMC port added to ZController
		port_e3_reg(5 downto 0) <= (others => '0');
		port_e3_reg(7) <= '0';
		
	elsif clk_bus'event and clk_bus = '1' then
--- 06.07.2023:OCH: DIVMMC port E3 added to ZController
			-- #xxE3
--- 08.07.2023:OCH: Due to confict with port (E3) of fddcontroller in cpm mode
--- block DIVMMC port E3 when in cpm
			if (cpu_iorq_n = '0' and cpu_wr_n = '0' and cpu_a_bus(7 downto 0) = X"E3" and cpm = '0' and divmmc_en = '1') then	
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
			
			if cs_7ffd = '1' and cpu_wr_n = '0' and (port_7ffd_reg(5) = '0' or port_dffd_reg(4)='1') then -- short #FD
			  port_7ffd_reg(7 downto 6) <= cpu_do_bus(7 downto 6);
			end if;
			
			-- #1FFD
			if cs_1ffd = '1' and cpu_wr_n = '0' then -- #1FFD
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
			if (((cpu_m1_n = '0' and cpu_mreq_n = '0' and cpu_a_bus(15 downto 8) = X"3D" and (rom14 = '1' or unlock_128 = '1')) or 
			(cpu_nmi_n = '0'  and DS80 = '0')) and port_dffd_reg(4) = '0') or (onrom = '1') then dos_act <= '1';
			elsif ((cpu_m1_n = '0' and cpu_mreq_n = '0' and cpu_a_bus(15 downto 14) /= "00") or (port_dffd_reg(4) = '1')) then dos_act <= '0'; end if;
				
	end if;
end process;

-------------------------------------------------------------------------------
-- Audio mixer

speaker <= port_xxfe_reg(4);
BEEPER <= speaker;

audio_mono <= 	
				("0000" & speaker & "00000000000") +
				("00000" & TAPE_IN & "0000000000") +				
				("0000"  & ssg_cn0_a &     "0000") + 
				("0000"  & ssg_cn0_b &     "0000") + 
				("0000"  & ssg_cn0_c &     "0000") + 
				("0000"  & ssg_cn1_a &     "0000") + 
				("0000"  & ssg_cn1_b &     "0000") + 
				("0000"  & ssg_cn1_c &     "0000") + 
				("0000"  & covox_a &       "0000") + 
				("0000"  & covox_b &       "0000") + 
				("0000"  & covox_c &       "0000") + 
				("0000"  & covox_d &       "0000") + 
				("0000"  & covox_fb &      "0000") + 
				("0000"  & saa_out_l &     "0000") + 				
				("0000"  & saa_out_r &     "0000");

audio_l <= "0000000000000000" when loader_act = '1' or kb_pause = '1' or sound_off = '1' else 
				audio_mono when kb_psg_mix = "10" else
				("000" & speaker & "000000000000") + -- ACB: L = A + C/2
				("00000" & TAPE_IN & "0000000000") +	
				("000"  & ssg_cn0_a &     "00000") + 
				("0000"  & ssg_cn0_c &     "0000") + 
				("000"  & ssg_cn1_a &     "00000") + 
				("0000"  & ssg_cn1_c &     "0000") + 
				("000"  & covox_a &       "00000") + 
				("000"  & covox_b &       "00000") + 
				("000"  & covox_fb &      "00000") + 
				("000"  & saa_out_l  &    "00000") when kb_psg_mix = "01" else 
				("000" & speaker & "000000000000") +  -- ABC: L = A + B/2
				("00000" & TAPE_IN & "0000000000") +	
				("000"  & ssg_cn0_a &     "00000") + 
				("0000"  & ssg_cn0_b &     "0000") + 
				("000"  & ssg_cn1_a &     "00000") + 
				("0000"  & ssg_cn1_b &     "0000") + 
				("000"  & covox_a &       "00000") + 
				("000"  & covox_b &       "00000") + 
				("000"  & covox_fb &      "00000") + 
				("000"  & saa_out_l  &    "00000");
				
audio_r <= "0000000000000000" when loader_act = '1' or kb_pause = '1' or sound_off = '1' else 
				audio_mono when kb_psg_mix = "10" else
				("000" & speaker & "000000000000") + -- ACB: R = B + C/2
				("00000" & TAPE_IN & "0000000000") +	
				("000"  & ssg_cn0_b &     "00000") + 
				("0000"  & ssg_cn0_c &     "0000") + 
				("000"  & ssg_cn1_b &     "00000") + 
				("0000"  & ssg_cn1_c &     "0000") + 
				("000"  & covox_c &       "00000") + 
				("000"  & covox_d &       "00000") + 
				("000"  & covox_fb &      "00000") + 
				("000"  & saa_out_r &     "00000") when kb_psg_mix = "01" else
				("000" & speaker & "000000000000") + -- ABC: R = C + B/2
				("00000" & TAPE_IN & "0000000000") +	
				("000"  & ssg_cn0_c &     "00000") + 
				("0000"  & ssg_cn0_b &     "0000") + 
				("000"  & ssg_cn1_c &     "00000") + 
				("0000"  & ssg_cn1_b &     "0000") + 
				("000"  & covox_c &       "00000") + 
				("000"  & covox_d &       "00000") + 
				("000"  & covox_fb &      "00000") + 
				("000"  & saa_out_r &     "00000");
				
-- Tape Out: 1/0 for revDS, open collector output for revA,B,C,D
TAPE_OUT <= port_xxfe_reg(3);
				
-- SAA1099
saa_wr_n <= '0' when (cpu_iorq_n = '0' and cpu_wr_n = '0' and cpu_a_bus(7 downto 0) = X"FF" and dos_act = '0') else '1';

---------------------------------------------------------------------------------
-- Port I/O

mc146818_wr <= '1' when (cs_rtc_ds = '1' and cpu_iorq_n = '0' and cpu_wr_n = '0' and cpu_m1_n = '1') else '0';


--- 06.07.2023:OCH: DIVMMC ports added to ZController
-- Z-controller + DIVMMC spi 
zc_spi_start <= '1' when (cpu_a_bus(7 downto 0) = X"57" or (cpu_a_bus(7 downto 0) = X"EB" and cpm = '0' and divmmc_en = '1')) and cpu_iorq_n='0' and cpu_m1_n='1' and loader_act='0' else '0';
zc_wr_en <= '1' when (cpu_a_bus(7 downto 0) = X"57" or (cpu_a_bus(7 downto 0) = X"EB" and cpm = '0' and divmmc_en = '1')) and cpu_iorq_n='0' and cpu_m1_n='1' and cpu_wr_n='0' and loader_act='0' else '0';
port77_wr <= '1' when (cpu_a_bus(7 downto 0) = X"77" or (cpu_a_bus(7 downto 0) = X"E7" and divmmc_en = '1')) and cpu_iorq_n='0' and cpu_m1_n='1' and cpu_wr_n='0' and loader_act='0' else '0';

process (port77_wr, loader_act, reset, clk_bus)
	begin
		if loader_act='1' or reset='1' then
			zc_cs_n <= '1';
		elsif clk_bus'event and clk_bus='1' then
--- 06.07.2023:OCH: DIVMMC uses 0 bit to control zc_cs_n, instead of 1 bit ZController. 
--- Lets check port number and select correct bit
--			if port77_wr='1' then
--				zc_cs_n <= cpu_do_bus(1);
--			end if;
			if port77_wr='1' then
--- 08.07.2023:OCH: E7 port confict with E7 port of SPI Flash parallel interface so block
--- DIVMMC E7 port when flash loader software active   
				if cpu_a_bus(7 downto 0) = X"E7" and ext_rom_bank(1 downto 0) /= "10" then
					zc_cs_n <= cpu_do_bus(0);
				else
					zc_cs_n <= cpu_do_bus(1);
				end if;
			end if;
		end if;
end process;

U_ZC_SPI: entity work.zc_spi     -- SD
port map(
	DI				=> cpu_do_bus,
	START			=> zc_spi_start,
	WR_EN			=> zc_wr_en,
	CLC     		=> clk_bus, 
	MISO    		=> SD_DO,
	DO				=> zc_do_bus,
	SCK     		=> zc_sclk,
	MOSI    		=> zc_mosi
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
		if cpu_a_bus(15 downto 8) = "00111101" then 
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

process (selector, cpu_a_bus, gx0, serial_ms_do_bus, ram_do_bus, mc146818_do_bus, kb_do_bus, zc_do_bus, ssg_cn0_bus, ssg_cn1_bus, port_7ffd_reg, port_dffd_reg, zxuno_uart_do_bus,
			zxuno_uart2_do_bus, vid_attr, port_eff7_reg, joy_bus, ms_z, ms_b, ms_x, ms_y, zxuno_addr_to_cpu, port_xxC7_reg, port_008b_reg,
			port_018b_reg, port_028b_reg, TAPE_IN)
begin
	case selector is
		when x"00" => cpu_di_bus <= ram_do_bus;
		when x"01" => cpu_di_bus <= mc146818_do_bus;
		when x"02" => cpu_di_bus <= GX0 & TAPE_IN & kb_do_bus;
		when x"03" => cpu_di_bus <= zc_do_bus;
		when x"04" => cpu_di_bus <= "11111100";	
		when x"05" => cpu_di_bus <= joy_bus;
		when x"06" => cpu_di_bus <= ssg_cn0_bus;
		when x"07" => cpu_di_bus <= ssg_cn1_bus;
		when x"08" => cpu_di_bus <= port_dffd_reg;
		when x"09" => cpu_di_bus <= port_7ffd_reg;
		when x"0A" => cpu_di_bus <= ms_z(3 downto 0) & '1' & not(ms_b(2)) & not(ms_b(0)) & not(ms_b(1)); -- D0=right, D1 = left, D2 = middle, D3 = fourth, D4..D7 - wheel
		when x"0B" => cpu_di_bus <= ms_x;
		when x"0C" => cpu_di_bus <= ms_y;
		when x"0D" => cpu_di_bus <= zxuno_uart2_do_bus;
		when x"0E" => cpu_di_bus <= serial_ms_do_bus;
		when x"0F" => cpu_di_bus <= zxuno_addr_to_cpu;
		when x"10" => cpu_di_bus <= zxuno_uart_do_bus;
		when x"13" => cpu_di_bus <= port_008b_reg;
		when x"14" => cpu_di_bus <= port_018b_reg;
		when x"15" => cpu_di_bus <= port_028b_reg;
		when x"16" => cpu_di_bus <= zifi_do_bus;
		when x"17" => cpu_di_bus <= vid_attr;
		when x"18" => cpu_di_bus <= fdd_do_bus;
		when x"19" => cpu_di_bus <= ide_do_bus;
		when others => cpu_di_bus <= (others => '1');
	end case;
end process;

selector <= 	
	x"00" when (ram_oe_n = '0') else -- ram / rom
	x"01" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cs_rtc_ds = '1') else -- RTC MC146818A
	x"02" when (cs_xxfe = '1' and cpu_rd_n = '0') else 									-- Keyboard, port #FE
	x"18" when (fdd_oe_n = '0') else -- fdd
	x"19" when (ide_oe_n = '0') else	-- ide	
 	x"03" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and (cpu_a_bus(7 downto 0) = X"57" or (cpu_a_bus(7 downto 0) = X"EB" and cpm = '0' and divmmc_en = '1')) ) else 	-- Z-Controller + DivMMC
	x"04" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cpu_a_bus(7 downto 0) = X"77") else 	-- Z-Controller
	x"05" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_m1_n = '1' and cpu_a_bus( 7 downto 0) = X"1F" and dos_act = '0' and cpm = '0' and joy_mode = "000") else -- Joystick, port #1F
	x"06" when (cs_fffd = '1' and cpu_rd_n = '0' and ssg_sel = '0') else 			-- TurboSound
	x"07" when (cs_fffd = '1' and cpu_rd_n = '0' and ssg_sel = '1') else
	x"08" when (cs_dffd = '1' and cpu_rd_n = '0') else										-- port #DFFD
	x"09" when (cs_7ffd = '1' and cpu_rd_n = '0') else										-- port #7FFD
	x"0A" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = X"FADF" and ms_present = '1' and cpm='0') else	-- Mouse0 port key, z
	x"0B" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = X"FBDF" and ms_present = '1' and cpm='0') else	-- Mouse0 port x
	x"0C" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus = X"FFDF" and ms_present = '1' and cpm='0') else	-- Mouse0 port y 
	x"0D" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and zxuno_uart2_oe_n = '0') else -- ZX UNO UART2
	x"0E" when (serial_ms_oe_n = '0') else -- Serial mouse
	x"0F" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and zxuno_addr_oe_n = '0') else -- ZX UNO Register
	x"10" when (cpu_iorq_n = '0' and cpu_rd_n = '0' and zxuno_uart_oe_n = '0') else -- ZX UNO UART
	x"13" when (cs_008b = '1' and cpu_rd_n = '0') else										-- port #008B
	x"14" when (cs_018b = '1' and cpu_rd_n = '0') else										-- port #018B
	x"15" when (cs_028b = '1' and cpu_rd_n = '0') else										-- port #028B
	x"16" when zifi_oe_n = '0' else  -- zifi
	x"17" when (vid_pff_cs = '1' and cpu_iorq_n = '0' and cpu_rd_n = '0' and cpu_a_bus( 7 downto 0) = X"FF") and dos_act='0' and cpm = '0' and ds80 = '0' else -- Port FF select
	(others => '1');


-- SDRAM
SDR_BA <= "00";
SDR_A <= (others => '0');
SDR_CLK <= '0';
SDR_DQM <= "00";
SDR_WE_N <= '1';
SDR_CAS_N <= '1';
SDR_RAS_N <= '1';

-- FT812
FT_SPI_CS_N <= '1';
FT_SPI_SCK <= '0';
FT_OE_N <= '1';

-- V_CLK buf
VCLK_buf: ODDR2
port map(
	Q => V_CLK, -- pixel clock for video dac
	C0 => clk_bus,
	C1 => not clk_bus,
	D0 => '1',
	D1 => '0'
);

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
divmmc_en <= kb_divmmc_en;
nemoide_en <= kb_nemoide_en;


end Behavioral;

