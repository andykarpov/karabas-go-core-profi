#!/bin/bash
# The rewrites of the timing work against the old code (sim/ref):
#   tb_eq_strobes (ghdl): strobe_reg (fd_port, port #FE) and divmmc_map, a T80 running random code
#   tb_eq_ide (ghdl):     ide_controller, the high byte register
#   tb_eq_overlay (ISim): overlay and icons (the memories are Verilog modules of karabas-go-modules)
# Usage: src/sim/run_eq_sim.sh [path to ISE_DS/settings64.sh]
# Each test prints "<tb>: 0 errors"; the script fails on any other count.

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
M="$SRC/../modules/rtl"
OUT="$SIM/build"
mkdir -p "$OUT/ghdl" "$OUT/isim"

result() {
	grep -E "$1: " "$2" | sed 's/.*(report \(note\|error\)): //; s/.*Note: //; s/.*Error: //' | head -14
	grep -q "$1: 0 errors" "$2" || { echo "$1 FAILED"; exit 1; }
}

# ---- ghdl ----
G="--std=08 -fsynopsys --workdir=$OUT/ghdl"
cd "$SRC"
ghdl -a $G rtl/t80se/T80_Pack.vhd rtl/t80se/T80_Reg.vhd rtl/t80se/T80_MCode.vhd rtl/t80se/T80_ALU.vhd \
	rtl/t80se/T80.vhd rtl/t80se/T80s.vhd \
	sim/ref/strobe_reg_ref.vhd sim/ref/divmmc_map_ref.vhd sim/ref/ide_controller_ref.vhd \
	rtl/bus/strobe_reg.vhd rtl/bus/divmmc_map.vhd rtl/ide/ide_controller.vhd \
	sim/tb_eq_strobes.vhd sim/tb_eq_ide.vhd 2> "$OUT/ghdl/analyse.log" || { cat "$OUT/ghdl/analyse.log"; exit 1; }
for tb in tb_eq_strobes tb_eq_ide; do
	ghdl -e $G $tb
	ghdl -r $G $tb --ieee-asserts=disable > "$OUT/ghdl/$tb.log" 2>&1 || true
	result $tb "$OUT/ghdl/$tb.log"
done

# ---- ISim ----
set --
source "$SETTINGS" > /dev/null
cd "$OUT/isim"
vlogcomp -work work "$M/mem/kg_sdpram.v" "$M/mem/kg_sprom.v" "$M/video/osd/kg_pix_doubler.v" > vlogcomp.log
vhpcomp -work work "$SIM/ref/icons_ref.vhd" "$SIM/ref/overlay_ref.vhd" "$SRC/rtl/osd/icons.vhd" \
	"$SRC/rtl/osd/overlay.vhd" "$SIM/tb_eq_overlay.vhd" > vhpcomp.log
fuse -top work.tb_eq_overlay -o tb_eq_overlay.exe > fuse.log
echo "run all; quit" > run.tcl
# the simulation runs in the directory it was built in; icons.vhd reads rtl/osd/icons.bit relative to it
ln -sfn "$SRC/rtl" rtl
./tb_eq_overlay.exe -tclbatch run.tcl > tb_eq_overlay.log 2>&1 || true
result tb_eq_overlay "$OUT/isim/tb_eq_overlay.log"
echo "EQ SIMULATION PASSED"
