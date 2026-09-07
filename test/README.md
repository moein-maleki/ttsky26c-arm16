# ARM16 verification

The tests check the instruction subset, pipeline, memory protocol, reset recovery and video output.
The powered-netlist checks use the public pins and the shipped ROM. The software model and GNU ARM
assembler supply independent instruction and result checks.

## Tools

Use Python 3.12, Icarus 12, GNU ARM binutils and the packages in `requirements.txt`. Gate tests also
need sky130A `8afc8346a57fe1ab7934ba5a6056ea8b43078e71`; set `PDK_ROOT` to its parent directory.
The CI jobs install these tools. Use a separate local virtual environment for Python packages.

## Required profiles

Run from the repository root. Use a new output directory for each run. The runner copies test inputs
under `/tmp`, saves their hashes and an archive, and checks that the test did not change them.

```bash
python scripts/run_verification.py software --output /tmp/arm16-results/software
python scripts/run_verification.py rtl --output /tmp/arm16-results/rtl
python scripts/run_verification.py rom --output /tmp/arm16-results/rom
python scripts/run_verification.py dead-rom --output /tmp/arm16-results/dead-rom
python scripts/run_verification.py gate --output /tmp/arm16-results/gate \
  --netlist runs/wokwi/final/pnl/tt_um_moein_maleki_arm16.pnl.v
```

- `software`: encoder, model, all flag states, GNU comparison, model lifecycle, and result/signoff checkers.
- `rtl`: the writable test ROM, all directed pipeline programs, hazard checks, and flash protocol tests.
- `rom`: the actual shipped ROM and all directed flash programs. The output must advance with both
  forwarding settings, and its displayed retirement meter must have the expected ratio.
- `dead-rom`: a separate private build replaces the ROM with an endless branch. The same visible-progress
  check must reject it. The positive build never uses this replacement.
- `gate`: the powered netlist, all directed flash programs, the real-ROM pin proof and persistent-memory
  reset tests. Hierarchy-only RTL tests have explicit skips and pin-based counterparts.

The profiles and permitted skips are in `coverage.json`. A missing required case, an unexpected skip,
an empty run, a failure element or a nonzero process exit fails the profile. The software profile must
run every collected test; external pytest and cocotb filters are removed. Random tests use seed 2026,
200 ROM programs and 40 flash programs. Pass `--seed` to select another reproducible campaign.

## Focused debugging

The Makefile remains available for focused checks. It uses a native 25 MHz testbench clock. Waves are
disabled by default because full gate-ROM proof simulates millions of cycles. Enable them explicitly:

```bash
cd test
make ROMTEST=yes WAVES=1 COCOTB_TEST_FILTER=test_stream_sequence
```

This writes `tb.fst`. Cocotb filters match qualified names and can select tests that are normally
skipped. A focused run does not replace a complete profile.

## Evidence

Each profile saves `run.log`, `results.xml`, `cases.json`, `status.json`, `input_manifest.json`,
`inputs.tar.gz` and its command record. The software profile also saves the full collection. CI uploads
these files for every profile, including failed runs. A fresh hardening run must pass the nine-corner
signoff checker and replay the gate profile before its artifacts are accepted.
