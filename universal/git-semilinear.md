---
module: git-semilinear
tier: universal
summary: Semi-linear integration — rebase-then-merge-commit, no plain non-ff, no squash-by-default, commit-message discipline, type-prefixed subjects/PR-titles, no WIP, branch naming.
requires: []
---

# Version Control: Semi-Linear Git Conventions

## Integration Strategy

- Team standard is **semi-linear merge**: always rebase the branch onto `main`
  first, then integrate with a merge commit. This keeps a linear, readable
  history while preserving the PR boundary (enables atomic PR revert via
  `git revert -m 1 <merge>` and a PR-level view via `git log --first-parent`).
- **Always rebase before merge.** Never integrate a branch that hasn't been
  rebased onto the current `main`.
- **No plain non-fast-forward merges** that skip the rebase. Branch protection
  requires linear history; do not propose or perform a merge that would
  interleave branch commits with unrelated `main` commits.
- **Do not squash by default.** Preserve well-formed, individually-coherent
  commits (each one bisectable and revertable). Squash only when a branch's
  commits are low-quality noise (e.g. "wip", "fix typo") that wouldn't survive
  review as standalone units — and prefer cleaning the commits up instead.
- The value of the merge commit is proportional to **commit-message
  discipline**: only keep commits when each message clearly explains its change.
  Clean up commit history before merge so the preserved commits are worth keeping.

## Commit Messages

- Begin every commit message subject with a type prefix, optionally scoped:
  `refactor:`, `test:`, `fix:`, `refactor(config):`, `test(config):`, etc.
- Keep subjects coherent and self-contained; the body should explain the change
  well enough that the commit stands on its own in history.
- **No WIP commits.** Never commit `wip`/checkpoint/"save progress" commits to a
  branch headed for a PR. Each commit must be a coherent, self-contained unit; if
  you need to checkpoint mid-task, fold it into a proper commit before pushing.

## Branch Names

- Use a folder-like, prefixed structure: `<type>/<short-kebab-description>`.
  Examples: `refactor/config-migrate-static-fields`, `fix/token-expiry-check`.
- Do not create bare branch names like `config-migrate-static-fields`.

## Pull Request Titles

- PR titles start with the same type prefix convention as commits:
  `refactor:`, `fix:`, `refactor(config):`, etc.
