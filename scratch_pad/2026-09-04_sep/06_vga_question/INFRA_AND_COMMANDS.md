# 06_vga_question: infra and commands

Local machine, 2026-09-05, `source ~/oss-cad-suite/environment`, sky130_fd_sc_hd tt_025C_1v80 liberty.

```bash
bash scripts/synth_vga_blocks_sky130.sh    # synthesizes vga_timing, vga_bitmap8, vga_seg4 flattened; logs to evidence/
```

Expect vga_timing 90 cells / 23 flops / 1.8% of the tile, vga_seg4 306 / 59 / 5.2%, vga_bitmap8 424 / 116 / 9.8%.
The renderers are area probes, not simulated; the TinyVGA pin order is applied in the spec, not in these files.
