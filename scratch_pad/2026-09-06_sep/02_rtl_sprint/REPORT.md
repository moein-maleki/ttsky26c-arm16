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
| 7 gate level | done: on the run-3 netlist 11 of the 11 runnable tests pass (replay 2: 10 pass, the delay sweep failed on a harness gap; replay 3 after the X-safe models: the sweep passes with the predicted table) | `evidence/gate_level_run2_netlist3.log`, `evidence/gate_level_run3_netlist3_delay_sweep.log` |
| 8 precheck, reviews | Codex reviews 1 and 2 applied; the local precheck cannot run (no `gdstk`, no `magic` outside Docker), so the CI precheck job is the gate; the STA design-rule counts are dispositioned below | `reviews/` |
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

## Gate-level replays 2 and 3 (Task 7, the run-3 netlist, 2026-09-06 15:00 to 15:15 UTC)

Replay 2 (`evidence/gate_level_run2_netlist3.log`, 14 minutes): 52 tests, 41 skipped (RTL-only), 10 passed,
1 failed. The failure was `test_delay_sweep`, and its cause is in the harness, not the RTL. In a strap and
round-trip setting that the table already calls BAD (15 ns with strap 1), the models' X window passes through
the netlist to a chip select. The bus monitor's `int()` raised on the X inside its coroutine, cocotb 2
cancelled the test in the ReadOnly phase, and the cleanup write of `uio_in` then raised the phase error that the
log reports. At RTL the same setting gives a deterministic wrong value, because an `if` on X takes the else
branch, so the monitor never saw an X there.

Fix (`test/qspi_models.py`): every control-pin read goes through `resolved()`, which returns None on an X or
Z; a model then records a protocol error and releases the lanes (`_abandon`), and the monitor records the
unresolvable select. `check()` already fails on model and monitor errors, and the sweep already treats a
failing strap as a data point, so a BAD setting stays BAD without a crash. The two unused bus accessors went.

Replay 3, the sweep alone on the same netlist (`evidence/gate_level_run3_netlist3_delay_sweep.log`,
9 minutes): PASS, with exactly the predicted table (strap 1 to 10 ns, strap 2 everywhere, strap 3 from
20 ns). The RTL suite on the fixed models: 51 pass, 1 skip, the same table
(`evidence/rtl_suite_after_x_safe_models.summary.log`). Result: 11 of the 11 runnable gate-level tests pass
on the run-3 netlist of commit `a9bdd86`.

The local simulator (Icarus 14 with the cocotb 2.1 development build) exits with a segmentation fault at
teardown in every run, RTL and gate level, after cocotb prints the summary table; make then deletes
`results.xml`. The summary table is the local verdict. The CI runs Icarus 12 with cocotb 2.0.1 and reads its
own `results.xml`; whether it shows the same teardown fault is known only from the CI run.

## STA design-rule counts: disposition (the Task 6 open item)

Where the counts come from (run 3, `runs/wokwi/55-openroad-stapostpnr/max_ss_100C_1v60/checks.rpt`):

- The limits are the PDK's (`sky130_fd_sc_hd/config.tcl`): max transition 0.75 ns, max fanout 10, max
  capacitance 0.2 pF. Run 1 with LibreLane's stock SDC already had 1,793 / 25 / 20, so `arm16.sdc` is not the
  cause.
- Max slew (1,969 at max_ss, 364 at nom_tt): the loads of the `fanoutN` buffers that repair_design inserted
  after global placement (fanout116 at 2.31 ns, fanout87 at 1.98 ns, fanout89 at 1.80 ns, fanout294 and
  fanout274 at 1.7 ns, each with about ten sinks). After placement repair the nominal corner was clean (step
  36: 0 slew violations); the routed parasitics and the ss library bring them back (step 43 after global
  routing: 22; after detailed routing and extraction: 364 at nom_tt, 1,969 at max_ss).
- Max fanout (27): 25 are CTS leaf clock buffers with 11 to 16 sinks (`clkbuf_leaf_*`, `clkbuf_0_clk`), 2 are
  data fanout buffers with 11 and 12 sinks.
- Max capacitance (21): 20 are `fanoutN` buffers (buf_1) whose routed load exceeds their 0.081 pF limit by
  up to 0.045 pF; 1 is the clock root buffer at 0.209 pF against 0.2.

Experiment A (`evidence/harden_expA_slew_cap_margin50_repairdesign.log`): `DESIGN_REPAIR_MAX_SLEW_PCT` and
`DESIGN_REPAIR_MAX_CAP_PCT` raised from 20 to 50 in an isolated clone. The repair-design step, which takes
seconds at the default, was still iterating after nine minutes (3,468 nets remaining at iteration 500), with
the container at 100% CPU and 34 GB of memory; killed. Not adoptable: a step of that size cannot run on the
CI runner, and the calendar does not allow a second attempt with a gate-level rerun.

Decision: push run 3 as it is. Setup and hold are met with the actual slews at all nine corners (setup
+6.87 ns, hold +0.108 ns), the counts are not gated by the TinyTapeout precheck, the clock-tree fanout items
are CTS's own leaf buffers, and a slow edge on a mux select at 25 MHz costs delay that STA already includes.
Recorded for v2: fewer high-fanout selects in the RTL (register-file read addresses, the freeze net), or a
post-route repair when LibreLane offers a stable one.

## State before the push (2026-09-06, 15:20 UTC)

- RTL suite green: 51 pass, 1 skip (test-ROM build) plus 14 pass (plain build with the shipped ROM);
  44 pytest. The delay sweep reproduces the predicted strap table exactly; 200 ROM-mode and 40 flash-fed
  random programs match the golden model; the longest PSRAM chip-select-low time in a load-heavy program is
  2,000 ns; the hard counter raises the select at about 6,040 ns with SCK and the lanes released.
- Harden 3 on commit `a9bdd86`: signoff clean, 74.99%, setup +6.87 ns, hold +0.108 ns (snapshot
  `evidence/harden_20260906T101958Z`). The test fixes after it touch only `test/`, so the RTL of that
  snapshot is the final RTL.
- Gate level: 11 of 11 runnable tests pass on the run-3 netlist (replays 2 and 3 above); the RTL suite on the
  X-safe models is 51 pass, 1 skip. The RTL of `a9bdd86` is unchanged; this commit changes `test/` and the
  scratch_pad only, so the CI hardens the same RTL as run 3.
- Next: Task 9 (create the repository, push, watch the `test`, `docs` and `gds` workflows, verify the
  artifacts), then the portal submission (the user).
