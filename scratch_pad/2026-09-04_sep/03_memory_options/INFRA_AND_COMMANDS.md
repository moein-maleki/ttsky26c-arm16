# 03_memory_options: infra and commands

## Where it ran

Local machine, `sandbox/computer-architecture-lab` at `9e731fa`, 2026-09-04. Tools from
`source ~/oss-cad-suite/environment` (Yosys 0.67, ABC). Liberty:
`~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib`.
Web research by six background agents, waves of six, about one request every two seconds per agent.

## What was done

1. Six research agents, one question each: demo-board hardware (schematic netlist traced), QSPI Pmod spec
   (BOM plus datasheets), TinyQV prior art, other TT external-memory projects, QSPI part timing, and the RP2
   as a memory server. Their reports are in `evidence/agent_*.md`, verbatim.
2. Baseline synthesis of the 02 probe reproduced (`evidence/repro_baseline.log`).
3. A streaming QSPI master written (`rtl_variants/qspi_master_streaming.v`) with the official Pmod pin map, a
   true 24-bit byte address, and chip select held low across sequential fetches. Synthesized alone and inside
   the whole design (`rtl_variants/full_streaming/`).
4. A fetch-latency model (`fetch_latency_model.py`) with datasheet cycle counts, the 33 MHz pad rating and the
   20 ns mux round trip as inputs.

## Commands

```bash
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
D=scratch_pad/2026-09-04_sep

# 1. reproduce the 02 baseline (expect 3,403 cells, 616 flops, 31,667.9 um^2)
cd $D/02_arm16_fit_probe/rtl
yosys -p "read_verilog -sv *.v; synth -top arm16_top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > ../../03_memory_options/evidence/repro_baseline.log
awk '/sky130_fd_sc_hd__/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} END {print "cells",c,"flops",f}' ../../03_memory_options/evidence/repro_baseline.log

# 2. the two QSPI masters in isolation (expect 529/127 and 696/158 cells/flops)
cd $D/03_memory_options
for v in "02_arm16_fit_probe/rtl/qspi_master.v qspi_master qspi_baseline" \
         "03_memory_options/rtl_variants/qspi_master_streaming.v qspi_master_streaming qspi_streaming"; do
  set -- $v
  yosys -p "read_verilog -sv ../$1; hierarchy -top $2; flatten; proc; memory; opt -fast; techmap; opt -fast; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > evidence/$3.log 2>&1
done

# 3. whole design with the streaming master and the official pin map (expect 3,517 cells, 642 flops, 32,697.6 um^2, depth 57)
cd $D/03_memory_options/rtl_variants/full_streaming
yosys -p "read_verilog -sv *.v; synth -top arm16_top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > ../../evidence/synth_flat_streaming.log
yosys -p "read_verilog -sv *.v; synth -top arm16_top -flatten; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; ltp -noff" | grep length=

# 4. the latency model
cd $D/03_memory_options && python3 fetch_latency_model.py | tee evidence/fetch_latency_model.out
```

Placed estimate = synthesis area x 1.487; utilization = placed / 72,565 um^2 (2x2 core).

## Artifacts

- `evidence/agent_demo_board_hardware.md`: board v3 (RP2350B), netlist trace proving the on-board flash is
  unreachable, full pin-to-GPIO table, Pmod socket pinout.
- `evidence/agent_qspi_pmod_spec.md`: Pmod BOM, pin map, cycle counts per transaction, max clocks, tCEM,
  purchase status, TinyQV reference controller interface.
- `evidence/agent_qspi_part_timing.md`: datasheet timing, worked latencies, the 33 MHz pad rating and 20 ns
  mux round trip, sampling-phase analysis.
- `evidence/agent_rp2_memory_server.md`: PIO responder ceilings, existing projects, failure modes, the
  3.1x to 8.2x comparison, precedent.
- `evidence/agent_tinyqv_prior_art.md`, `evidence/agent_tt_project_survey.md`: prior art (added when the
  agents reported).
- `evidence/repro_baseline.log`, `qspi_baseline.log`, `qspi_streaming.log`, `synth_flat_streaming.log`.
- `evidence/fetch_latency_model.out`: the model's table.
- `rtl_variants/qspi_master_streaming.v`: area probe only, not simulated.
- `rtl_variants/full_streaming/`: the 02 probe with the streaming master and a corrected top; area probe only.
- `REPORT.md`: findings and the recommendation. `PLAN.md`: what the design must now include.

## How to verify

Run block 1 and expect 3,403 cells. Run block 3 and expect 3,517 cells and `length=57`. Run block 4 and expect
the flash streaming row to read 8 SCK cycles per 32-bit fetch at both clock ratios. The agent reports carry
their own sources; the two netlist claims (flash unreachable, Pmod pin map) can be re-traced with
`kicad-cli sch export netlist` on `TinyTapeout/tt-demo-pcb` and `mole99/qspi-pmod`.
