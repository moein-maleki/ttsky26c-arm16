# RTL correctness fixes implementation plan

> **For agentic workers:** Use test-driven development for each RTL change. Run the new tests on the unmodified source before an RTL edit.

**Goal:** Correct five pipeline and condition-code defects without a structural redesign.

**Architecture:** Add self-checking module testbenches beside each RTL version. Change only the ports and expressions that cause the defects. Keep the three version directories and the existing module names.

**Tech stack:** Verilog 2001, Icarus Verilog 13, and Verilator 5.027.

## Global constraints

- Keep the existing file structure.
- Use the existing lower snake case file names and signal names.
- Do not change the instruction memory program.
- Keep the base, forwarding, and cache versions separate.
- Store the plan, scripts, test evidence, and report in this scratch folder.
- Run the original testbenches after the new tests pass.

---

### Task 1: Add directed regression tests

**Files:**

- Create: `arm-base/bug_regression_testbench.v`
- Create: `arm-forwarding/bug_regression_testbench.v`
- Create: `arm-cache/bug_regression_testbench.v`
- Create: `scratch_pad/2026-08-10_aug/02_rtl_correctness_fixes/scripts/run_bug_regression_tests.sh`

**Test behavior:**

- Check that condition `LS` is true when `C=0` or `Z=1`.
- Check that a logical ALU operation preserves the input carry value.
- Check that a load and a branch do not request a status-register update.
- Check that a simultaneous branch and freeze loads the branch address.
- In the forwarding versions, check that only a dependent EXE load causes a forwarding-mode hazard.

- [x] Write self-checking tests with literal expected values and `$fatal` failures.
- [x] Run the tests on the unmodified source.
- [x] Save the failing output in `evidence/red_test_results.log`.
- [x] Confirm that each reported defect causes at least one failure.

### Task 2: Correct load-use hazard detection

**Files:**

- Modify: `arm-forwarding/hazard_detection.v`
- Modify: `arm-forwarding/arm_processor.v`
- Modify: `arm-cache/hazard_detection.v`
- Modify: `arm-cache/arm_processor.v`

**Interface:**

- Replace the late `mem_mem_r_en_in` hazard input with `exe_mem_r_en_in`.
- Connect the input to `exe_out_mem_r_en`.
- Assert a forwarding-mode hazard only when the EXE load destination matches a used ID source.

- [x] Apply the minimal interface and expression changes.
- [x] Run the two forwarding hazard tests.
- [x] Confirm that dependent loads stall and independent loads do not stall.

### Task 3: Correct branch, flag, carry, and condition behavior

**Files:**

- Modify: `arm-base/IF_stage.v`, `arm-forwarding/IF_stage.v`, `arm-cache/IF_stage.v`
- Modify: `arm-base/ID_stage.v`, `arm-forwarding/ID_stage.v`, `arm-cache/ID_stage.v`
- Modify: `arm-base/alu.v`, `arm-forwarding/alu.v`, `arm-cache/alu.v`
- Modify: `arm-base/condition_check.v`, `arm-forwarding/condition_check.v`, `arm-cache/condition_check.v`

**Behavior:**

- Give an EXE branch priority over a freeze when the PC register loads its next value.
- Permit a status-register update only for a data-processing instruction with `S=1`.
- Set the combinational carry output to `sr_bit_C_in` before the ALU case statement.
- Use `(~C) | Z` for the `LS` condition.

- [x] Apply the minimal RTL changes to all three versions.
- [x] Run all new directed tests.
- [x] Save the passing output in `evidence/green_test_results.log`.

### Task 4: Run regression and static checks

**Files:**

- Use: `scratch_pad/2026-08-10_aug/01_hdl_architecture_audit/scripts/run_verilog_checks.sh`
- Use: `scratch_pad/2026-08-10_aug/01_hdl_architecture_audit/scripts/run_verilator_lint.sh`
- Create: `scratch_pad/2026-08-10_aug/02_rtl_correctness_fixes/findings/rtl_correctness_report.md`

- [x] Run the original five simulations and three wrapper builds.
- [x] Run Verilator lint and check the carry-latch result.
- [x] Ask parallel reviewers to inspect the pipeline changes and the test coverage.
- [x] Check every finding against source line locations.
- [x] Record commands, results, limits, and residual risks in the report.
- [x] Update `tasks/todo.md` with the final review.
