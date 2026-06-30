# Adopting Canon in dev containers

For teams that run each repository in its own dev container — for example Docker
Compose services on a shared VM — and want every container to install Canon
*itself*, with nothing installed at the VM or host level. Each container provisions
Canon into its own `~/.claude`, so the containers stay isolated and the host stays
clean.

This guide adds only the container-specific wiring. The mechanics it builds on —
the scriptable install, the `.claude/settings.json` declaration and pin, and CI
enforcement — are in the [README](../README.md); links point there rather than
repeat them.

## Two layers

Canon adoption is always a *declaration* plus an *activation*, and keeping them
separate is what lets a container self-provision while the host holds nothing:

- Declaration — the committed `.claude/settings.json` block that pins the marketplace
  `ref` and enables `canon-core`. It records intent and drives CI; it does **not**
  install. See [Versioning & staying current](../README.md#versioning--staying-current).
- Activation — the per-environment install Claude Code requires. See
  [Install in any environment (scriptable)](../README.md#install-in-any-environment-scriptable).
  Canon will not let a checked-out repo install itself silently, so this step is
  always explicit. In a container it is one idempotent script:
  [`templates/devcontainer/setup-canon.sh`](../templates/devcontainer/setup-canon.sh).

## Where to call the activation

This is the one container-specific decision, and the obvious answer is often wrong.

`devcontainer.json`'s `postCreateCommand` only fires when an editor's
dev-container integration (VS Code "Reopen in Container", or the devcontainer CLI)
*creates* the container. It does **not** fire when the container is brought up by
plain `docker compose up` and attached to with `docker exec` or SSH. If that is how
you reach your containers, a `postCreateCommand` activation silently never runs.

So choose by how the container actually starts:

- Compose up + `docker exec`/SSH attach (recommended for this model) — call the
  script from the compose **entrypoint**, where it always runs. Add one line before
  the entrypoint hands off to the container's command, so it runs as the default
  (non-root) user after `~/.claude` is mounted:

  ```bash
  "$(dirname "$0")/setup-canon.sh" || echo "entrypoint: canon activation failed (non-fatal)"
  ```

- Editor "Reopen in Container" / devcontainer CLI — the standard
  `postCreateCommand` is enough; chain it after anything already there:

  ```jsonc
  "postCreateCommand": "${containerWorkspaceFolder}/.devcontainer/setup-canon.sh"
  ```

The script is identical either way; only the caller differs. It is idempotent and
needs no credentials, so running it on every start is fine — once Canon is installed
it is a fast no-op.

Restart Claude Code after the first install: the `SessionStart` hook registers only
at process startup (a fresh launch, not `/clear`).

### Scope

`setup-canon.sh` defaults to `CANON_SCOPE=user`, matching the README's container
recommendation — it enables Canon for the whole container, which for a one-repo
container is what you want and needs no working directory. Set `CANON_SCOPE=project`
to scope the install to a single repo instead; the script then runs from the repo
root (it assumes it lives at `<repo>/.devcontainer/setup-canon.sh`).

## Make it required (CI)

The committed declaration is only a promise until something checks it. Add the
declaration-check from
[Enforcing that the rules are installed](../README.md#enforcing-that-the-rules-are-installed)
to required build validation. Two ready-made implementations live in
[`templates/ci/`](../templates/ci/):

- [`test_canon_adoption.py`](../templates/ci/test_canon_adoption.py) — a pytest
  module for Python repos.
- [`check-canon-declaration.sh`](../templates/ci/check-canon-declaration.sh) — a
  language-agnostic `jq` script for everything else.

Both verify the marketplace is declared, the `ref` is a pinned `vX.Y.Z` tag,
`autoUpdate` is `false`, `canon-core` is enabled, and `.claude/canon.txt` lists the
modules the repo requires. Edit the knobs at the top of whichever you use.

## Per-repo checklist

1. Commit the `.claude/settings.json` declaration block and a `.claude/canon.txt`
   listing the modules this repo requires.
2. Copy [`setup-canon.sh`](../templates/devcontainer/setup-canon.sh) to
   `<repo>/.devcontainer/setup-canon.sh` (`chmod +x`) and wire it to the entrypoint
   (or `postCreateCommand`) per above.
3. Copy a CI check from [`templates/ci/`](../templates/ci/), set its knobs, and add
   it to required build validation + branch protection.

Adopting a new container is then those three steps — the host never sees Canon, and
each container keeps itself current against the pin.
