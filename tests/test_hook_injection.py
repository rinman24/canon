"""Behavior tests for the ``canon-core`` SessionStart hook.

The hook (``hooks/verify-and-inject.sh``) discovers the bundled rule modules,
optionally narrows the injected set via a consuming project's
``.claude/canon.txt`` manifest, and writes the injected block to stdout plus an
inspectable summary line to both stdout (HTML comment) and stderr.

Each test builds a throwaway fake plugin bundle (``CLAUDE_PLUGIN_ROOT``) with a
couple of ``universal/*.md`` modules and one ``python/*.md`` module, plus a fake
consuming project (``CLAUDE_PROJECT_DIR``), then runs the *real* hook via a
``bash`` subprocess and asserts on stdout/stderr.

The v2.0 default (no canon.txt) resolution: tier-1 ``universal/`` modules are
always injected; every family tier (e.g. ``python/``) is injected only when the
project is DETECTED as that kind of project. An unknown family tier with no
detection rule is injected by default. A present canon.txt with >= 1 valid
module remains AUTHORITATIVE — it narrows to exactly those modules and wins over
detection. Covered:

* no manifest, non-Python project -> universal only (python skipped);
* no manifest, Python project     -> universal + python (detected via marker);
* subset manifest    -> only the listed modules injected (excluded content and
  its ``source:`` comment are ABSENT), summary reports the narrowed count;
* authoritative wins -> a manifest listing a family module injects it even when
  the project is not detected as that family;
* unknown name       -> warning emitted for the missing module;
* zero-valid manifest -> fallback to the v2.0 default set + a fallback warning;
* unknown family tier -> injected by default with a "no detection rule" note;
* every case exits 0 (SessionStart hooks must never gate the session).
"""

import subprocess
from pathlib import Path

HOOK: Path = Path(__file__).resolve().parents[1] / "hooks" / "verify-and-inject.sh"

# stem -> (tier, marker sentence unique to that module's body)
BUNDLE: dict[str, tuple[str, str]] = {
    "architecture-closed": ("universal", "ARCHITECTURE_CLOSED_BODY_MARKER"),
    "git-semilinear": ("universal", "GIT_SEMILINEAR_BODY_MARKER"),
    "typing-python": ("python", "TYPING_PYTHON_BODY_MARKER"),
}


def _make_bundle(root: Path) -> None:
    """Write a minimal valid plugin bundle under ``root``."""
    for stem, (tier, marker) in BUNDLE.items():
        tier_dir: Path = root / tier
        tier_dir.mkdir(parents=True, exist_ok=True)
        (tier_dir / f"{stem}.md").write_text(
            f"---\n"
            f"module: {stem}\n"
            f"tier: {tier}\n"
            f"summary: Test module {stem}.\n"
            f"requires: []\n"
            f"---\n\n"
            f"# {stem}\n\n"
            f"{marker}\n",
            encoding="utf-8",
        )


def _run(bundle: Path, project: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(HOOK)],
        env={
            "CLAUDE_PLUGIN_ROOT": str(bundle),
            "CLAUDE_PROJECT_DIR": str(project),
            "PATH": _path(),
        },
        capture_output=True,
        text=True,
        check=False,
    )


def _path() -> str:
    import os

    return os.environ.get("PATH", "/usr/bin:/bin")


def _write_manifest(project: Path, body: str) -> None:
    claude: Path = project / ".claude"
    claude.mkdir(parents=True, exist_ok=True)
    (claude / "canon.txt").write_text(body, encoding="utf-8")


def _write_module(root: Path, tier: str, stem: str, marker: str) -> None:
    """Write a single valid rule module under ``root/tier/stem.md``."""
    tier_dir: Path = root / tier
    tier_dir.mkdir(parents=True, exist_ok=True)
    (tier_dir / f"{stem}.md").write_text(
        f"---\n"
        f"module: {stem}\n"
        f"tier: {tier}\n"
        f"summary: Test module {stem}.\n"
        f"requires: []\n"
        f"---\n\n"
        f"# {stem}\n\n"
        f"{marker}\n",
        encoding="utf-8",
    )


