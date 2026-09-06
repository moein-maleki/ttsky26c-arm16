# lab_copy: provenance

Fresh copy of `sandbox/computer-architecture-lab/arm-forwarding/*.v` taken on 2026-09-06 at the start of the
RTL sprint. Lab repository head `af1a532`; the five defect fixes with regressions are commit `cc1fd9c`
(2026-08-10). This copy is the reference for the decode tables, the pipeline structure, the hazard and
forwarding logic and the condition table. Nothing in it is compiled into the design: each module is
transformed into a dialect unit under `src/` (see `../PLAN.md`, Task 2).
