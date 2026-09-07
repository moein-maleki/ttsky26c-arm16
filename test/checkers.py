"""Small result checks shared by simulation and software tests."""


class StateMismatch(AssertionError):
    """A completed test produced a different state from its expected state."""


class ProtocolError(AssertionError):
    """A memory model or bus monitor recorded a protocol violation."""


def check_equal(actual, expected, label):
    if actual != expected:
        raise StateMismatch(f"{label}: got {actual!r}, expected {expected!r}")


def check_flags(actual, expected):
    if actual != expected:
        raise StateMismatch(f"flags NZCV: got {actual:04b}, expected {expected:04b}")


def positive_count(text, name):
    try:
        count = int(text)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a positive integer") from exc
    if count < 1:
        raise ValueError(f"{name} must be a positive integer")
    return count


def check_protocol(*models):
    """Protocol errors are test failures, separate from expected data mismatches."""
    for model in models:
        if model.errors:
            raise ProtocolError(f"{type(model).__name__} protocol errors: {model.errors}")
