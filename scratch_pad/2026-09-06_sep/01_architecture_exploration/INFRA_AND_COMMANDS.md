# 01_architecture_exploration: infra and commands

Local machine, design repo at `3a230d8`, 2026-09-06. No synthesis in this folder; the area figures are
reused from `2026-09-04_sep/02_arm16_fit_probe`, `05_cache_question` and `06_vga_question`. Two Explore
agents did the web research and two Plan agents the reviews; their reports are in `evidence/` verbatim in
substance. The cycle model is pure Python:

```bash
python3 scripts/cycle_model.py | tee evidence/cycle_model.out
```

Expect the drain F16 R40 row to read 16.0 / 33.5 / 47.5 and the on-chip forwarding row 1.0 / 1.0 / 1.0.
