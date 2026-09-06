# 02_rtl_sprint: report

> 2026-09-06. The sprint that turned spec v0.3 into RTL, tests, GDS and a CI-green repository. Plan:
> `PLAN.md` (the approved plan with its decisions D1 to D13). Commands: `INFRA_AND_COMMANDS.md`.
> Reviews: `reviews/`. Evidence: `evidence/`. This report is updated at every task boundary.

## Status by task

| Task | State | Evidence |
|---|---|---|
| 0 scaffold, baseline | done, `b92f188` | `evidence/baseline_repro.log` (3,403 cells) |
| 1 software testbench | done, `64e70ad` | 44 pytest cases |
| 2 pipeline in the dialect | done, `0a52e6b` | 34 cocotb tests, dialect 0 errors |
| 3 ROM, VGA, peripherals, meter | done, `409ba09` | frame capture pixel-exact, meter, hardware view |
| 4 engine, models, bus tests | done; RTL suite green after review 2: 51 of 52 pass in the test-ROM build (the plain-build test skips there), 14 of 14 runnable in the plain build | `reviews/codex_review_2.md`, run logs in the session scratchpad |
| 5 UART, docs | UART cut (D13); docs v0.4 and info.md written | |
| 6 harden | done three times, signoff clean; run 3 is on commit `a9bdd86` | `evidence/harden_20260906T101958Z` is the netlist to replay and push |
| 7 gate level | first replay on the run-2 netlist: stream, restart, interleave, literal load, negative test pass; the random and band tests hit the review-2 test defects; rerun pending on the run-3 netlist | `evidence/gl_run1.log` |
| 8 precheck, reviews | Codex reviews 1 and 2 applied | `reviews/` |
| 9 push, CI | pending | |

## Findings so far

- The lab's falling-edge status register let an ADCS or SBCS recompute with its own carry before EX/MEM
  captured it; fixed by a flags snapshot in ID/EX, then (review 1) the status register moved to the
  rising edge with a bypass into decode.
- The probe's VGA renderer computed the glyph one pixel ahead of its sync window; found by the
  pixel-exact frame capture.
- A 16-bit retired-per-frame meter overflows in ROM mode (about 360,000 retired per frame); METER counts
  in units of 16.
- The receive lane index of the engine was two bits wide; the trace showed the second half of every
  word overwriting the first.
- Area: the engine took the design to 80.4%; the ALU had four adders and the shifter three barrel
  shifters; with one adder, one rotator, the delivered word as the decode register and the UART
  dropped, 71.7%.

## Hardening (Task 6)

Two local LibreLane 3.0.3 runs at CLOCK_PERIOD 40 ns, PL_TARGET_DENSITY_PCT 75, clkdlybuf banned,
PL_RESIZER_SETUP_SLACK_MARGIN 0.6, signoff by `scripts/check_signoff.py` (identity, nine corners, setup
and hold counts and worst slack, Magic DRC, LVS, route DRC, antenna, cell choice).

| Run | Constraints | Time | Placed util | Std cells | Setup ws (max_ss) | Hold ws | DRC / LVS / antenna |
|---|---|---|---|---|---|---|---|
| 1 (`harden_run1.log`) | LibreLane defaults, 20% IO delay | 4m10s | 73.97% | 6,062 | +9.490 ns | +0.107 ns | 0 / 0 / 0 |
| 2 (`harden_run2.log`) | `src/arm16.sdc`: 65% IO delay on the Pmod pins, 20% on SCK, rise/fall uncertainty 2.5/2.0 ns; UART_EN registered | 6m18s | 75.16% | 6,175 | +6.479 ns | +0.100 ns | 0 / 0 / 0 |
| 3 (`harden_run3.log`, snapshot `harden_20260906T101958Z`, commit `a9bdd86`, reproducible) | same, after review 2 (tCEM recovery, d_valid on abort) | 4m23s | 74.99% | 6,126 | +6.872 ns | +0.108 ns | 0 / 0 / 0 (slew 1,969, fanout 27, cap 21: open item) |

