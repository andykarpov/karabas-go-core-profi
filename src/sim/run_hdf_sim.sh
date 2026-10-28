#!/bin/bash
# Simulate tb_hdf_ata.v with iverilog.
set -e
cd "$(dirname "$0")"
mkdir -p build
iverilog -o build/tb_hdf_ata ../../modules/rtl/mcu/hdf_ata.v tb_hdf_ata.v
vvp build/tb_hdf_ata
