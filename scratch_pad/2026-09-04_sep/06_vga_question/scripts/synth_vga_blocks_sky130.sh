#!/bin/bash
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
cd /tmp/arm16-work/vga
printf "%-14s %-6s %-6s %-11s %-11s %-8s\n" block cells flops synth_um2 placed_um2 tile_pct
for top in vga_timing vga_bitmap8 vga_seg4; do
  yosys -p "read_verilog -sv vga_timing.v vga_bitmap8.v vga_seg4.v; hierarchy -top $top; flatten; proc; memory; opt -fast; techmap; opt -fast; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > s_$top.log 2>&1
  awk -v n=$top '/sky130_fd_sc_hd__/ && !/Chip/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} /Chip area/ {a=$NF}
       END {printf "%-14s %-6d %-6d %-11.0f %-11.0f %-8.1f\n", n, c, f, a, a*1.487, a*1.487/72565*100}' s_$top.log
done
echo VGA_DONE
