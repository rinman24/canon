"""Lint the rule-module frontmatter invariants documented in the README.

Every tracked ``*.md`` whose YAML frontmatter declares ``module:`` is a rule
module. For each one this asserts:

* ``module`` equals the filename stem;
* ``tier`` is a known tier (``universal`` | ``python``);
* ``tier`` matches the directory the module lives in;
* every name in ``requires`` refers to an existing module;
* ``requires`` points up-tier only — a ``universal`` module may not require a
  ``python``/family module (the README's invariant, enforced here).

Scan set = ``git ls-files '*.md'`` so untracked working docs (PLAN-*.md) are
neither scanned nor required.
"""

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import cast

import pytest
import yaml

REPO_ROOT: Path = Path(__file__).resolve().parents[1]

# Lower rank = more universal. `requires` may only point at a tier whose rank
# is <= the requiring module's rank.
TIER_RANK: dict[str, int] = {"universal": 0, "python": 1}


@dataclass(frozen=True)
class Module:
    path: Path
    frontmatter: dict[str, object]

    @property
    def rel(self) -> str:
        return self.path.relative_to(REPO_ROOT).as_posix()


def _tracked_markdown() -> list[Path]:
    out: str = subprocess.run(
        ["git", "ls-files", "-z", "--", "*.md"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return [REPO_ROOT / rel for rel in out.split("\0") if rel]


def _frontmatter(path: Path) -> dict[str, object] | None:
    lines: list[str] = path.read_text(encoding="utf-8").splitlines()
    if not lines or lines[0].strip() != "---":
        return None
    end: int | None = next(
        (i for i, line in enumerate(lines[1:], start=1) if line.strip() == "---"),
        None,
    )
    if end is None:
        return None
    data: object = yaml.safe_load("\n".join(lines[1:end]))
    if not isinstance(data, dict):
        return None
    return cast(dict[str, object], data)


def _modules() -> list[Module]:
    found: list[Module] = []
    for path in _tracked_markdown():
        fm: dict[str, object] | None = _frontmatter(path)
        if fm is not None and "module" in fm:
            found.append(Module(path=path, frontmatter=fm))
    return found


MODULES: list[Module] = _modules()
MODULE_TIERS: dict[str, str] = {
    str(m.frontmatter.get("module")): str(m.frontmatter.get("tier"))
    for m in MODULES
}

_parametrize_modules = pytest.mark.parametrize(
    "module", MODULES, ids=[m.rel for m in MODULES]
)


def test_modules_were_discovered() -> None:
    """Guard the scan itself — an empty set would vacuously pass everything."""
    assert MODULES, "no tracked *.md with `module:` frontmatter found"


@_parametrize_modules
def test_module_name_matches_filename_stem(module: Module) -> None:
    assert module.frontmatter.get("module") == module.path.stem, (
        f"{module.rel}: `module:` must equal the filename stem"
    )


@_parametrize_modules
def test_tier_is_known(module: Module) -> None:
    assert module.frontmatter.get("tier") in TIER_RANK, (
        f"{module.rel}: `tier:` must be one of {sorted(TIER_RANK)}"
    )


@_parametrize_modules
def test_tier_matches_directory(module: Module) -> None:
    assert module.frontmatter.get("tier") == module.path.parent.name, (
        f"{module.rel}: `tier:` must match the directory the module lives in"
    )


def _requires(module: Module) -> list[str]:
    raw: object = module.frontmatter.get("requires", [])
    assert isinstance(raw, list), f"{module.rel}: `requires:` must be a list"
    names: list[str] = []
    for item in cast(list[object], raw):
        assert isinstance(item, str), (
            f"{module.rel}: `requires:` entries must be strings, got {item!r}"
        )
        names.append(item)
    return names


@_parametrize_modules
def test_requires_refer_to_existing_modules(module: Module) -> None:
    unknown: list[str] = [r for r in _requires(module) if r not in MODULE_TIERS]
    assert not unknown, (
        f"{module.rel}: `requires:` names unknown module(s) {unknown}; "
        f"known: {sorted(MODULE_TIERS)}"
    )


@_parametrize_modules
def test_requires_point_up_tier_only(module: Module) -> None:
    tier: object = module.frontmatter.get("tier")
    if tier not in TIER_RANK:  # reported by test_tier_is_known
        pytest.skip("unknown tier; covered by test_tier_is_known")
    own_rank: int = TIER_RANK[str(tier)]
    for req in _requires(module):
        req_tier: str | None = MODULE_TIERS.get(req)
        if req_tier is None:  # reported by test_requires_refer_to_existing_modules
            continue
        assert TIER_RANK[req_tier] <= own_rank, (
            f"{module.rel}: requires down-tier module '{req}' "
            f"(tier {req_tier!r}); a {tier} module may only require "
            f"same-or-more-universal tiers"
        )
