"""Smoke test - proves the package is importable.

This is the only test required to satisfy Milestone M1's exit criterion.
Real tests for each brain module land in their respective milestones
(see ADR-0022).
"""

import crossengin


def test_package_imports() -> None:
    """The crossengin package should be importable."""
    assert crossengin is not None


def test_version_present() -> None:
    """The package should expose a string __version__."""
    assert hasattr(crossengin, "__version__")
    assert isinstance(crossengin.__version__, str)
    assert crossengin.__version__
