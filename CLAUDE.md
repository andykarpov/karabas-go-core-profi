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
- Check `karabas_<board>_map.mrp` (LUTs, slices, block RAMs: the design is close to full) and `karabas_<board>.par` (timing) after a change.

## Simulation

- `src/sim/run_burst_sim.sh` (ISim): `tb_mcu_burst.vhd`, the CMD_CAPS answer and the rom loader over classic frames and bursts at 16 / 32 MHz, `kg_mcu` with the parameters of `profi.vhd`.
- The tests of the shared modules are in `modules/sim` (`run_all.sh`).

## Layout

- `src/rtl/profi.vhd`: CPU (T80), memory, video, OSD, MCU link (`kg_mcu`), soft switches, sound (Turbosound FM, SAA1099, GS, OPL2, Covox), FDC, IDE, DivMMC / Z-Controller, ZiFi / RS232 over USB.
- `src/rtl/osd`: the OSD of this core (`overlay.vhd`, 9-bit RGB, with `icons.vhd`), on `kg_sdpram` / `kg_sprom` / `kg_pix_doubler`.
- `src/rtl/mcu`: the core-specific parts of the HID input: `hid_parser.vhd` (keyboard matrix, joysticks), `usb_ps2_lut.vhd`, `dot_matrix.v`.
- `src/rtl/clock/clock.vhd`: the clocks (`kg_pll`) and the clock enables of the machine.
