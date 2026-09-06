# ttsky26c-arm16 tasks

> **File:** `tasks/todo.md`. **Last regenerated:** 2026-09-06 (/close: spec v0.3 agreed after the architecture exploration; RTL is next). **Open tasks:** 8. **Priority:** P1 highest, P4 parking.
> Session history lives in the project journal; the board is `tasks/STATE.md`.

## Constraints

- Purpose: learn the RTL-to-GDSII flow end to end and ship a chip that works and can be watched with no host. Demonstrability and first-try closure outrank novelty.
- Shuttle TTSKY26c, 2x2 tile, closes 2026-09-07 20:00 UTC. No scope growth.
- Memory: the TinyTapeout QSPI Pmod, flash for code, PSRAM A for data, streamed EBh fetch, no volatile chip mode.
- Area cap 72% at the synthesis estimate. Measure after every feature. Do not estimate.
- No push without the user. No AI attribution anywhere.

## Open tasks

#### P1 · 2026-09-07 · Write the RTL to the spec
Core from the probe RTL with every narrowed width audited; the drain stall policy with a valid/ready fetch and 0b1111 bubbles; ARM-standard branch, load/store direction, BL, r15 semantics; ALU flags rewritten; streaming QSPI controller from `tinyQV/cpu/qspi_flash.v` with the sampling delay and falling-edge SCK; peripheral decode, the VGA timing generator and four-digit renderer, SW, hardware view, the internal ROM isolated from the controller, then UART, then the meter. Checklist: `scratch_pad/2026-09-04_sep/03_memory_options/PLAN.md`. Order of work and kill criteria: `scratch_pad/2026-09-06_sep/01_architecture_exploration/REPORT.md` section 7. Synthesize after each block; stay under 72%.

#### P1 · 2026-09-07 · Golden model, assembler, memory models
Python ARM-subset simulator from the ARM definition; Python encoder for the subset (cross-check against `arm-none-eabi-as` when installed); cocotb models of the W25Q128JV and APS6404L from the datasheets in `scratch_pad/2026-09-04_sep/03_memory_options/evidence/`.

#### P1 · 2026-09-07 · Verification to the "works" list
Spec section 14: directed tests per class with flags, the five lab regressions re-encoded, random-program differential, UART loopback, ROM boot, hardware view, demo program end to end.

#### P1 · 2026-09-07 · Harden at 25 MHz and pass gate level
Per the `ttsky26c-hardening-guardrails` note: regenerate user config, harden, assert the top module, nine corners, DRC, LVS, antenna, snapshot metrics, gate-level cocotb on the powered netlist. TinyQV's SDC.

#### P2 · 2026-09-07 · Demo program in the internal ROM, datasheet page
The ROM is a must (spec section 3.5): about 15 instructions, registers written before read, an eight-deep dependent chain so the count rate changes about 2x with FWD_EN, no loads, unused entries branch to themselves; isolated from the QSPI controller. Measure it. Then `docs/info.md` and the umbrella index row.

#### P3 · 2026-09-07 · Push, CI, submit
Create the GitHub repository, push, confirm test, docs and GDS workflows green, submit the 2x2 on the portal.

#### P3 · 2026-09-07 · Order one QSPI Pmod and one TinyVGA Pmod; write the process post
store.tinytapeout.com, 20 EUR and 15 EUR. Cut the digit jumpers JP2 to JP9 before the first run. Install `binutils-arm-none-eabi` or rely on the Python encoder (spec section 18). Bring-up notes are in spec sections 15 and 16.

#### P4 · parked · arm16 v2, two tracks (architecture exploration 2026-09-06)
Same RTL, golden model, tests and programs as v1. Track decision first. **Sky130 (TTSKY26d):** drain, self-armed continuous read with the FFh mode reset, PSRAM QPI, a strappable memory-clock ratio (1:1 with a fallback to 1:2), the retired-per-frame meter, and a ROM macro holding a 64 to 128 instruction demo program at one instruction per cycle; about 73 to 77% on a 2x2 or 47% on a 3x2. **IHP (next shuttle):** the 512x16 SRAM macro as a 128-instruction cache with a 3-cycle hit on a 3x2, continuous read, a strappable ratio. Dry runs before any RTL: a 30-line tile hardened with the forwarded clock and its generated-clock constraint; a dummy 2x2 with a generated ROM macro (TinyTapeout/sky130-rom-experiments, smunaut/tt08-rom-test) hardened and its contents extracted from the GDS; mode-aware flash and PSRAM models with a warm-reset test. Parked lower: the branch-target cache (3.5% for 11%), the latch loop buffer, the emulator data channel (needs an RP2350 firmware port), tnt's register-file macro (license). Findings: `scratch_pad/2026-09-06_sep/01_architecture_exploration/REPORT.md`.

## Completed

### Scaffold and specification (2026-09-04)
- [x] Repository created from `TinyTapeout/ttsky-verilog-template` with a fresh history; `tt/` submodule at the template's pin; remote set to `github.com/moein-maleki/ttsky26c-arm16` (not pushed).
- [x] Lab work promoted: the five defect fixes with regressions, the fit probe, the memory research (`scratch_pad/PROVENANCE.md`).
- [x] Decoder audit for the spec: three encoding quirks (branch offset unshifted from PC+4, direction bit ignored, BL without link), N and V read bit 31 of a 16-bit result, C computed from signed operands. `scratch_pad/2026-09-04_sep/04_spec/REPORT.md`.
- [x] `docs/spec.md` v0.1 and `info.yaml` pinout written.
- [x] 2026-09-05: spec v0.2, the TinyVGA Pmod replaces the seven-segment digit (measured 5.2%), UART behind the mode switch, clock fixed at 25 MHz.

### Specification review (2026-09-06)
- [x] Spec reviewed through v0.2 (TinyVGA replaces the digit) and v0.3 (stall policy, ROM above UART); agreed, RTL may start.

### Architecture exploration (2026-09-06)
- [x] Forwarding and branch handling analysed with a cycle model: drain policy mandatory (30% on loops and loads); forwarding is decoration on the streamed path (0.9% of the tile) and worth 40 to 80% in ROM mode; branch prediction not worth a gate. Parallel memory needs pins the VGA holds and unported firmware. Latch caches 6 to 12% for 4 to 8 instructions. tnt's register file: dense, proven, 22% of the tile, license unresolved. A ROM macro is the one structure that runs a program at one instruction per cycle. Spec v0.3. `scratch_pad/2026-09-06_sep/01_architecture_exploration/REPORT.md`.

### Cache question (2026-09-05)
- [x] Measured: flop caches of 4 to 64 lines on sky130 (14% to 204% of the tile); the core on SG13G2 (65,780 um^2, 2.01x sky130); IHP macro sizes from the PDK LEFs; TT rules and prior art researched. No cache on sky130; cache is the IHP v2. `scratch_pad/2026-09-04_sep/05_cache_question/REPORT.md`.

## Review

Nothing verified yet beyond synthesis area. The spec is the first gate.
