#!/usr/bin/env python3
"""Fail a hardening run when its signoff evidence is incomplete or dirty.

Usage: check_signoff.py [run_dir] [expected_top]
Exit status: zero only when all required gates pass.
"""

import json
import pathlib
import re
import sys


RUN = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "runs/wokwi")
EXPECTED_TIMING_CORNERS = frozenset(
    {
        "max_ff_n40C_1v95",
        "max_ss_100C_1v60",
        "max_tt_025C_1v80",
        "min_ff_n40C_1v95",
        "min_ss_100C_1v60",
        "min_tt_025C_1v80",
        "nom_ff_n40C_1v95",
        "nom_ss_100C_1v60",
        "nom_tt_025C_1v80",
    }
)


def read_info_top() -> str | None:
    try:
        text = pathlib.Path("info.yaml").read_text(encoding="utf-8")
    except OSError:
        return None
    match = re.search(r"(?m)^\s*top_module:\s*[\"']?([^\"'#\s]+)", text)
    return match.group(1) if match else None


def read_user_config_top() -> str | None:
    path = pathlib.Path("src/user_config.json")
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("DESIGN_NAME")
    except (OSError, json.JSONDecodeError):
        return None


def main() -> int:
    metrics_path = RUN / "final" / "metrics.json"
    if not metrics_path.exists():
        print(f"FAIL: no metrics at {metrics_path} -- the flow did not reach signoff")
        return 1

    try:
        metrics = json.loads(metrics_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        print(f"FAIL: cannot read metrics at {metrics_path}: {error}")
        return 1

    failures: list[str] = []

    def gate(ok: bool, label: str, detail: str) -> None:
        mark = "PASS" if ok else "FAIL"
        print(f"  [{mark}] {label:34s} {detail}")
        if not ok:
            failures.append(label)

    print("=== IDENTITY ===")
    info_top = read_info_top()
    expected_top = sys.argv[2] if len(sys.argv) > 2 else info_top
    built_top = metrics.get("design__name") or metrics.get("DESIGN_NAME")
    if built_top is None:
        built_top = read_user_config_top()

    gate(info_top is not None, "info.yaml top module", str(info_top))
    gate(expected_top is not None, "expected top module", str(expected_top))
    if info_top is not None and expected_top is not None:
        gate(
            info_top == expected_top,
            "expected top matches info.yaml",
            f"expected '{expected_top}', info.yaml says '{info_top}'",
        )
    gate(built_top is not None, "built design identity", str(built_top))
    if built_top is not None and expected_top is not None:
        gate(
            built_top == expected_top,
            "built design matches expected top",
            f"built '{built_top}', expected '{expected_top}'",
        )

    print("=== TIMING ===")
    setup_violations = metrics.get("timing__setup_vio__count")
    hold_violations = metrics.get("timing__hold_vio__count")
    gate(
        setup_violations == 0,
        "setup violations, all corners",
        str(setup_violations),
    )
    gate(
        hold_violations == 0,
        "hold violations, all corners",
        str(hold_violations),
    )

    setup_slacks = {
        key.split("corner:", 1)[1]: value
        for key, value in metrics.items()
        if key.startswith("timing__setup__ws__corner:")
    }
    hold_slacks = {
        key.split("corner:", 1)[1]: value
        for key, value in metrics.items()
        if key.startswith("timing__hold__ws__corner:")
    }
    setup_corners = frozenset(setup_slacks)
    hold_corners = frozenset(hold_slacks)
    gate(
        setup_corners == EXPECTED_TIMING_CORNERS,
        "setup corner set is complete",
        f"found {len(setup_corners)} of {len(EXPECTED_TIMING_CORNERS)}",
    )
    gate(
        hold_corners == EXPECTED_TIMING_CORNERS,
        "hold corner set is complete",
        f"found {len(hold_corners)} of {len(EXPECTED_TIMING_CORNERS)}",
    )
    gate(
        setup_corners == hold_corners,
        "setup and hold corner sets match",
        f"setup {len(setup_corners)}, hold {len(hold_corners)}",
    )
    if setup_slacks:
        corner, slack = min(setup_slacks.items(), key=lambda item: item[1])
        gate(slack >= 0, "worst setup slack", f"{slack:+.3f} ns @ {corner}")
    if hold_slacks:
        corner, slack = min(hold_slacks.items(), key=lambda item: item[1])
        gate(slack >= 0, "worst hold slack", f"{slack:+.3f} ns @ {corner}")

    print("=== PHYSICAL ===")
    physical_gates = (
        ("magic__drc_error__count", "Magic DRC"),
        ("design__lvs_error__count", "LVS"),
        ("route__drc_errors", "route DRC"),
        ("route__antenna_violation__count", "route antenna"),
        ("antenna__violating__nets", "antenna nets"),
        ("antenna__violating__pins", "antenna pins"),
    )
    for key, label in physical_gates:
        value = metrics.get(key)
        gate(value == 0, label, str(value))

    print("=== AREA ===")
    stdcell_area = metrics.get(
        "design__instance__area__class:stdcell",
        metrics.get("design__instance__area__stdcell", 0),
    )
    utilization = metrics.get(
        "design__instance__utilization",
        metrics.get("design__instance__utilization__stdcell", 0),
    )
    core_area = metrics.get("design__die__area")
    if core_area is None and stdcell_area and utilization:
        core_area = stdcell_area / utilization
    core_area = core_area or 0
    print(f"         utilization                       {utilization * 100:.2f} %")
    print(
        f"         stdcell area                      {stdcell_area:.1f} um2 "
        f"({stdcell_area / core_area * 100:.1f}% of core)"
        if core_area
        else f"         stdcell area                      {stdcell_area:.1f} um2"
    )
    cells = metrics.get("design__instance__count__stdcell", 0)
    dffs = metrics.get("design__instance__count__class:sequential_cell", 0)
    print(f"         cells / DFFs                      {cells} / {dffs}")

    print("=== CELL CHOICE ===")
    netlists = list(RUN.glob("final/pnl/*.pnl.v")) + list(
        RUN.glob("final/nl/*.nl.v")
    )
    gate(bool(netlists), "final netlist exists", str(netlists[0] if netlists else None))
    if netlists:
        text = netlists[0].read_text(encoding="utf-8")
        delay_cells = len(re.findall(r"clkdlybuf", text))
        gate(
            delay_cells == 0,
            "clkdlybuf instances in netlist",
            f"{delay_cells} (banned via EXTRA_EXCLUDED_CELLS)",
        )

    print()
    if failures:
        print(f"SIGNOFF FAILED: {', '.join(failures)}")
        return 1
    print("SIGNOFF CLEAN: every gate passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
