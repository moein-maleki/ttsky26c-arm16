# ttsky26c-arm16 tasks

> **File:** `tasks/todo.md`. **Created:** 2026-09-04 (repository scaffolded from the TinyTapeout template; spec written for review). **Open tasks:** 8. **Priority:** P1 highest, P4 parking.
> Session history lives in the project journal; the board is `tasks/STATE.md`.

## Constraints

- Purpose: learn the RTL-to-GDSII flow end to end and ship a chip that works and can be watched with no host. Demonstrability and first-try closure outrank novelty.
- Shuttle TTSKY26c, 2x2 tile, closes 2026-09-07 20:00 UTC. No scope growth.
- Memory: the TinyTapeout QSPI Pmod, flash for code, PSRAM A for data, streamed EBh fetch, no volatile chip mode.
- Area cap 72% at the synthesis estimate. Measure after every feature. Do not estimate.
- No push without the user. No AI attribution anywhere.

## Open tasks

#### P1 · 2026-09-05 · Review the specification
`docs/spec.md` v0.1. The six decisions in section 17 change the RTL; the three questions in section 18 need the user. No RTL before this is agreed.

#### P1 · 2026-09-05 · Write the RTL to the spec
Core from the probe RTL with every narrowed width audited; ARM-standard branch, load/store direction, BL, r15 semantics; ALU flags rewritten; streaming QSPI controller from `tinyQV/cpu/qspi_flash.v` with the sampling delay and falling-edge SCK; peripheral decode, DISP, SW, HEXDISP, hardware view, UART. Checklist: `scratch_pad/2026-09-04_sep/03_memory_options/PLAN.md`. Synthesize after each block; stay under 72%.

#### P1 · 2026-09-05 · Golden model, assembler, memory models
Python ARM-subset simulator from the ARM definition; Python encoder for the subset (cross-check against `arm-none-eabi-as` when installed); cocotb models of the W25Q128JV and APS6404L from the datasheets in `scratch_pad/2026-09-04_sep/03_memory_options/evidence/`.

#### P1 · 2026-09-06 · Verification to the "works" list
Spec section 14: directed tests per class with flags, the five lab regressions re-encoded, random-program differential, UART loopback, ROM boot, hardware view, demo program end to end.

#### P1 · 2026-09-06 · Harden at 25 MHz and pass gate level
Per the `ttsky26c-hardening-guardrails` note: regenerate user config, harden, assert the top module, nine corners, DRC, LVS, antenna, snapshot metrics, gate-level cocotb on the powered netlist. TinyQV's SDC.

#### P2 · 2026-09-06 · Demo program and internal ROM
A counting program for the digit; measure the 16-instruction ROM and include it if under the cap; the datasheet page `docs/info.md`; umbrella index row.

#### P3 · 2026-09-07 · Push, CI, submit
Create the GitHub repository, push, confirm test, docs and GDS workflows green, submit the 2x2 on the portal.

#### P3 · 2026-09-07 · Order one QSPI Pmod; write the process post
store.tinytapeout.com, 20 EUR. Bring-up notes are in spec section 15 and 16.

## Completed

### Scaffold and specification (2026-09-04)
- [x] Repository created from `TinyTapeout/ttsky-verilog-template` with a fresh history; `tt/` submodule at the template's pin; remote set to `github.com/moein-maleki/ttsky26c-arm16` (not pushed).
- [x] Lab work promoted: the five defect fixes with regressions, the fit probe, the memory research (`scratch_pad/PROVENANCE.md`).
- [x] Decoder audit for the spec: three encoding quirks (branch offset unshifted from PC+4, direction bit ignored, BL without link), N and V read bit 31 of a 16-bit result, C computed from signed operands. `scratch_pad/2026-09-04_sep/04_spec/REPORT.md`.
- [x] `docs/spec.md` v0.1 and `info.yaml` pinout written.

## Review

Nothing verified yet beyond synthesis area. The spec is the first gate.
