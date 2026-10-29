#!/bin/bash
# The virtual HDD:
#   tb_hdf_ata (iverilog): hdf_ata alone
#   tb_ide_hdf (ISim):     ide_controller, ide_mux, hdf_ata, img_sdc with a model of the mcu and of the CF card
# Usage: src/sim/run_hdf_sim.sh [path to ISE_DS/settings64.sh]
set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
M="$SRC/../modules/rtl"
OUT="$SIM/build"
mkdir -p "$OUT/isim_hdf"

cd "$SIM"
iverilog -o "$OUT/tb_hdf_ata" "$M/mcu/hdf_ata.v" tb_hdf_ata.v
vvp "$OUT/tb_hdf_ata"

set --
source "$SETTINGS" > /dev/null
cd "$OUT/isim_hdf"
vlogcomp -work work "$M/mcu/hdf_ata.v" "$M/mcu/img_sdc.v" > vlogcomp.log
vhpcomp -work work "$SRC/rtl/ide/ide_controller.vhd" "$SRC/rtl/ide/ide_mux.vhd" "$SIM/tb_ide_hdf.vhd" > vhpcomp.log
fuse -top work.tb_ide_hdf -o tb_ide_hdf.exe > fuse.log
echo "run all; quit" > run.tcl
./tb_ide_hdf.exe -tclbatch run.tcl > tb_ide_hdf.log 2>&1 || true
grep "tb_ide_hdf: " tb_ide_hdf.log | grep -v finished
grep -q "tb_ide_hdf: 0 errors" tb_ide_hdf.log || { echo "tb_ide_hdf FAILED"; exit 1; }
echo "HDF SIMULATION PASSED"
