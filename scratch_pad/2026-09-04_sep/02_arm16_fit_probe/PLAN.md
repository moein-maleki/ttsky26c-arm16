# arm16 on TinyTapeout — forward plan

> Written at close on 2026-09-04. This is the next session's top goal, in the user's words: work on this
> and harden it. The probe in this folder proved the area fits (64.9% utilization, see `REPORT.md`). Nothing
> here is verified yet. The user's purpose is fixed and should govern every choice: learn the RTL-to-GDSII
> flow end to end, produce a chip that works and that a stranger can watch working, and be able to write
> about the process before and after the boards arrive.

## Design brief (agreed with the user)

- 16-bit datapath, five-stage pipeline, forwarding, hazard detection, condition codes, barrel shifter, full
  32-bit ARM instruction decode. Every feature of `arm-cache` except the cache.
- Instructions stored as two consecutive 16-bit words in an external QSPI flash; data in the QSPI PSRAM on the
  same Pmod; serial fetch is accepted. QSPI takes 7 of the 8 bidirectional pins.
- Something observable on the 8 output pins with no host attached: at least the program counter, better a
  program that drives the demo board's seven-segment display or an LED pattern.
- It must work. Clock target 20 to 25 MHz, not 40 (longest path is 56 gate levels against 19 for logos).

## Decisions the next session must take first

1. **Shuttle.** TTSKY26c closes 2026-09-07 20:00 UTC and the user holds a 2x2 tile there. TTSKY26d opens for
   December. A functional, tested, hardened, gate-level-clean core in three days is possible only with total
   focus and no scope growth; the honest default is 26d unless the user chooses to sprint.
2. **Repository name.** Per the umbrella convention: clone `TinyTapeout/ttsky-verilog-template` into
   `designs/tt<shuttle>-<name>/` (suggested `arm16`), copy the probe RTL from `rtl/` here, and promote this
   folder's reports into that repo's `scratch_pad/`. Never hand-roll the harness.

## Checklist

- [ ] Choose shuttle and repo name; create the design repo from the template; copy `rtl/` in; commit.
- [ ] Make the 16-bit narrowing correct: audit every substituted width, the PC, immediates, shifter and
      condition logic; bring the five defect regressions from `02_rtl_correctness_fixes` across.
- [ ] Write a cocotb QSPI flash/PSRAM model and a golden Python model of the core; assemble a small test
      program with a real assembler (or a tiny custom one) and store it as 16-bit word pairs.
- [ ] Pass: directed tests, the regression set, a program run end to end in RTL simulation.
- [ ] Add the observable output path and a demo program (seven-segment counter or LED pattern).
- [ ] Harden per memory `ttsky26c-hardening-guardrails`: regenerate user config, harden at 20 to 25 MHz,
      assert the top module, check setup and hold across nine corners, DRC, LVS, antenna; snapshot metrics.
- [ ] Gate-level cocotb on the powered netlist (`PDK_ROOT` set, netlist copied to `test/gate_level_netlist.v`).
- [ ] `docs/info.md` datasheet, README, umbrella index row; write the process log the user wants to post.
- [ ] If tight on area: single 32-bit instruction copy, shared QSPI registers (about 15% together).

## Rules

Measure, do not estimate: three architectural predictions were wrong this week until synthesized. Every
session artifact goes under `scratch_pad/<date>/<xx>_<feature>/` with PLAN, REPORT, INFRA_AND_COMMANDS,
evidence and scripts. No push without the user. No AI attribution.

### 2026-09-06 progress
Superseded. The shuttle and repository decisions are taken (TTSKY26c, `designs/ttsky26c-arm16`), the memory
is decided (`03_memory_options`), and the checklist above now lives in `tasks/todo.md` and `docs/spec.md`
v0.3. The probe RTL in `rtl/` remains the starting point for the RTL task and carries the defects listed in
`04_spec/REPORT.md` and `03_memory_options/REPORT.md`.
