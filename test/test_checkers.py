"""Negative controls for the result checks; no simulator is needed."""

from types import SimpleNamespace

import pytest

from checkers import ProtocolError, StateMismatch, check_equal, check_flags, check_protocol, positive_count


def test_state_checker_accepts_equal_values():
    check_equal(0x1234, 0x1234, "r1")
    check_flags(0b1010, 0b1010)


def test_state_checker_rejects_one_changed_register():
    with pytest.raises(StateMismatch, match="r1"):
        check_equal(0x1234, 0x1235, "r1")


def test_flags_checker_reports_binary_values():
    with pytest.raises(StateMismatch, match="got 1010, expected 1000"):
        check_flags(0b1010, 0b1000)


@pytest.mark.parametrize("value", ["0", "-1", "bad", "1.5", None])
def test_random_count_rejects_empty_or_invalid_runs(value):
    with pytest.raises(ValueError, match="ARM16_RANDOM_COUNT must be a positive integer"):
        positive_count(value, "ARM16_RANDOM_COUNT")


@pytest.mark.parametrize("value,expected", [("1", 1), ("200", 200)])
def test_random_count_accepts_positive_values(value, expected):
    assert positive_count(value, "ARM16_RANDOM_COUNT") == expected


def test_protocol_failure_is_not_a_state_mismatch():
    check_protocol(SimpleNamespace(errors=[]))
    with pytest.raises(AssertionError, match="protocol errors") as caught:
        check_protocol(SimpleNamespace(errors=["both chips selected"]))
    assert not isinstance(caught.value, StateMismatch)


@pytest.mark.parametrize("failed_model", range(4))
def test_protocol_checker_checks_each_model_including_bus(failed_model):
    models = [SimpleNamespace(errors=[]) for _ in range(4)]
    check_protocol(*models)
    models[failed_model].errors.append("ownership conflict")
    with pytest.raises(ProtocolError, match="ownership conflict"):
        check_protocol(*models)
