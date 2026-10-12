#!/usr/bin/env bash
# Quartus compile of the behavioural model rtl/behav (Cyclone IV E): synthesis, fitting, timing at SYSCLK.
# Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
#   rtl/behav/run_quartus.sh [MHz]       -> rtl/quartus/vg93.{map,fit,sta}.rpt   (default 16 MHz)
# Env: QUARTUS_BIN (default C:/intelFPGA/22.1std/quartus/bin64), FAMILY (default "Cyclone IV E"), DEVICE (default
# EP4CE10E22C8), MACROS (Verilog macros, e.g. VG93_ROM_FILE), WORK (default tmp/quartus_behav).
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${QUARTUS_BIN:-/c/intelFPGA/22.1std/quartus/bin64}
MHZ=${1:-16}
WORK=${WORK:-$HERE/quartus}
mkdir -p "$WORK"
cp "$HERE/vg93-microcode-rom.hex" "$WORK/"
{
  echo "set_global_assignment -name FAMILY \"${FAMILY:-Cyclone IV E}\""
  for m in $MACROS; do echo "set_global_assignment -name VERILOG_MACRO \"$m=1\""; done
  echo "set_global_assignment -name DEVICE ${DEVICE:-EP4CE10E22C8}"
  echo 'set_global_assignment -name TOP_LEVEL_ENTITY vg93_top'
  echo "set_global_assignment -name SEARCH_PATH $(cygpath -m "$HERE")"
  echo 'set_global_assignment -name SDC_FILE vg93.sdc'
  for f in "$HERE"/*.v; do echo "set_global_assignment -name VERILOG_FILE $(cygpath -m "$f")"; done
} > "$WORK/vg93.qsf"
echo 'PROJECT_REVISION = "vg93"' > "$WORK/vg93.qpf"
period=$(awk "BEGIN { printf \"%.3f\", 1000 / $MHZ }")
{
  echo "create_clock -name sysclk -period $period [get_ports SYSCLK]"
  echo 'create_clock -name rawread -period 1000 [get_ports RAWREAD_n]'   # clocks the /RAWREAD catchers
  echo 'set_clock_groups -asynchronous -group {sysclk} -group {rawread}'
  # the chip's pins are asynchronous to SYSCLK: sampled once (vg93_top), or driven straight to the bus
  echo 'set_false_path -from [remove_from_collection [all_inputs] [get_ports SYSCLK]]'
  echo 'set_false_path -to [all_outputs]'
} > "$WORK/vg93.sdc"
cd "$WORK"
for step in map fit sta; do
    "$BIN/quartus_$step.exe" vg93 > $step.log 2>&1 || { grep -E "Error \(" $step.log; exit 1; }
done
grep -E "Total logic elements|Total registers|Total memory bits|Embedded Multiplier|Total pins" vg93.fit.rpt | head -6
grep -E "Number of user-specified and inferred latches" vg93.map.rpt || true
grep -iE "inferred latch|combinational loop" map.log | head || true
grep -A4 "Slow 1200mV 85C Model Fmax Summary" vg93.sta.rpt | tail -2
grep -E "^; Worst-case Setup Slack|Setup.*sysclk" vg93.sta.rpt | head -3 || true
