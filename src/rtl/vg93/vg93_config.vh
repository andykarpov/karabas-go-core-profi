// Build configuration of the VG93 model for the Profi core (hrdy_fdc): replaces the empty default of the upstream
// rtl/vg93_config.vh (github.com/demyanenko-d/FD1793_1818VG93). The macros are described in vg93_top.v.
// SYSCLK is clk_bus (28 / 24 MHz), the CPU clock: one clock domain with the host bus, no clock from logic.
`ifndef VG93_CONFIG_VH
`define VG93_CONFIG_VH
`define VG93_EMBEDDED                 // DRQ / INTRQ push-pull inside the FPGA
`define VG93_MFM_ONLY                 // DDEN_n was tied low
`define VG93_NO_TEST                  // TEST_n was tied high
`define VG93_NO_RG                    // RG is not used (fdd_glue is free running)
`define VG93_NO_PIN33                 // /VFOE was not used
`define VG93_FAST_SYSCLK              // no posedge /RAWREAD catcher: a clock from logic; fdd_glue gives 1-SYSCLK pulses
`define VG93_TURBO_STEP               // TurboFDC, always on: step rate and head delays of CLK 2 MHz, the core at 1 MHz
`endif
