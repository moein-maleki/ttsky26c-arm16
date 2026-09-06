#!/usr/bin/env bash
# Gate-level cocotb replay on the powered netlist of the last local harden (sprint plan task 7).
set -euo pipefail
repo=/home/moein/projects/lithos/designs/ttsky26c-arm16
export PDK_ROOT=/home/moein/.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71
cd "$repo"
cp runs/wokwi/final/pnl/tt_um_moein_maleki_arm16.pnl.v test/gate_level_netlist.v
source ~/oss-cad-suite/environment
cd test
GATES=yes make -B 2>&1 | tee "$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/gate_level_tests.log" | grep -E 'TESTS=|FAIL |passed|failed' | sed 's/^ *//' | cut -c1-120
cp results.xml "$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/gate_level_results.xml"
