"""Behavior tests for the consumer-facing CI templates in ``templates/ci/``.

Each fixture under ``tests/fixtures/`` is a minimal fake consuming-repo tree
(``.claude/settings.json`` + ``.claude/canon.txt``). The templates are exercised
**verbatim** — the fixtures adapt to the templates' default knobs (the six
universal modules), never the reverse:

* jq flavor:     ``check-canon-declaration.sh`` runs with cwd = the fixture dir.
* pytest flavor: ``test_canon_adoption.py`` is copied unmodified to the documented
  depth (``<tmp>/tests/meta/``) beside a copy of the fixture's ``.claude/`` and
  run as a pytest subprocess.

The ``good`` fixture must pass both flavors; every ``bad-*`` fixture must fail
both — the negative assertions are the point (a fixture that passes when it
should fail is a broken guard).
"""

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT: Path = Path(__file__).resolve().parents[1]
JQ_TEMPLATE: Path = REPO_ROOT / "templates" / "ci" / "check-canon-declaration.sh"
PYTEST_TEMPLATE: Path = REPO_ROOT / "templates" / "ci" / "test_canon_adoption.py"
FIXTURES: Path = Path(__file__).resolve().parent / "fixtures"

# fixture directory name -> whether the templates must accept it
FIXTURE_EXPECTATIONS: dict[str, bool] = {
    "good": True,
    "bad-unpinned-ref": False,
    "bad-autoupdate": False,
    "bad-missing-module": False,
    "bad-no-declaration": False,
}

_parametrize_fixtures = pytest.mark.parametrize(
    ("fixture_name", "should_pass"),
    sorted(FIXTURE_EXPECTATIONS.items()),
)


def test_every_fixture_dir_has_an_expectation() -> None:
    """A fixture directory nobody asserts on is a silently dead guard."""
    on_disk: set[str] = {p.name for p in FIXTURES.iterdir() if p.is_dir()}
    assert on_disk == set(FIXTURE_EXPECTATIONS), (
        "tests/fixtures/ and FIXTURE_EXPECTATIONS are out of sync"
    )


@_parametrize_fixtures
def test_jq_template(fixture_name: str, should_pass: bool) -> None:
    if shutil.which("jq") is None:
        pytest.fail("jq is required to exercise check-canon-declaration.sh")
    fixture: Path = FIXTURES / fixture_name
    result: subprocess.CompletedProcess[str] = subprocess.run(
        ["bash", str(JQ_TEMPLATE)],
        cwd=fixture,
        capture_output=True,
        text=True,
        check=False,
    )
    detail: str = f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    if should_pass:
        assert result.returncode == 0, f"{fixture_name} must pass; {detail}"
    else:
        assert result.returncode != 0, f"{fixture_name} must fail; {detail}"


def _materialize_consumer_repo(fixture: Path, root: Path) -> Path:
    """Build ``<root>/.claude/`` + ``<root>/tests/meta/test_canon_adoption.py``.

    Mirrors the template's documented install location — its REPO_ROOT calc
    assumes ``parents[2]``. Returns the ``tests/meta`` directory.
    """
    shutil.copytree(fixture / ".claude", root / ".claude")
    meta: Path = root / "tests" / "meta"
    meta.mkdir(parents=True)
    _ = shutil.copy(PYTEST_TEMPLATE, meta / "test_canon_adoption.py")
    return meta


@_parametrize_fixtures
def test_pytest_template(fixture_name: str, should_pass: bool, tmp_path: Path) -> None:
    meta: Path = _materialize_consumer_repo(FIXTURES / fixture_name, tmp_path)
    result: subprocess.CompletedProcess[str] = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "-q",
            "-p",
            "no:cacheprovider",
            "--rootdir",
            str(tmp_path),
            str(meta),
        ],
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    detail: str = f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    if should_pass:
        assert result.returncode == 0, f"{fixture_name} must pass; {detail}"
    else:
        # Exit code 1 = tests ran and failed. Anything else (2 usage error,
        # 4 collection error, ...) would mean the gate broke rather than fired.
        assert result.returncode == 1, f"{fixture_name} must fail its tests; {detail}"
