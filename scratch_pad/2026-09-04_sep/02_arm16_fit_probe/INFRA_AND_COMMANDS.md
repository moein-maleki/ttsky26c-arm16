# 02_arm16_fit_probe: infra and commands

## Where it ran

Local machine, `sandbox/computer-architecture-lab` at `cc1fd9c`. Tools from `source ~/oss-cad-suite/environment`
(Yosys 0.67, ABC). Liberty: `~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib`.
The probe was built in the session scratch area and copied here; `rtl/` is the complete source set.

## How the probe was made

1. Copied the synthesizable modules of `arm-cache/` (not `arm.v`, the testbenches, `sram_model.v`,
   `cache_controller.v`, `sram_controller.v`).
2. `sed -i 's/\[31:0\]/[15:0]/g' *.v`, then restored the six instruction-carrying declarations to `[31:0]`
   (`instruction_in`/`instruction_out` in `ID_stage.v`, `IF_stage_reg.v`; `if_out_instruction`,
   `id_in_instruction` in `arm_processor.v`) and narrowed the datapath literals (`32'b0`, `32'd4`,
   `32'd1024`, `32'h0000_0001`, `32'bx`).
3. Rewrote `IF_stage.v` (16-bit PC, external instruction with ready handshake), `MEM_stage.v`
   (request/ready memory port, no cache), added `qspi_master.v` and the pin wrapper `arm16_top.v`, and
   rewired `arm_processor.v` to the new ports (python replace, no `sram` references remain).

## Commands

```bash
source ~/oss-cad-suite/environment
LIB=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71/sky130A/libs.ref/sky130_fd_sc_hd/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
cd scratch_pad/2026-09-04_sep/02_arm16_fit_probe/rtl

# whole design, flattened (the number that counts)
yosys -p "read_verilog -sv *.v; synth -top arm16_top -flatten; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean -purge; stat -liberty $LIB" > ../evidence/synth_flat.log
awk '/sky130_fd_sc_hd__/ {c+=$1} /sky130_fd_sc_hd__(df|edf|sdf|dl)/ {f+=$1} END {print "cells",c,"flops",f}' ../evidence/synth_flat.log
grep 'Chip area' ../evidence/synth_flat.log | tail -1          # x1.487 = placed estimate; /72565 = utilization

# per-module breakdown (register_file is nested inside ID_stage; do not sum both)
for m in register_file qspi_master IF_stage ID_stage EXE_stage alu val2_generator; do
  yosys -p "read_verilog -sv *.v; hierarchy -top $m; flatten; proc; memory; opt -fast; techmap; opt -fast; dfflibmap -liberty $LIB; abc -liberty $LIB; opt_clean; stat -liberty $LIB" > ../evidence/s_$m.log 2>&1; done

# combinational depth, measured BEFORE liberty mapping so flip-flops break paths
yosys -p "read_verilog -sv *.v; synth -top arm16_top -flatten; abc -g AND,NAND,OR,NOR,XOR,XNOR,MUX; opt_clean; ltp -noff" | grep length=
```

## Artifacts

- `rtl/`: the 20 probe sources. Unverified; structurally faithful for area only.
- `evidence/synth_flat.log`: 3,403 cells, 616 flops, 31,668 um^2 synthesis area.
- `evidence/s_*.log`: per-module runs. `evidence/depth.log`: 56 gate levels.
- `REPORT.md`: the findings and the fit verdict (64.9% utilization estimated).

## How to verify

Re-run the first block; expect 3,403 cells and a chip area of about 31,668 um^2. Re-run the depth line;
expect `length=56`. Running `ltp` after `dfflibmap` walks through mapped flip-flops and reports about 578,
which is meaningless; measure depth before mapping.
