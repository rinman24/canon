---
module: worktree-isolation
tier: universal
summary: Per-session git-worktree isolation for commit-producing work — trigger, timing, base ref, top-level-only, sub-agent isolation by unit of work, name=branch, keep-on-exit lifecycle.
requires: [git-semilinear]   # references the "always rebase onto current main" rule
---

# Worktree Isolation

Top-level, commit-producing sessions isolate themselves in a git worktree so parallel
sessions never fight over the single shared checkout. The harness-native `EnterWorktree`
tool is the mechanism; this instruction is the trigger (the tool fires only on explicit
user or CLAUDE.md/memory instruction — there is no automatic isolation).

- **When (trigger).** Only when the task will produce commits — implement, fix, refactor,
  TDD. Call `EnterWorktree` for those. Q&A, planning, research, and other non-committing
  work stays in the main checkout (no worktree — avoids orphan branches/dirs).
- **Timing.** Enter the worktree BEFORE the first file edit — at the point a branch would
  otherwise be created. A fresh worktree branches from the remote default branch and will
  not carry along edits already made in the main checkout.
- **Base ref.** Branch from a freshly-fetched `origin/main`. This matches the "always
  rebase onto current `main`" semi-linear rule and makes the eventual rebase a no-op.
- **Top-level only.** Only a top-level session self-isolates. A sub-agent NEVER calls
  `EnterWorktree` for itself; the parent is always the one that decides isolation.
- **Sub-agents / teams: isolate by unit of work, not by "is it a sub-agent."** The parent
  sets isolation based on the work, not the role:
  - Helpers collaborating on ONE slice → share the parent's tree. Spawn them WITHOUT
    `isolation: "worktree"` (they inherit the parent's pinned cwd).
  - N independent, file-disjoint slices → spawn one agent per slice WITH
    `isolation: "worktree"` (each slice gets its own tree).
- **Naming (pass `name` at creation; never re-branch in-tree).** Always call
  `EnterWorktree` with an explicit `name: <type>/<slug>` (e.g. `feat/scope-revocation`) —
  its `name` accepts `/`-separated segments. Worktree name = branch name. Do **not**
  rename or re-create branches inside the worktree — that leaks orphan branches. Keep
  names consistent with the branch-naming convention in `git-semilinear`.
- **Lifecycle.** Keep the worktree on session exit; remove it only after its PR merges.
  Uncommitted work in a kept worktree survives until cleanup.

Mechanics (hook, base ref, lifecycle) are repo-specific; see your worktree hooks and any
local ADR.
