# 04_spec: specification before RTL

> 2026-09-04. The user asked for a clear specification of features in and out, the interaction with the
> carrier and demo boards, and the use of the chip pins, before any RTL is written.

- [x] Scaffold `designs/ttsky26c-arm16` from the TinyTapeout template with a fresh history; submodule; remote.
- [x] Promote the lab folders (defect fixes, fit probe, memory research) with a provenance note.
- [x] Audit the decoder and datapath of the probe; record the findings (`REPORT.md`).
- [x] Confirm the ALU carry defect by simulation (`evidence/alu_flag_check.log`).
- [x] Write `docs/spec.md` v0.1: features in and out, environment, pins, address map, modes, boot, area,
      timing, performance, the "works" list, tools, bring-up, decisions, open questions.
- [x] Write `info.yaml` with the pinout, `README.md`, `tasks/`.
- [x] Add the UART to the memory checklist (`03_memory_options/PLAN.md`) and to the tasks.
- [x] User reviewed the spec through two revisions: v0.2 (TinyVGA replaces the digit, 2026-09-05) and v0.3
      (stall policy, ROM above UART, 2026-09-06). Section 18's open items (install binutils, order the two
      Pmods) moved to `tasks/todo.md`.
- [x] Then: RTL per the spec and the checklist, synthesizing after every block. (Done 2026-09-06; spec v0.4 records the implementation decisions in section 19.)

### 2026-09-06 progress
Spec v0.3 is the agreed gate; RTL may start. Superseding plan for execution: `03_memory_options/PLAN.md`
(the RTL checklist) and section 9 of the architecture exploration report (the order of work).

### 2026-09-06 (later) progress
RTL written and verified; spec revised to v0.4 (section 19). This plan is complete.
