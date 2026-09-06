# 04_spec: infra and commands

Local machine, design repo, 2026-09-04 to 2026-09-06. Tools from `source ~/oss-cad-suite/environment`.

The one simulation in this folder checks the probe ALU's flags against ARM expectations:

```bash
source ~/oss-cad-suite/environment
cd /tmp/aluchk && cp ../02_arm16_fit_probe/rtl/alu.v .
# testbench as in evidence/alu_flag_check.log: eight vectors, ADD and SUB, N Z C V compared with ARM
iverilog -g2012 -o tb.vvp tb.v alu.v && vvp -n tb.vvp | tee evidence/alu_flag_check.log
```

Expect every vector to print MISMATCH: N and V are X (bit 31 of a 16-bit result), C is inverted on subtraction
and wrong on 0xFFFF + 1. Artifacts: `REPORT.md` (decoder audit), `evidence/alu_flag_check.log`, and the spec
itself at `docs/spec.md`.
