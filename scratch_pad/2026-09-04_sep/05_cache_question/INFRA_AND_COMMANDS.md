# 05_cache_question: infra and commands

Local machine, 2026-09-05. sky130 synthesis from `source ~/oss-cad-suite/environment` (Yosys 0.67); IHP
synthesis and macro LEF reads inside `hpretl/iic-osic-tools` (sha256 fd38cb07...) with `--skip` as the first
argument after the image; one research agent for the TT rules and prior art.

```bash
# flop caches of 4 to 64 lines on sky130 (do not pass -q to yosys: it suppresses the stat table)
bash scripts/sweep_icache_sky130.sh            # writes evidence/icache_*lines_sky130.log and the summary
# the core on the IHP library, and the SRAM macro sizes from the PDK LEFs
docker run --rm -v "$PWD:/work" -w /work --user "$(id -u):$(id -g)" hpretl/iic-osic-tools@sha256:fd38cb07a29d49d5f9720494cc4497cd8e8c80dfa06b4224d46447bc0f3c2ef0 --skip bash -c '
  LIB=/foss/pdks/ihp-sg13g2/libs.ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
  yosys -p "read_verilog -sv rtl_variants/full_streaming/*.v; synth -top arm16_top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB"
  for f in /foss/pdks/ihp-sg13g2/libs.ref/sg13g2_sram/lef/*.lef; do printf "%-48s " $(basename $f .lef); grep -m1 SIZE $f; done'
```

Expect 4 lines = 305 cells / 180 flops / 14.1% of the tile, 64 lines = 204%; the core on SG13G2 4,176 cells,
642 flops, 65,780 um^2; the 256x16 macro 236.80 x 118.78 um. Artifacts in `evidence/`, `rtl/icache_dm.v`,
`REPORT.md`, and the agent report `evidence/agent_ihp_sram_in_tt.md`.