Run 1's worst path was the negedge SCK copy flop to `uio_out[3]` (22.3 ns arrival against a 31.75 ns
requirement). Run 2's worst path is an input pin path under the 26 ns external delay. The STA report of
run 1 showed `ui_in[2]` reaching the video pins combinationally (UART_EN through the pin mux); UART_EN is
now registered, so no input reaches an output without a flop. The 1.487 placed-over-synthesis factor
held: 34,980 um^2 synthesized became 53,678 um^2 of standard cells (x1.53) at 73.97% utilization.

## Review 2 and the open items at the pause (2026-09-06)

Codex review 2 (`reviews/codex_review_2.md`): no normal-path RTL defect; four test-harness blockers and
one abnormal-path engine defect, all fixed in `a9bdd86`; one open flow item:

- **Signoff STA design-rule counts.** Harden run 2 reports 1,778 max-slew, 22 max-fanout and 15 max-cap
  violations (logos had 0/1/0 at 14% utilization). The violators are mux select pins driven by a few
  high-fanout nets (2.29 ns slew against the 0.75 ns limit at the slow corner). Setup and hold are met
  with the actual slews (+6.48 ns / +0.100 ns) and the TinyTapeout precheck does not gate these, but
  they are worth removing: next step, add `DESIGN_REPAIR_MAX_SLEW_PCT` / `DESIGN_REPAIR_MAX_FANOUT`
  settings or `RUN_POST_GRT_DESIGN_REPAIR`, or buffer the freeze and register-file address nets in RTL,
  and compare the counts and the setup slack. Not done before the pause.
- The strap windows: QSPI_DLY = 2 is the nominal setting (31 ns setup, 41 ns hold margin at a 20 ns
  round trip); 3 has 1.5 ns of hold margin at 20 ns and is the setting for longer round trips; 1 works
  only below 11 ns. Spec section 12 now says so.

Not done before the pause: the gate-level replay on the run-3 netlist (`scripts/run_gate_level.sh`,
30 to 60 minutes), the CI push (Task 9), the portal submission (the user's action).

## Gate-level replay 1 (Task 7, on the run-2 netlist, before the review-2 fixes)

`evidence/gate_level_run1_netlist2.log`, 29m17s, unit delays, mid-cycle sampling, PDK models from the
`8afc834` build. 52 tests: 41 skipped (ROM-mode and hierarchy tests are RTL-only), 7 passed, 4 failed.

| Passed on the powered netlist | Failed |
|---|---|
| stream sequence (one EBh transaction, 78 words, sixteen PSRAM stores), restart on branch, data-access interleave, flash literal load, tCEM and idle pins (136 PSRAM transactions), negative byte order, ROM-mode band (bus quiet, "0000" rendered) | delay sweep (review 2 finding 2: stale model drivers), random flash programs (finding 3: unreachable epilogue), PSRAM write and read (timeout, to re-examine), demo end to end (timeout in the done-marker wait after a 256k-cycle band capture, to re-examine) |

The replay must be repeated on the run-3 netlist with the fixed tests (`scripts/run_gate_level.sh`).

## State at the pause (2026-09-06, sprint hour 3)

- RTL suite green: 51 pass, 1 skip (test-ROM build) plus 14 pass (plain build with the shipped ROM);
  44 pytest. The delay sweep reproduces the predicted strap table exactly; 200 ROM-mode and 40 flash-fed
  random programs match the golden model; the longest PSRAM chip-select-low time in a load-heavy program is
  2,000 ns; the hard counter raises the select at about 6,040 ns with SCK and the lanes released.
- Harden 3 on commit `a9bdd86`: signoff clean, 74.99%, setup +6.87 ns, hold +0.108 ns (snapshot
  `evidence/harden_20260906T101958Z`). The test fixes after it touch only `test/`, so the RTL of that
  snapshot is the final RTL.
- Next session, in order: `bash scratch_pad/2026-09-06_sep/02_rtl_sprint/scripts/run_gate_level.sh` (the
  run-3 netlist is in `runs/wokwi/final/pnl/`; about 30 minutes; band tests capture every eighth row),
  then Task 9 (push, CI watch, artifact verification), then the portal submission.
