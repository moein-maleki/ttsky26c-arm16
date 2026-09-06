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
