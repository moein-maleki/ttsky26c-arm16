# 05_cache_question

> 2026-09-05. Question from the user: can the design have a 256 x 16 cache from IHP single-port SRAM, any size.

- [x] Measure flop-based direct-mapped instruction caches of 4 to 64 lines on sky130 (`scripts/`, `rtl/`).
- [x] Read the IHP SRAM macro sizes from the PDK LEFs; measure the core on the SG13G2 library.
- [x] Research the Tiny Tapeout rules for IHP SRAM macros, prior art, tile geometry, ttihp26b status.
- [x] Report and recommend (`REPORT.md`): no cache on sky130; cache as arm16 v2 on the next IHP shuttle.
- [x] Record the decision in `docs/spec.md` section 4 and a parked task.
