import json
import subprocess
import sys
from pathlib import Path


CHECKER = Path(__file__).with_name("check_signoff.py")
EXPECTED_TOP = "tt_um_moein_maleki_tryte"
CORNERS = (
    "max_ff_n40C_1v95",
    "max_ss_100C_1v60",
    "max_tt_025C_1v80",
    "min_ff_n40C_1v95",
    "min_ss_100C_1v60",
    "min_tt_025C_1v80",
    "nom_ff_n40C_1v95",
    "nom_ss_100C_1v60",
    "nom_tt_025C_1v80",
)
CORNER = CORNERS[-1]


def clean_metrics() -> dict[str, object]:
    metrics: dict[str, object] = {
        "design__name": EXPECTED_TOP,
        "design__die__area": 75_602.5,
        "design__instance__area__stdcell": 54_135.7,
        "design__instance__utilization__stdcell": 0.746034,
        "timing__setup_vio__count": 0,
        "timing__hold_vio__count": 0,
        "magic__drc_error__count": 0,
        "design__lvs_error__count": 0,
        "route__drc_errors": 0,
        "route__antenna_violation__count": 0,
        "antenna__violating__nets": 0,
        "antenna__violating__pins": 0,
    }
    for corner in CORNERS:
        metrics[f"timing__setup_vio__count__corner:{corner}"] = 0
        metrics[f"timing__setup__ws__corner:{corner}"] = 1.25
        metrics[f"timing__hold_vio__count__corner:{corner}"] = 0
        metrics[f"timing__hold__ws__corner:{corner}"] = 0.10
    return metrics


def make_project(
    tmp_path: Path,
    *,
    metrics: dict[str, object] | None = None,
    info_top: str | None = EXPECTED_TOP,
    user_top: str | None = EXPECTED_TOP,
    netlist_text: str = "module clean; endmodule\n",
    create_netlist: bool = True,
) -> tuple[Path, Path]:
    project = tmp_path
    run_dir = project / "runs" / "wokwi"
    final_dir = run_dir / "final"
    final_dir.mkdir(parents=True)
    (final_dir / "metrics.json").write_text(
        json.dumps(clean_metrics() if metrics is None else metrics),
        encoding="utf-8",
    )

    info_value = "" if info_top is None else f'  top_module: "{info_top}"\n'
    (project / "info.yaml").write_text(
        f"project:\n{info_value}yaml_version: 6\n",
        encoding="utf-8",
    )

    if user_top is not None:
        src_dir = project / "src"
        src_dir.mkdir()
        (src_dir / "user_config.json").write_text(
            json.dumps({"DESIGN_NAME": user_top}),
            encoding="utf-8",
        )

    if create_netlist:
        netlist = final_dir / "pnl" / f"{EXPECTED_TOP}.pnl.v"
        netlist.parent.mkdir()
        netlist.write_text(netlist_text, encoding="utf-8")

    return project, run_dir


def run_checker(project: Path, run_dir: Path) -> subprocess.CompletedProcess[str]:
    assert CHECKER.is_file(), f"missing production checker: {CHECKER}"
    return subprocess.run(
        [sys.executable, str(CHECKER), str(run_dir), EXPECTED_TOP],
        cwd=project,
        check=False,
        capture_output=True,
        text=True,
    )


def test_missing_identity_fails(tmp_path: Path) -> None:
    metrics = clean_metrics()
    metrics.pop("design__name")

    project, run_dir = make_project(tmp_path / "missing_info", info_top=None)
    assert run_checker(project, run_dir).returncode != 0

    project, run_dir = make_project(
        tmp_path / "missing_build",
        metrics=metrics,
        user_top=None,
    )
    assert run_checker(project, run_dir).returncode != 0


def test_wrong_identity_fails(tmp_path: Path) -> None:
    metrics = clean_metrics()
    metrics["design__name"] = "tt_um_wrong_design"
    project, run_dir = make_project(
        tmp_path,
        metrics=metrics,
        user_top="tt_um_wrong_design",
    )
    assert run_checker(project, run_dir).returncode != 0


def test_timing_violation_fails(tmp_path: Path) -> None:
    metrics = clean_metrics()
    metrics["timing__setup_vio__count"] = 1
    metrics[f"timing__setup_vio__count__corner:{CORNER}"] = 1
    project, run_dir = make_project(tmp_path / "setup_violation", metrics=metrics)
    assert run_checker(project, run_dir).returncode != 0

    metrics = clean_metrics()
    metrics.pop(f"timing__hold__ws__corner:{CORNER}")
    project, run_dir = make_project(tmp_path / "missing_hold_corners", metrics=metrics)
    assert run_checker(project, run_dir).returncode != 0


def test_partial_corner_set_fails(tmp_path: Path) -> None:
    metrics = clean_metrics()
    metrics.pop(f"timing__setup__ws__corner:{CORNER}")
    project, run_dir = make_project(tmp_path, metrics=metrics)
    result = run_checker(project, run_dir)
    assert result.returncode != 0, result.stdout + result.stderr


def test_physical_violation_fails(tmp_path: Path) -> None:
    metrics = clean_metrics()
    metrics["magic__drc_error__count"] = 1
    project, run_dir = make_project(tmp_path / "drc_violation", metrics=metrics)
    assert run_checker(project, run_dir).returncode != 0

    project, run_dir = make_project(tmp_path / "missing_netlist", create_netlist=False)
    assert run_checker(project, run_dir).returncode != 0


def test_clkdlybuf_fails(tmp_path: Path) -> None:
    project, run_dir = make_project(
        tmp_path,
        netlist_text="sky130_fd_sc_hd__clkdlybuf4s25_1 bad_cell ();\n",
    )
    assert run_checker(project, run_dir).returncode != 0


def test_clean_metrics_pass(tmp_path: Path) -> None:
    project, run_dir = make_project(tmp_path)
    result = run_checker(project, run_dir)
    assert result.returncode == 0, result.stdout + result.stderr
