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
| 4 engine, models, bus tests | in progress | see below |
| 5 UART, docs | UART cut (D13); docs v0.4 and info.md written | |
| 6 harden | done twice, signoff clean | `evidence/harden_20260906T093*` (defaults) and `evidence/harden_20260906T094153Z` (SDC) |
| 7 gate level | pending | |
| 8 precheck, review 4 | pending | |
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

Run 1's worst path was the negedge SCK copy flop to `uio_out[3]` (22.3 ns arrival against a 31.75 ns
requirement). Run 2's worst path is an input pin path under the 26 ns external delay. The STA report of
run 1 showed `ui_in[2]` reaching the video pins combinationally (UART_EN through the pin mux); UART_EN is
now registered, so no input reaches an output without a flop. The 1.487 placed-over-synthesis factor
held: 34,980 um^2 synthesized became 53,678 um^2 of standard cells (x1.53) at 73.97% utilization.
