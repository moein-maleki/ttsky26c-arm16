#!/usr/bin/env bash
# Verify the downloaded TinyTapeout CI artifacts of a gds run (hardening guardrails, sprint plan task 9).
# usage: verify_ci_artifacts.sh <artifact-root> <commit-sha> <gds-run-id>
set -euo pipefail
if [[ "$#" -ne 3 ]]; then
    printf 'usage: %s <artifact-root> <commit-sha> <gds-run-id>\n' "$0" >&2
    exit 2
fi
artifact_root="$1"; expected_commit="$2"; expected_run="$3"
metadata="$artifact_root/tt_submission/tt_submission/commit_id.json"
pdk="$artifact_root/tt_submission/tt_submission/pdk.json"
metrics="$artifact_root/GDS_logs/runs/wokwi/final/metrics.json"
info="$artifact_root/tt_submission/info.yaml"
precheck="$artifact_root/precheck_reports/results.xml"
for required in "$metadata" "$pdk" "$metrics" "$info" "$precheck"; do
    [[ -f "$required" ]] || { printf 'missing required artifact: %s\n' "$required" >&2; exit 1; }
done
jq -e --arg commit "$expected_commit" --arg run "$expected_run" \
    '.commit == $commit and (.workflow_url | endswith("/actions/runs/" + $run))' "$metadata" >/dev/null
jq -e '.FLOW_NAME == "LibreLane" and (.FLOW_VERSION | startswith("3.")) and .PDK == "sky130A" and
       .PDK_SOURCE == "open_pdks" and .PDK_VERSION == "8afc8346a57fe1ab7934ba5a6056ea8b43078e71"' "$pdk" >/dev/null
jq -e '
    .["timing__setup__ws"] > 0 and .["timing__hold__ws"] > 0 and
    .["timing__setup_vio__count"] == 0 and .["timing__hold_vio__count"] == 0 and
    .["timing__setup_r2r_vio__count"] == 0 and .["timing__hold_r2r_vio__count"] == 0 and
    .["route__drc_errors"] == 0 and .["magic__drc_error__count"] == 0 and
    .["design__lvs_error__count"] == 0 and .["antenna__violating__nets"] == 0 and
    .["antenna__violating__pins"] == 0 and .["route__antenna_violation__count"] == 0 and
    .["design__power_grid_violation__count"] == 0 and .["flow__errors__count"] == 0 and
    .["synthesis__check_error__count"] == 0 and .["design__lint_error__count"] == 0 and
    .["design__instance_unmapped__count"] == 0' "$metrics" >/dev/null
grep -q 'top_module:  "tt_um_moein_maleki_arm16"' "$info"
grep -q 'clock_hz:     25000000' "$info"
grep -q 'tiles: "2x2"' "$info"
! grep -q '<failure\|<error' "$precheck"
jq -r '"utilization \(.["design__instance__utilization"])  setup ws \(.["timing__setup__ws"])  hold ws \(.["timing__hold__ws"])  cells \(.["design__instance__count__stdcell"])"' "$metrics"
printf 'CI artifact verification: PASS\n'
