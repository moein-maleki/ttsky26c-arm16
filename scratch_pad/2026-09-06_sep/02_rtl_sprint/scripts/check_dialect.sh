#!/usr/bin/env bash
# Runs the verilog-rewrite dialect checker on the design tree. The plan and the output must live outside
# the project tree, so they go to the session scratchpad; the result JSON is copied into evidence/.
set -euo pipefail
repo=/home/moein/projects/lithos/designs/ttsky26c-arm16
sprint=$repo/scratch_pad/2026-09-06_sep/02_rtl_sprint
out=${DIALECT_OUT:-/tmp/claude-1000/-home-moein-projects-lithos/73559d18-d5d6-448b-bcf2-89f0d63c3f51/scratchpad/dialect}
mkdir -p "$out"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
cp "$sprint/rewrite-plan.json" "$out/rewrite-plan.json"
set +e
/usr/bin/python3 /home/moein/.agents/skills/verilog-rewrite/scripts/check_dialect.py \
  --project "$repo" --rewrite-plan "$out/rewrite-plan.json" --output "$out/dialect_$stamp.json"
rc=$?
set -e
if [ -f "$out/dialect_$stamp.json" ]; then
  cp "$out/dialect_$stamp.json" "$sprint/evidence/dialect_$stamp.json"
  python3 - "$out/dialect_$stamp.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print("passed", d.get("passed"), "checked_files", len(d.get("checked_files", [])), "errors", len(d.get("errors", [])))
for e in d.get("errors", []):
    print("  -", e)
PY
else
  echo "checker produced no output (rc=$rc)"
fi
exit $rc
