# 01_architecture_exploration: what earns its cycles

> 2026-09-06. The user asked, before any RTL: do forwarding and branch handling help on this fetch-starved
> core or are they decoration; can instruction and data memory run in parallel; can a latch-based cache
> pay for itself; what did `tt_um_tnt_rf_validation` do. No code. Plan approved the same day.

- [x] Read the probe's pipeline stall and flush wiring; found it has no policy for a fetch that is not ready.
- [x] Cycle model of drain versus freeze, forwarding, continuous read, clock ratio, branch-target cache,
      on-chip program (`scripts/cycle_model.py`, `evidence/cycle_model.out`).
- [x] Research sweep: dense storage on sky130 at TinyTapeout, tnt's register file, latch RAM, ROM macros
      (`evidence/agent_dense_storage_sky130.md`).
- [x] Research sweep: parallel memory paths, restart reduction, pipelining versus multicycle
      (`evidence/agent_parallel_memory_stalls.md`).
- [x] Two planning reviews, performance-first and risk-first (`evidence/plan_review_*.md`).
- [x] User decisions: stay on TTSKY26c with the spec; the ROM outranks the UART in the drop order.
- [x] `REPORT.md`; spec v0.3; RTL rules into `03_memory_options/PLAN.md`; v2 tracks into `tasks/todo.md`.
