# 02_rtl_sprint: infra and commands

## Where it ran

Local machine, 2026-09-06, design repo `designs/ttsky26c-arm16` on `main`. Simulation and Yosys from
`source ~/oss-cad-suite/environment` (Icarus 14, cocotb 2.1.0.dev0, Yosys 0.67). Hardening from
`source ~/.venvs/librelane/bin/activate` (LibreLane 3.0.3, Docker 29.1.3) with
`PDK_ROOT=$HOME/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71`; `tt/` at `d65690e`.
Codex reviews through the MCP in a read-only sandbox. The dialect checker is
`~/.agents/skills/verilog-rewrite/scripts/check_dialect.py` (standalone; the baseline gate of that skill
stays blocked by the libbz2 change of 2026-09-02 and is not needed for a fresh design).

## Commands

```bash
cd designs/ttsky26c-arm16
S=scratch_pad/2026-09-06_sep/02_rtl_sprint

# software testbench (encoder, image builder, golden model, ROM consistency)
source ~/oss-cad-suite/environment && (cd test && python3 -m pytest test_software.py -q)      # 44 passed, 1 skipped

# RTL suite: ROM-mode tests on the 1,024-word test ROM plus the flash-fed tests with the memory models
(cd test && make -B)                      # ROMTEST=yes is the RTL default; about 12 minutes
(cd test && make -B ROMTEST=no)           # the shipped demo ROM: test_shipped_rom_boot only

# area (flattened, sky130_fd_sc_hd tt corner; util = area x 1.487 / 72,565)
bash $S/scripts/synth_area.sh tt_um_moein_maleki_arm16 $S/evidence/synth_final.log src/*.v

# dialect
bash $S/scripts/check_dialect.sh          # passed True, 14 files, 0 errors

# harden and sign off
source ~/.venvs/librelane/bin/activate; export PDK_ROOT=~/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
python tt/tt_tool.py --create-user-config && python tt/tt_tool.py --harden
bash $S/scripts/snapshot_harden.sh && python scripts/check_signoff.py runs/wokwi tt_um_moein_maleki_arm16

# gate level
bash $S/scripts/run_gate_level.sh

# CI artifacts after the push
gh run download <gds-run-id> -n tt_submission -n GDS_logs -n precheck_reports -D $S/evidence/ci/
bash scripts/verify_ci_artifacts.sh $S/evidence/ci <commit-sha> <gds-run-id>
```

## Measurements (synthesis estimate)

| Stage | Cells | Flops | Synth um^2 | Tile |
|---|---|---|---|---|
| Probe baseline reproduced (`evidence/baseline_repro.log`) | 3,403 | 616 | 31,668 | 64.9% |
| Task 2: pipeline, VGA, peripherals, meter, engine stub (`synth_task2.log`) | 3,350 | 583 | 29,905 | 61.3% |
| Engine landed (`synth_task4.log`) | 4,416 | 774 | 39,256 | 80.4% |
| One-adder ALU, narrowed engine registers (`synth_task4b.log`) | 4,262 | 773 | 37,772 | 77.4% |
| D as the decode register, one-rotator shifter, 14-bit branch immediate (`synth_task4c.log`) | 3,960 | 725 | 35,325 | 72.4% |
| UART divider removed (`synth_task4d.log`) | 3,977 | 709 | 34,980 | 71.7% |
