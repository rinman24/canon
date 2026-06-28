# canon — portable Claude Code rule modules

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

## Consuming via the plugin marketplace

This repo is also a Claude Code **plugin marketplace**. Instead of vendoring the
modules, a project can install them as a plugin — the rules are then injected
into every session by a `SessionStart` hook, with no `@import` lines to maintain.

Add the marketplace and install the plugin:

```bash
/plugin marketplace add rinman24/canon
/plugin install canon-core@canon
```

The `canon-core` plugin bundles every tier-1 (`universal/`) and tier-2
(`python/`) module. On each session start — and after `/clear` and compaction —
the hook injects the bundled modules as context and warns loudly if anything is
missing.

Optionally declare which modules a project requires in
`.claude/canon.txt` (one module name per line, `#` for comments). The hook
verifies each is present in the installed bundle and emits a prominent warning
block if not:

```
# .claude/canon.txt
architecture-closed
git-semilinear
dev-hygiene
typing-python
```

Tier-3 bindings still belong in the **consuming repo's** `.claude/local/` — the
plugin ships only the portable principles.

### Verifying the install

After installing, open Claude Code in any project and confirm the hook fired:
look for the injected context block titled `# Engineering rules (injected by
canon-core)` — check it via `/context`, or just ask "what engineering rules
are loaded?". For a deeper look, `claude --debug` shows the `SessionStart` hook
registering and running `verify-and-inject.sh`.

### Staying current

`canon-core` declares no `version` (in neither `plugin.json` nor the
marketplace entry), so its version resolves to the **git commit SHA** of the
default branch. Every push to `main` is therefore a new version — maintainers
never bump a number, and consumers can always reach the latest rules.

How a consumer gets those updates:

- **Automatic (recommended).** Enable auto-update for the marketplace —
  `/plugin` → Marketplaces → select `canon` → "Enable auto-update". Claude
  Code then refreshes the marketplace and pulls the newest commit at startup,
  and prompts `/reload-plugins` to activate it. (Third-party marketplaces have
  auto-update **off** by default, so this is opt-in per consumer.)
- **Manual.** Run `/plugin marketplace update canon`, then `/reload-plugins`.

## Consuming via git subtree

Vendor the modules into your repo at `.claude/rules/` so a fresh clone resolves every
`@import` with no install step:

```bash
git remote add canon <this-repo-url>
git fetch canon main
git subtree add --prefix=.claude/rules canon main --squash
```

Take upstream updates with:

```bash
git fetch canon main
git subtree pull --prefix=.claude/rules canon main --squash
```

**Linear-history hosts:** `git subtree` creates merge commits, which rebase-based PR
completion (e.g. Azure DevOps semi-linear / rebase-and-fast-forward) cannot replay —
the squashed root commit lands at the repo root. If your target branch only accepts
rebased PRs, vendor with a plain snapshot commit instead, keeping subtree-compatible
provenance trailers:

```bash
git fetch canon main
SPLIT=$(git rev-parse FETCH_HEAD)
git rm -rq .claude/rules 2>/dev/null || true
git read-tree --prefix=.claude/rules -u FETCH_HEAD
git commit -m "chore(rules): vendor canon at ${SPLIT:0:9}" \
  -m "git-subtree-dir: .claude/rules" \
  -m "git-subtree-split: ${SPLIT}"
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

## Enforcing that the rules are installed

The `canon-core` SessionStart hook injects these rules and warns loudly
when a required module is missing. But a SessionStart hook **cannot block** a
session, and it only runs when the plugin is already installed — so it covers
"installed but broken," not "never installed." To make installation genuinely
*required*, add one of the following layers. Each lives **outside** the plugin,
so it can catch a missing plugin:

1. **Hard fail via CI (recommended for repos you control).** Add a declaration
   check to the repo's required build validation: a small test/lint that fails
   if `.claude/settings.json` does not declare this marketplace and the required
   rule plugin(s). Combined with branch protection, this makes a repo that
   "forgot to require the rules" **un-mergeable**. CI is enforced server-side
   and needs no per-developer setup, so it is the only truly unskippable gate.

2. **Once-per-machine tripwire (optional — for live dev sessions).** On
   machines you provision, drop a SessionStart hook into the user-level
   `~/.claude/settings.json` (e.g. via your dotfiles/bootstrap). It runs in
   every repo on that machine, checks the project's declared requirements, and
   warns if `canon-core` is not loaded — catching the gap in interactive
   sessions rather than only in CI.
