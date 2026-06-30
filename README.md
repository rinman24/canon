<picture align="center">
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/rinman24/canon/main/docs/assets/canon_light.svg">  <img alt="canon logo" src="https://raw.githubusercontent.com/rinman24/canon/main/docs/assets/canon.svg">
</picture>

-----------------

Canon is a portable library of engineering principles — *architecture*, *git*, *testing*, *hygiene* — composed into a project's `CLAUDE.md` and injected into every coding session, so your agent follows the same principles in every repo.

## What Canon is

A fixed point, assembled from parts. A *canon* is the authoritative body of
principles a discipline is built on — durable, shared, versioned. The name carries
the two ideas the project is built on: a **north star** the agent aligns to in every
session, and a **whole composed from small, single-concept modules**. Authoritative
without being loud — a reference you return to, not a tool that shouts.

In practice that means small, single-concept rule modules for `CLAUDE.md`, designed
to be shared across projects. A consuming repo's `CLAUDE.md` becomes a thin manifest
of `@import` lines; the durable engineering principles live here, and the
project-specific facts live in the consuming repo.

## Find it on the Claude Code marketplace

Canon ships as a Claude Code **plugin marketplace**. Add it and install the plugin:

```bash
/plugin marketplace add rinman24/canon
/plugin install canon-core@canon
```

`canon-core` bundles every tier-1 (`universal/`) and tier-2 (`python/`) module and
injects them at every session start. For verification, staying current, and the
optional `.claude/canon.txt` manifest, see [Consuming via the plugin
marketplace](#consuming-via-the-plugin-marketplace) below.

### Install in any environment (scriptable)

The slash commands above are interactive. To install canon **non-interactively** —
in dotfiles, a setup script, CI, or a fresh container/machine — use the CLI
equivalents:

```bash
claude plugin marketplace add rinman24/canon --scope user
claude plugin install canon-core@canon --scope user
```

This clones the marketplace (canon is public — no auth needed) and installs and
enables `canon-core` for every project on the machine. It is safe to re-run: it
no-ops once installed, so it belongs in your shell rc / dotfiles to make new
environments self-provision.

A committed `.claude/settings.json` that *declares* the marketplace does **not**
auto-install the plugin — each environment needs this one-time activation. That is
a deliberate security boundary: a repo you check out cannot silently make your
machine fetch and run code. Restart Claude Code afterward, because the
`SessionStart` hook only registers at process startup (not on `/clear`).

Running each repo in its own dev container, with nothing installed at the host
level? See [Adopting Canon in dev containers](docs/adopting-in-dev-containers.md)
for the activation wiring (entrypoint vs `postCreateCommand`) and a ready-made
`setup-canon.sh`.

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

Installing as a plugin (the [quick start](#find-it-on-the-claude-code-marketplace)
above) is the path most projects want: instead of vendoring the modules, the rules
are injected into every session by a `SessionStart` hook, with no `@import` lines to
maintain.

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

After installing (and **restarting** Claude Code), confirm the hook fired. Note
that `/context` does **not** itemize `SessionStart`-injected content, so an
empty-looking `/context` is not a failure. Verify by either:

- **Functionally** — ask "what engineering rules are loaded?"; the answer should
  draw on canon modules (e.g. the `git-semilinear` rule: rebase before merge, no
  WIP commits) rather than just project-local facts.
- **Hook output / debug** — `claude --debug` shows the `SessionStart` hook
  registering and running `verify-and-inject.sh`; the injected block is titled
  `# Engineering rules (injected by canon-core)`.

### Versioning & staying current

`canon-core` declares a semantic `version` in `plugin.json`, and each release is
a matching git tag (`vX.Y.Z`) on `main`. Consumers pin to a tag via the
marketplace `ref` so the injected rules never drift between environments:

```json
// .claude/settings.json (per-repo, shared with teammates) — or ~/.claude/settings.json (per-machine)
"extraKnownMarketplaces": {
  "canon": {
    "source": { "source": "github", "repo": "rinman24/canon", "ref": "v1.0.0" },
    "autoUpdate": false
  }
}
```

How a consumer takes an update:

- **Manual.** Bump the pinned `ref` to the new tag, then
  `/plugin marketplace update canon` and `/reload-plugins` (or restart).
- **Automated (recommended).** A dependency bot — e.g. Renovate's `github-tags`
  manager watching `rinman24/canon` — opens a PR raising the pinned `ref` when a
  new tag ships; review and merge to adopt it.

Leaving `autoUpdate: false` (the default for third-party marketplaces) keeps every
environment on the pinned tag until you deliberately move it.

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
   Ready-made checks live in [`templates/ci/`](templates/ci/): a pytest module
   and a language-agnostic `jq` script.

2. **Once-per-machine tripwire (optional — for live dev sessions).** On
   machines you provision, drop a SessionStart hook into the user-level
   `~/.claude/settings.json` (e.g. via your dotfiles/bootstrap). It runs in
   every repo on that machine, checks the project's declared requirements, and
   warns if `canon-core` is not loaded — catching the gap in interactive
   sessions rather than only in CI.

## Brand

Canon's identity — mark, palette, type, and voice — is documented in the
[Canon Brand Kit](docs/brand/Canon%20Brand%20Kit.html). The mark is a circle
inscribed with a square centered on a single point: the ring is the canon that
contains, the square is structure, the point is first principles. Voice is
**precise, quiet, durable** — say the rule and the reason, authoritative without
volume, written for the long term.

-----------------

*Canon — Brand Guidelines · v1.0 · 2026 — the principles your agent codes by.*
