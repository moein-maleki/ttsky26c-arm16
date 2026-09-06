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
- [ ] User reviews sections 17 and 18 of the spec.
- [ ] Then: RTL per the spec and the checklist, synthesizing after every block.
