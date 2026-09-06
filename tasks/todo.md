# ttsky26c-arm16 tasks

> **File:** `tasks/todo.md`. **Last regenerated:** 2026-09-06 (RTL sprint paused after Codex review 2: RTL, tests, docs done; two local hardens signoff clean; CI push next). **Open tasks:** 5. **Priority:** P1 highest, P4 parking.
> Session history lives in the project journal; the board is `tasks/STATE.md`.

## Constraints

- Purpose: learn the RTL-to-GDSII flow end to end and ship a chip that works and can be watched with no host. Demonstrability and first-try closure outrank novelty.
- Shuttle TTSKY26c, 2x2 tile, closes 2026-09-07 20:00 UTC. No scope growth.
- Memory: the TinyTapeout QSPI Pmod, flash for code, PSRAM A for data, streamed EBh fetch, no volatile chip mode.
- Area cap 72% at the synthesis estimate. Measure after every feature. Do not estimate.
- No push without the user. No AI attribution anywhere.

## Open tasks

#### P1 · 2026-09-07 · Confirm the suite and the gate-level replay on the final netlist, then push and watch the CI
RTL suite: `cd test && make -B` (ROMTEST default, about 15 minutes; 46 tests). Gate level:
`bash scratch_pad/2026-09-06_sep/02_rtl_sprint/scripts/run_gate_level.sh` on the run-3 netlist (30 to 60
minutes; the band tests capture every eighth row at gate level). Then `gh repo create moein-maleki/ttsky26c-arm16 --public`,
`git push -u origin main`, watch the `test`, `docs` and `gds` workflows (`gh run watch`), download the
artifacts and run `scripts/verify_ci_artifacts.sh`. Plan Task 9 in `scratch_pad/2026-09-06_sep/02_rtl_sprint/PLAN.md`.

#### P2 · 2026-09-07 · Signoff STA design-rule counts
Harden run 2 reported 1,778 max-slew, 22 max-fanout and 15 max-cap violations on mux select nets (setup and
hold are met; the precheck does not gate them). Try `DESIGN_REPAIR_MAX_SLEW_PCT`, `DESIGN_REPAIR_MAX_FANOUT`
or `RUN_POST_GRT_DESIGN_REPAIR` in `src/config.json`, or buffer the freeze and register-address nets, and
compare with `evidence/harden_*/metrics.json`. Codex review 2, finding 1.

#### P2 · 2026-09-07 · Submit the 2x2 on the portal after the CI is green
The user's action (app.tinytapeout.com). The report names the commit to select. Order one QSPI Pmod and one
TinyVGA Pmod (store.tinytapeout.com); cut jumpers JP2 to JP9 before the first run; set the flash
quad-enable bit once at bring-up (spec 15).

#### P3 · 2026-09-07 · Codex review 3 on the final state
Reviews 1 and 2 are applied (`scratch_pad/2026-09-06_sep/02_rtl_sprint/reviews/`). A third pass on the
final netlist evidence and the CI artifacts closes plan Task 8.

#### P4 · parked · arm16 v2, two tracks (architecture exploration 2026-09-06)
Same RTL, golden model, tests and programs as v1. Track decision first. **Sky130 (TTSKY26d):** drain, self-armed continuous read with the FFh mode reset, PSRAM QPI, a strappable memory-clock ratio (1:1 with a fallback to 1:2), the retired-per-frame meter, and a ROM macro holding a 64 to 128 instruction demo program at one instruction per cycle; about 73 to 77% on a 2x2 or 47% on a 3x2. **IHP (next shuttle):** the 512x16 SRAM macro as a 128-instruction cache with a 3-cycle hit on a 3x2, continuous read, a strappable ratio. Dry runs before any RTL: a 30-line tile hardened with the forwarded clock and its generated-clock constraint; a dummy 2x2 with a generated ROM macro (TinyTapeout/sky130-rom-experiments, smunaut/tt08-rom-test) hardened and its contents extracted from the GDS; mode-aware flash and PSRAM models with a warm-reset test. Parked lower: the branch-target cache (3.5% for 11%), the latch loop buffer, the emulator data channel (needs an RP2350 firmware port), tnt's register-file macro (license), the UART (cut for area in v1). Findings: `scratch_pad/2026-09-06_sep/01_architecture_exploration/REPORT.md`.

## Completed

### RTL sprint (2026-09-06)
- [x] Software testbench: encoder, image builder, dump epilogue, reference decoder, golden model (44 pytest).
- [x] RTL in the verilog-rewrite dialect: top, controller, datapath, ten units, demo ROM; dialect checker 0 errors.
- [x] ROM-mode cocotb suite: directed per class, five lab regressions, 200 random programs both stall
      policies, retired-count check, pixel-exact frame capture, meter, hardware view.
- [x] QSPI streaming engine, flash and PSRAM models with the round-trip sweep, flash-fed tests.
- [x] Area to 71.2% of the tile (one-adder ALU, one-rotator shifter, D as the decode register, UART cut).
- [x] Two local hardens signoff clean (setup +9.49 / +6.48 ns, hold +0.107 / +0.100 ns, 73.97% / 75.16%);
      SDC after TinyQV; UART_EN registered.
- [x] Codex reviews 1 and 2 applied; spec v0.4 with section 19; docs/info.md.

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
