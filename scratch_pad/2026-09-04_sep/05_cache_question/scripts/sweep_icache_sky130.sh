#!/bin/bash
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
cd /tmp/arm16-work/icache
printf "%-10s %-6s %-6s %-12s %-12s %-8s\n" lines cells flops synth_um2 placed_um2 tile_pct
for cfg in "4 2" "8 3" "16 4" "32 5" "64 6"; do
  set -- $cfg
  yosys -p "read_verilog -sv icache_dm.v; chparam -set LINES $1 -set IDX $2 icache_dm; hierarchy -top icache_dm; flatten; proc; memory; opt -fast; techmap; opt -fast; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > s_$1.log 2>&1
  awk -v n=$1 '/sky130_fd_sc_hd__/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} /Chip area/ {a=$NF}
       END {printf "%-10s %-6d %-6d %-12.0f %-12.0f %-8.1f\n", n, c, f, a, a*1.487, a*1.487/72565*100}' s_$1.log
done
echo ICACHE_DONE2
