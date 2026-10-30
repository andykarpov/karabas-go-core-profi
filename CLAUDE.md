# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The Profi (Karabas Pro) ZX Spectrum core for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). One core, three tops: `src/rtl/karabas_go_top.vhd` (VGA, floppy connector), `karabas_mini_top.vhd` and `karabas_minig_top.vhd` (HDMI). The machine is `src/rtl/profi.vhd`; the tops differ in their board glue and the generics they give it (`ENABLE_FDD`, `BURST_MAX_MHZ`, `SOFTSW_LAYOUT`).

The board modules (MCU link, memories, clocks, DACs, HDMI, OSD helpers) come from the git submodule `modules/` ([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules), shared by the Karabas Go cores; clone with `--recursive` or run `git submodule update --init`). A change to them is made there and taken here by updating the submodule commit. Its `CLAUDE.md` and `docs/PLAN.md` have the rules (Verilog-2001 for XST, tests, checks of LUTs and timing).

## Build

- `cd src && make` builds the three boards (`make go`, `mini`, `minig` one of them; `make minig-xst`, `-impl`, `-core` one step; `make minig-report` the utilization and timing of the last build). It runs the ISE command-line flow (the steps and options of the former ISE projects) and sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh` (`ISE_SETTINGS=` to change it). The boards share `xst/` and `_ngo/` in `src/`, so they are built one after the other; a board takes about 30 minutes, mostly PAR.
- Inputs per board: `karabas_<board>.prj` (the source list, add new files here; the shared modules as `"../modules/rtl/..."`), `.xst`, `.ucf`, `.ut`. There is no ISE GUI project (`.xise`) any more; the Makefile has its map / par options.
- `core` packs `karabas_<board>.bin` and the ROMs of `core.json` (Go), `core_mini.json`, `core_minig.json` into `profi.kg1` / `kg2` / `kg3` with `make_core.py`, a symlink to karabas-go-tools (the sibling repo must be checked out next to this one). The `.bin` and `.kg*` files are committed as the release.
- The `osd` items of the json are the soft switch registers in their order: `SOFTSW_LAYOUT` 0 for `core.json` (Go, with the floppy items), 1 for the Mini / Mini G files; the fields are cut out of the `kg_soft_switches` registers in `profi.vhd`. A new item changes the index of the items after it.
- Check `karabas_<board>_map.mrp` (LUTs, slices, block RAMs: the design is close to full) and `karabas_<board>.par` (timing) after a change; `make <board>-report` prints both, and the result of `make <board>-ds80`.
- `make <board>-ds80`: trce of the routed board with clk_bus at 24 MHz. clk_bus is a BUFGMUX of 28 and 24 MHz (the DS80 video mode); both PERIODs cover the same flip-flops and trce analyses 28 MHz only, while the phases to the other clocks (clk_sdr, HDMI) differ at 24 MHz. Run it after every build; both analyses must report "All constraints were met".

## Timing

- Clocks (`rtl/clock/clock.vhd`), one PLL (VCO 675 MHz), phase 0: clk_bus (28 / 24 MHz by ds80, BUFGMUX), clk_rgb (clk_bus gated by ena_rgb, BUFGCE), clk_gs (28 MHz in both modes: the General Sound, so its SDRAM on clk_sdr 84 MHz is always 1:3), clk_sdr, clk_12 (MIDI clock out), clk_8 (FT812 clock out of the Mini / Mini G). The FDC of the Go (`rtl/vg93`) runs on clk_bus. The SAA1099 runs on clk_bus with an 8 MHz clock enable. HDMI: a DCM on clk_bus.
- The three ucf have the same timing block (the end of each file): PERIOD on CLK_50MHZ (derived onto the PLL outputs), TS_CLK_MCU, bounded DATAPATHONLY paths for the asynchronous crossings (MCU_SCK <-> clk_bus), the SRAM budget (12 ns out + 10 ns tAA + 12 ns in in one 28 MHz clock). Each exception is explained there; do not TIG paths that are real.
- No clocks from logic and no latches (check "Clock Information" of the `.syr`): a register loaded by a CPU strobe uses `rtl/bus/strobe_reg.vhd`, a decoded enable becomes a clock enable or a register with a bypass (OSD, `rtl/bus/divmmc_map.vhd`). A register whose initial value differs from its asynchronous reset value makes XST build a latch.

## Simulation

- `src/sim/run_burst_sim.sh` (ISim): `tb_mcu_burst.vhd`, the CMD_CAPS answer and the rom loader over classic frames and bursts at 16 / 32 MHz, `kg_mcu` with the parameters of `profi.vhd`.
- `src/sim/run_eq_sim.sh` (ghdl, ISim): the rewrites of the timing work against the old code in `sim/ref` (the version of master 3d016a4, entities renamed `*_ref`): `tb_eq_strobes` (strobe_reg, divmmc_map; a T80 running random code in every turbo mode), `tb_eq_ide` (ide_controller), `tb_eq_overlay` (overlay, icons). Each prints `<tb>: 0 errors`.
- `src/sim/run_fdc_sim.sh` (iverilog): `tb_hrdy_fdc`, the FDC of the Go with a model of a drive (MFM track, steps, index): Restore with the turbo step rate, Read Sector, Write Sector decoded back from WDATA, at 28 and 24 MHz and a disk 2 % off speed; the CPU writes the registers back to back (the WAIT of `hrdy_fdc`).
- The tests of the shared modules are in `modules/sim` (`run_all.sh`).

## Layout

- `src/rtl/profi.vhd`: CPU (T80), memory, video, OSD, MCU link (`kg_mcu`), soft switches, sound (Turbosound FM, SAA1099, GS, OPL2, Covox), FDC, IDE, DivMMC / Z-Controller, ZiFi / RS232 over USB.
- `src/rtl/osd`: the OSD of this core (`overlay.vhd`, 9-bit RGB, with `icons.vhd`), on `kg_sdpram` / `kg_sprom` / `kg_pix_doubler`.
- `src/rtl/mcu`: the core-specific parts of the HID input: `hid_parser.vhd` (keyboard matrix, joysticks), `usb_ps2_lut.vhd`, `dot_matrix.v`.
- `src/rtl/clock/clock.vhd`: the clocks (`kg_pll`) and the clock enables of the machine.
- `src/rtl/vg93`: the FDC of the Go: `hrdy_fdc.v` (Beta Disk glue, port #FF, WAIT after a register write), `fdd_glue.v` (data separator, write precompensation), the VG93 model `vg93_*` from [FD1793_1818VG93](https://github.com/demyanenko-d/FD1793_1818VG93) `rtl/` (taken unchanged; the build macros in our `vg93_config.vh`, TurboFDC = `VG93_TURBO_STEP`).
- `src/rtl/bus`: `strobe_reg.vhd` (registers loaded at the end of a CPU strobe: the #FD opcode latch, port #FE), `divmmc_map.vhd` (DivMMC automap).
