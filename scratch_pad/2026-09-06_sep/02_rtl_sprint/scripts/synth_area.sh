#!/usr/bin/env bash
# Usage: synth_area.sh <top> <log> <verilog files...>
# Prints: cells N flops F area A util U%   (util = synth area x 1.487 / 72,565 um^2, the 2x2 core)
set -euo pipefail
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
top=$1; log=$2; shift 2
yosys -p "read_verilog $*; synth -top $top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > "$log" 2>&1 || { echo "yosys failed, see $log"; exit 1; }
awk '/sky130_fd_sc_hd__/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} END {printf "cells %d flops %d ", c, f}' "$log"
grep 'Chip area' "$log" | tail -1 | awk '{a=$NF; printf "area %.0f util %.1f%%\n", a, a*1.487/72565*100}'
