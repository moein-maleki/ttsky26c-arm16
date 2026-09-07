import subprocess
import sys
from pathlib import Path

import pytest


CHECKER = Path(__file__).with_name('check_results.py')


def run_check(tmp_path, xml, *arguments):
    path = tmp_path / 'results.xml'
    path.write_text(xml)
    return subprocess.run([sys.executable, str(CHECKER), str(path), *arguments],
                          capture_output=True, text=True)


def test_accepts_required_pass_and_named_skip(tmp_path):
    result = run_check(tmp_path, '<testsuites><testsuite><testcase name="needed"/>'
                       '<testcase name="hierarchy_only"><skipped/></testcase></testsuite></testsuites>',
                       '--require', 'needed', '--allow-skip', 'hierarchy_only')
    assert result.returncode == 0, result.stdout + result.stderr
    assert 'PASS=1 FAIL=0 SKIP=1' in result.stdout


@pytest.mark.parametrize('xml,reason', [
    ('<testsuites/>', 'no test cases'),
    ('<root><testcase name="fake"/></root>', 'unsupported XML root'),
    ('<testsuite><testcase name="bad"><failure/></testcase></testsuite>', 'failed tests'),
    ('<testsuite><testcase name="bad"><error/></testcase></testsuite>', 'failed tests'),
    ('<testsuite><testcase name="same"/><testcase name="same"/></testsuite>', 'duplicate test'),
    ('<testsuite><testcase name="silent"><skipped/></testcase></testsuite>', 'no passing tests'),
    ('<testsuite><testcase name="ok"/><testcase name="silent"><skipped/></testcase></testsuite>', 'unexpected skip'),
])
def test_rejects_invalid_or_incomplete_evidence(tmp_path, xml, reason):
    result = run_check(tmp_path, xml)
    assert result.returncode != 0
    assert reason in result.stderr, result.stderr


def test_required_test_cannot_be_skipped(tmp_path):
    result = run_check(tmp_path, '<testsuite><testcase name="ok"/>'
                       '<testcase name="needed"><skipped/></testcase></testsuite>',
                       '--require', 'needed', '--allow-skip', 'needed')
    assert result.returncode != 0
    assert 'required test did not pass: needed' in result.stderr


def test_required_test_cannot_be_absent(tmp_path):
    result = run_check(tmp_path, '<testsuite><testcase name="ok"/></testsuite>', '--require', 'missing')
    assert result.returncode != 0
    assert 'required test did not pass: missing' in result.stderr


def test_summary_attributes_cannot_hide_case_failure(tmp_path):
    result = run_check(tmp_path, '<testsuite tests="1" failures="0">'
                       '<testcase name="bad"><failure/></testcase></testsuite>')
    assert result.returncode != 0
    assert 'failed tests' in result.stderr


def test_allow_skip_pattern_does_not_allow_missing_required(tmp_path):
    result = run_check(tmp_path, '<testsuite><testcase name="ok"/>'
                       '<testcase name="hierarchy_a"><skipped/></testcase></testsuite>',
                       '--allow-skip', 'hierarchy_*', '--require', 'gate_proof')
    assert result.returncode != 0
    assert 'required test did not pass: gate_proof' in result.stderr
