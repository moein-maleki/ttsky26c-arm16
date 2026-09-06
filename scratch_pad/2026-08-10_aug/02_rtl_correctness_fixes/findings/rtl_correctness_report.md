# RTL correctness report

## Scope

This work corrects five findings from the architecture audit.

The original source is commit `e7a380ac02eb5941fde141f067f95f2a74981eae`.

The work keeps the three version folders and all existing module names.

The new test file in each version is `bug_regression_testbench.v`.

## Result

| Finding | Result | Main source location |
|---|---|---|
| Load-use forwarding starts too late | Corrected | `arm-forwarding/hazard_detection.v:32`, `arm-cache/hazard_detection.v:32` |
| A cache wait can discard an EXE branch | Corrected | `arm-cache/IF_stage.v:25` |
| Raw instruction bit 20 can update flags | Corrected | `arm-base/ID_stage.v:81` |
| The ALU carry output infers a latch | Corrected | `arm-base/alu.v:36` |
| ARM condition `LS` uses AND | Corrected | `arm-base/condition_check.v:46` |

The same common changes are present in the base, forwarding, and cache versions.

## Load-use correction

The old hazard input came from the load after it entered MEM.

The processor now sends `exe_out_mem_r_en` to `exe_mem_r_en_in`.

The forwarding hazard now needs all these conditions:

- Forwarding is active.
- A load is in EXE.
- The EXE destination matches a used ID source.

The hazard inserts one bubble.

The load moves to MEM while the dependent instruction stays in ID.

The load then moves to WB when the dependent instruction enters EXE.

The existing WB bypass supplies the loaded data instead of the MEM load address.

The source sites are:

- `arm-forwarding/arm_processor.v:104`
- `arm-forwarding/arm_processor.v:112`
- `arm-forwarding/hazard_detection.v:16`
- `arm-forwarding/hazard_detection.v:32`
- `arm-cache/arm_processor.v:115`
- `arm-cache/arm_processor.v:123`
- `arm-cache/hazard_detection.v:16`
- `arm-cache/hazard_detection.v:32`

The ID source-two hazard now uses the decoded source count.

This change prevents load offset bits from causing an unnecessary source-two stall.

The source sites are `arm-forwarding/ID_stage.v:74` and `arm-cache/ID_stage.v:74`.

## Branch and freeze correction

Each IF stage now gives a taken branch priority over freeze.

If a cache wait and an EXE branch occur together, the PC loads the branch target.

If the wait continues, the PC holds that target.

The PC resumes sequential operation after the wait ends.

The pipeline flush still removes the two younger instructions.

The source sites are:

- `arm-base/IF_stage.v:22`
- `arm-forwarding/IF_stage.v:22`
- `arm-cache/IF_stage.v:25`
- `arm-cache/arm_processor.v:113`

## Status-update correction

The ID stage still reads instruction bit 20.

It now permits a status update only when `instr_mode` is `2'b00`.

Loads and branches cannot update the condition flags through bit 20.

Data-processing instructions with `S=1` can still update the flags.

The source sites are:

- `arm-base/ID_stage.v:81`
- `arm-base/ID_stage.v:106`
- `arm-forwarding/ID_stage.v:86`
- `arm-forwarding/ID_stage.v:114`
- `arm-cache/ID_stage.v:86`
- `arm-cache/ID_stage.v:114`

## ALU carry-latch correction

Each combinational ALU block now assigns `sr_bit_C_out` before its case statement.

The default value is `sr_bit_C_in`.

MOV, NOP, logical operations, and unsupported commands do not retain an earlier command value.

The ALU blocks now use blocking assignments for combinational logic.

The source sites are:

- `arm-base/alu.v:36`
- `arm-forwarding/alu.v:37`
- `arm-cache/alu.v:37`

Focused Verilator lint reports no `LATCH` or `COMBDLY` warning for any ALU.

## `LS` correction

ARM `LS` is true when carry is clear or zero is set.

The three condition check modules now use `(~C) | Z`.

The source site is line 46 in each `condition_check.v` file.

## Directed RED and GREEN evidence

The final test files were copied into an isolated export of the original commit.

The tests failed on that original source:

| Version | RED failures |
|---|---:|
| `arm-base` | 9 |
| `arm-forwarding` | 13 |
| `arm-cache` | 16 |

The same tests pass on the corrected source:

| Version | GREEN checks |
|---|---:|
| `arm-base` | 16 |
| `arm-forwarding` | 21 |
| `arm-cache` | 26 |

The tracked RTL diff has this SHA-256 value:

`d378b9883f4e6c8fed9b2855bf6708f24d4451da6a2144fb6ed167d8965868bb`

The evidence files are:

- `evidence/red_test_results.log`
- `evidence/green_test_results.log`

The test runner is `scripts/run_bug_regression_tests.sh`.

## Original regression evidence

The original five simulation targets compile and reach their planned stop points.

The three board wrappers also compile.

The original processor testbenches remain smoke tests.

The evidence file is `evidence/original_regression_results.log`.

## Static check evidence

Verilator completes the base and forwarding core lint with warnings.

The cache core lint still stops at `arm-cache/cache_controller.v:112`.

Verilator does not support the array-select tristate construct at that line.

Icarus compiles and simulates the same cache controller.

Focused lint of all three ALUs exits with status 0 and reports no latch.

The evidence file is `evidence/lint_results.log`.

## Parallel review result

Three reviewers checked the final work.

One reviewer checked pipeline timing and branch priority.

One reviewer checked the tests, flag logic, and ALU behavior.

One reviewer checked file structure, names, and version consistency.

The pipeline review found one false source-two stall for ID loads.

The work now corrects that issue and includes a directed test.

No reviewer found another in-scope high-severity defect.

## Residual technical risks

The five requested findings are corrected, but the processor flags are not ARM-complete.

The ADD overflow expression reports overflow for `1 + 1`.

This defect is at line 31 or 32 in each ALU.

The arithmetic carry expressions also use a 32-bit result expression.

For example, `32'hffff_ffff + 1` does not produce carry one in the current RTL.

The operand shifter has no carry output.

Therefore, MOVS and logical flag updates cannot implement the full ARM shifter-carry rule.

These flag defects existed before this work and are outside the five approved corrections.

The load-use tests force processor boundary signals.

They prove the hazard stage, register matching, and top-level connection.

They do not run a complete load and dependent instruction program through the hard-coded instruction memory.

The cache collision test also forces cache busy and EXE branch signals.

It proves branch priority, pipeline flush, target hold, and PC resume behavior.

It does not create a cache miss from a complete instruction program.

## File and format control

The work adds one testbench to each existing version folder.

It does not rename a production module or move a production file.

New names use the repository lower snake case style.

The changed legacy RTL files keep their original CRLF line endings.

The test, script, and report files use LF line endings.

## Conclusion

The source now implements the five requested corrections.

The directed tests prove RED behavior on the original commit and GREEN behavior on the corrected source.

The original simulations and wrapper builds still run.

The residual flag defects need a separate ARM condition-code correction task.
