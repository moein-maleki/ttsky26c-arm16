#!/usr/bin/env bash
# Snapshot the signoff artifacts of runs/wokwi before any re-harden (the flow deletes runs/wokwi first).
set -euo pipefail
repo=/home/moein/projects/lithos/designs/ttsky26c-arm16
dest=$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint/evidence/harden_$(date -u +%Y%m%dT%H%M%SZ)
mkdir -p "$dest"
cd "$repo"
cp runs/wokwi/final/metrics.json "$dest/metrics.json"
cp runs/wokwi/55-openroad-stapostpnr/summary.rpt "$dest/sta-summary.rpt" 2>/dev/null || true
grep GPL-0019 runs/wokwi/28-openroad-globalplacement/openroad-globalplacement.log > "$dest/gpl-utilization.txt" 2>/dev/null || true
cp runs/wokwi/final/pnl/*.pnl.v "$dest/" 2>/dev/null || true
cp runs/wokwi/01-verilator-lint/verilator-lint.log "$dest/" 2>/dev/null || true
cp runs/wokwi/final/commit_id.json runs/wokwi/pdk.json "$dest/" 2>/dev/null || true
for c in max_ss_100C_1v60 min_ff_n40C_1v95 nom_tt_025C_1v80; do
  cp "runs/wokwi/55-openroad-stapostpnr/$c/max.rpt" "$dest/max_$c.rpt" 2>/dev/null || true
  cp "runs/wokwi/55-openroad-stapostpnr/$c/min.rpt" "$dest/min_$c.rpt" 2>/dev/null || true
done
echo "snapshot: $dest"; ls "$dest"
