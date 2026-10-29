#!/bin/bash
set -e
mkdir -p build
iverilog -g2005 -o build/sim_fdd tb_fdd_virtual.v ../rtl/vg93/fdd_virtual.v
vvp build/sim_fdd