# Universal stems, used repeatedly to assert the always-on tier-1 surface.
UNIVERSAL_MARKERS: list[str] = [
    marker for _, (tier, marker) in BUNDLE.items() if tier == "universal"
]


def test_no_manifest_non_python_injects_universal_only(tmp_path: Path) -> None:
    """No canon.txt + non-Python project -> universal only; python skipped."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()  # empty project: no Python markers

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    for marker in UNIVERSAL_MARKERS:
        assert marker in result.stdout, f"{marker} missing from universal injection"
    # The python module is gated out and its content must be absent.
    assert BUNDLE["typing-python"][1] not in result.stdout
    assert "python/typing-python.md" not in result.stdout
    # 2 of 3 injected; manifest reports the default composition + skip reason.
    assert f"injected 2/{len(BUNDLE)} modules (defaults:" in result.stdout
    assert "universal always-on" in result.stdout
    assert "python skipped — no Python project markers" in result.stdout
    assert "python skipped — no Python project markers" in result.stderr


def test_no_manifest_python_project_injects_universal_and_python(
    tmp_path: Path,
) -> None:
    """No canon.txt + a Python project -> universal + python (detected)."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    (project / "pyproject.toml").write_text("[project]\nname='x'\n", encoding="utf-8")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    for marker in UNIVERSAL_MARKERS:
        assert marker in result.stdout
    assert BUNDLE["typing-python"][1] in result.stdout
    assert "python/typing-python.md" in result.stdout
    assert f"injected {len(BUNDLE)}/{len(BUNDLE)} modules (defaults:" in result.stdout
    assert "python detected via pyproject.toml" in result.stdout
    assert "python detected via pyproject.toml" in result.stderr


