# Lessons

Carried from the lab repository and the earlier TinyTapeout designs; only what is not derivable from the code.

- Measure area by synthesizing the whole design flattened. Per-module sums double-count nested instances and
  modules without observable outputs synthesize to nothing.
- Count sequential cells with `df|edf|sdf|dl`; a `df|dl` pattern misses enable flops and under-reports tenfold.
- Measure combinational depth with `ltp -noff` before liberty mapping; after `dfflibmap` it reports nonsense.
- A 15-word two-read-port register file costs about four times its flop count in cells; it is the area floor.
- Three architectural area predictions were wrong in one week until synthesized. Predict nothing; measure.
- `matches` is a SystemVerilog keyword under icarus `-g2012`; do not use it as an identifier.
- Run cocotb from `source ~/oss-cad-suite/environment`; cocotb 2.x cancels clocks started inside a test, so
  start one clock per test.
- Yosys formal treats `dut.sig` references as implicit one-bit wires; use verification taps and a negative test.
- Gate-level netlists need mid-cycle sampling; set `PDK_ROOT` and copy the powered netlist to
  `test/gate_level_netlist.v`.
- `tt_tool.py --harden` needs a git remote configured.
- Kill background jobs from a separate command with a bracket pattern (`pkill -f 'name[.]py'`); a plain
  pattern in a command that also contains launch lines kills the calling shell.
- The lab ALU declares its operands `signed`; the carry flag is wrong on some sums and inverted on
  subtraction. The mechanical 32-to-16 narrowing left `alu_result[31]` in the N and V logic. Audit every flag.
- The lab's branch immediate is a byte offset from PC + 4, unshifted; standard assembler output does not run
  on it. Decide encoding before writing tests.

## RTL sprint, 2026-09-06

- A falling-edge status register lets an ADCS or SBCS recompute with its own carry before EX/MEM captures
  it (the ALU is combinational on the same flags). Snapshot the flags into ID/EX, or write them on the
  rising edge and bypass into decode. Review found the half-period path the falling edge also creates.
- Measured RTL from a probe is not simulated RTL: the VGA renderer's glyph was one pixel ahead of its sync
  window because `lit` used the live counter while `active` was registered. A pixel-exact frame capture
  against an independent Python render finds this in one run.
- Compare retired-instruction counts with the model on every run; it is the one check that sees a
  phantom bubble (the old ANDEQ defect) when the register values happen to agree.
- The synthesis estimate x1.487 held (34,980 um^2 became 53,678 um^2 of cells at 74% utilization). Four
  separate adders in an ALU cost 150 cells; three barrel shifters cost 90; a separate IF/ID register beside
  the delivered word cost 48 flops. Measure after each block, as the plan said.
- cocotb models that live across runs keep driving the pins: cancel every model coroutine at the end of a
  run, or a sweep compares the DUT against a crowd of stale drivers.
- A program that ends with `B .` before an appended epilogue never reaches the epilogue: strip the
  self-branch before appending.
- `COCOTB_TEST_MODULES` in the template Makefile is a plain assignment; override it on the make command line,
  not in the environment. `COCOTB_TEST_FILTER` is passed unquoted, so no `|` or parentheses.
- The dialect checker's public-signal closure follows only the top's `assign` statements: every pin-facing
  unit must live inside the datapath, and a top may hold only the controller, the datapath and units whose
  ports are named `clk`, `rst` or `rst_n`.
- `check_signoff.py` gates setup, hold, DRC, LVS and antenna; it does not gate the STA design-rule counts
  (max slew, fanout, cap). Read them from `metrics.json` and decide.

## Gate level and the push, 2026-09-06

- A cocotb model must read every control pin through a resolver that returns None on X or Z. At gate level a
  BAD strap setting carries the models' X window into a chip select; `int()` on the X raises inside the
  model's coroutine, cocotb 2 cancels the test in the ReadOnly phase, and the cleanup write then raises the
  phase error that hides the cause. Record the X as a protocol error and let `check()` fail.
- The STA design-rule counts at signoff come from the routed `fanoutN` buffer trees at the ss corner and from
  CTS leaf buffers over the fanout limit; the SDC is not the cause (the stock SDC gave the same counts).
  Raising the repair-design margins to 50% on a 75% design does not converge (34 GB after nine minutes).
  Decide on the counts from `checks.rpt`; do not expect a config knob to remove them.
- Icarus 14 with the cocotb 2.1 development build segfaults at teardown after the summary table, so make
  deletes `results.xml` in every local run; the summary table is the local verdict. The CI's own
  `results.xml` is the only one that exists.
- Docker cannot see the session scratchpad under the sandboxed `/tmp`; a clone for an isolated harden must
  live under the home directory.
- `tt/precheck` needs `gdstk` and a native `magic`; neither is installed, so the CI precheck job is the gate.
