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
| 6 harden | first run in progress | |
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
