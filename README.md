# claude-rules — portable Claude Code rule modules

Small, single-concept rule modules for `CLAUDE.md`, designed to be shared across
projects. A consuming repo's `CLAUDE.md` becomes a thin manifest of `@import` lines;
the durable engineering principles live here, and the project-specific facts live in
the consuming repo.

## Tiers

| Tier | Lives in | Content |
|---|---|---|
| 1 — universal | `universal/` | Language-agnostic principles (architecture, git, hygiene, testing, delivery, worktrees) |
| 2 — family | `python/` (and future siblings) | Principles portable within one language ecosystem |
| 3 — binding | the **consuming repo's** `.claude/local/` | Project/org-specific facts: directory trees, CI commands, env paths, host specifics |

Principles (tiers 1–2) carry **no project identity** — no project paths, no org tooling,
no host names. Anything project-specific belongs in a binding, authored and owned by the
consuming repo.

## Module format

Every module starts with YAML frontmatter:

```yaml
---
module: <kebab-case-name>
tier: universal | python | binding
summary: One-line description of what the module governs.
requires: []   # other modules this one assumes, by name
---
```

`requires` is declarative metadata (for humans and lint), **not** an import trigger —
the consuming manifest imports every module explicitly.

**`requires` points up-tier only.** A binding may require a principle; a principle never
requires a binding, and a universal module never requires a family module. This is the
invariant that keeps this repo free of any consumer's specifics.

## Consuming via git subtree

Vendor the modules into your repo at `.claude/rules/` so a fresh clone resolves every
`@import` with no install step:

```bash
git remote add claude-rules <this-repo-url>
git fetch claude-rules main
git subtree add --prefix=.claude/rules claude-rules main --squash
```

Take upstream updates with:

```bash
git fetch claude-rules main
git subtree pull --prefix=.claude/rules claude-rules main --squash
```

Rules of the road:

- `.claude/rules/` is **upstream-owned — never hand-edit it** in a consuming repo.
  Improvements go here, then propagate via `subtree pull`. This is what keeps
  `subtree pull` conflict-free.
- Principles copy in **verbatim, never trimmed**. Pick-and-choose happens in the
  manifest: omit a module by commenting out its `@import` line.
- In the manifest, import the vendored rules **first** and your local bindings **last**,
  so local content has the final say.

A consuming `CLAUDE.md` then looks like:

```markdown
# <project> — Claude Code rules manifest

<project mission / goals, inline>

@.claude/rules/universal/architecture-closed.md
@.claude/rules/universal/git-semilinear.md
...
@.claude/local/<your-bindings>.md
```