def test_manifest_subset_narrows_injection(tmp_path: Path) -> None:
    """A subset manifest injects only the listed modules; others are absent."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    _write_manifest(project, "architecture-closed\ntyping-python\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    # Included modules: body marker AND source comment present.
    assert BUNDLE["architecture-closed"][1] in result.stdout
    assert "universal/architecture-closed.md" in result.stdout
    assert BUNDLE["typing-python"][1] in result.stdout
    assert "python/typing-python.md" in result.stdout
    # Excluded module: neither body marker nor its source comment.
    assert BUNDLE["git-semilinear"][1] not in result.stdout
    assert "git-semilinear.md" not in result.stdout
    # Summary reports the narrowed count and reason.
    assert f"injected 2/{len(BUNDLE)} modules (narrowed by" in result.stdout
    assert f"injected 2/{len(BUNDLE)} modules (narrowed by" in result.stderr


def test_manifest_preserves_sorted_bundle_order(tmp_path: Path) -> None:
    """Injected subset keeps sorted bundle order, not canon.txt order."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    # Bundle order is sorted by path: "python/..." sorts before "universal/...",
    # so typing-python precedes architecture-closed. List them reversed in the
    # manifest to prove injection ignores canon.txt order.
    _write_manifest(project, "architecture-closed\ntyping-python\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    arch_at: int = result.stdout.index(BUNDLE["architecture-closed"][1])
    typing_at: int = result.stdout.index(BUNDLE["typing-python"][1])
    assert typing_at < arch_at, "injection must follow sorted bundle order"


def test_manifest_unknown_name_warns(tmp_path: Path) -> None:
    """A listed name absent from the bundle raises a warning (present ones still inject)."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    _write_manifest(project, "architecture-closed\nno-such-module\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    assert "no-such-module" in result.stdout  # in the warning block
    assert "no-such-module" in result.stderr
    assert "REQUIRED CANON RULES PROBLEM" in result.stdout
    # The valid listed module is still injected, and the count is narrowed to 1.
    assert BUNDLE["architecture-closed"][1] in result.stdout
    assert f"injected 1/{len(BUNDLE)} modules (narrowed by" in result.stdout


def test_manifest_zero_valid_falls_back_to_defaults(tmp_path: Path) -> None:
    """Comments-only manifest -> v2.0 default set injected + fallback warning."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()  # non-Python project
    _write_manifest(project, "# only comments\n#architecture-closed\n\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    # Fallback yields the DEFAULT set (universal only — no Python markers here).
    for marker in UNIVERSAL_MARKERS:
        assert marker in result.stdout, f"{marker} missing from fallback injection"
    assert BUNDLE["typing-python"][1] not in result.stdout
    assert "selected 0 valid modules" in result.stdout  # fallback warning still fires
    assert "selected 0 valid modules" in result.stderr
    assert f"injected 2/{len(BUNDLE)} modules (fallback" in result.stdout
    assert "using defaults:" in result.stdout


def test_manifest_all_missing_falls_back_to_defaults(tmp_path: Path) -> None:
    """Every listed name missing -> v2.0 default set fallback, not an empty inject."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()  # non-Python project
    _write_manifest(project, "nope-one\nnope-two\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    for marker in UNIVERSAL_MARKERS:
        assert marker in result.stdout
    assert BUNDLE["typing-python"][1] not in result.stdout
    assert "selected 0 valid modules" in result.stdout
    assert f"injected 2/{len(BUNDLE)} modules (fallback" in result.stdout


def test_detection_via_pyproject_injects_python(tmp_path: Path) -> None:
    """No canon.txt + pyproject.toml marker -> python module injected."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    (project / "pyproject.toml").write_text("[project]\n", encoding="utf-8")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    assert BUNDLE["typing-python"][1] in result.stdout
    assert "python detected via pyproject.toml" in result.stdout


def test_detection_via_py_file_injects_python(tmp_path: Path) -> None:
    """A stray *.py file (no marker file) still detects a Python project."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()
    (project / "app.py").write_text("print('hi')\n", encoding="utf-8")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    assert BUNDLE["typing-python"][1] in result.stdout
    assert "python detected via app.py" in result.stdout


def test_detection_negative_skips_python(tmp_path: Path) -> None:
    """No canon.txt + empty project -> python skipped, universal injected."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    for marker in UNIVERSAL_MARKERS:
        assert marker in result.stdout
    assert BUNDLE["typing-python"][1] not in result.stdout
    assert "python skipped — no Python project markers" in result.stdout


def test_manifest_authoritative_wins_over_detection(tmp_path: Path) -> None:
    """canon.txt listing only a family module injects it despite no detection."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    _make_bundle(bundle)
    project.mkdir()  # non-Python project — detection would skip python
    _write_manifest(project, "typing-python\n")

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    # Explicit manifest wins: python injected, universal NOT force-added.
    assert BUNDLE["typing-python"][1] in result.stdout
    for marker in UNIVERSAL_MARKERS:
        assert marker not in result.stdout
    assert f"injected 1/{len(BUNDLE)} modules (narrowed by" in result.stdout


def test_unknown_family_tier_injected_by_default(tmp_path: Path) -> None:
    """A family tier with no detection rule is injected by default, and said so."""
    bundle: Path = tmp_path / "bundle"
    project: Path = tmp_path / "project"
    # Build an inline bundle: one universal + one module under an unknown tier.
    _write_module(bundle, "universal", "architecture-closed", "ARCH_MARKER")
    _write_module(bundle, "rust", "borrow-checker", "BORROW_CHECKER_MARKER")
    project.mkdir()  # not a Rust project, but there is no rule to gate on

    result = _run(bundle, project)

    assert result.returncode == 0, result.stderr
    assert "ARCH_MARKER" in result.stdout
    assert "BORROW_CHECKER_MARKER" in result.stdout
    assert "rust injected by default — no detection rule" in result.stdout
    assert "rust injected by default — no detection rule" in result.stderr
    assert "injected 2/2 modules (defaults:" in result.stdout
