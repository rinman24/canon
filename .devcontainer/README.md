# Canon dev container

Develop Canon in its own container — the same per-repo-container model as
gswa-backend, but much leaner (no database, no app venv, no multi-stage build). The
image carries `git`, `jq`, `shellcheck`, `python` + `pytest`, and the Claude Code CLI,
running as a non-root `dev` user (uid 1000) with passwordless sudo. See the top of
[`../Dockerfile`](../Dockerfile) for what's installed and why.

## Bring it up

VS Code (recommended): Remote-SSH into the VM, open this repo, then
**Dev Containers: Reopen in Container**. It builds the image, starts the `canon`
service, and attaches as `dev` at `/workspaces/canon`.

Plain Compose + attach (the gswa workflow):

```bash
docker compose -f .devcontainer/docker-compose.yml up -d --build
docker compose -f .devcontainer/docker-compose.yml exec canon bash   # lands as `dev`
```

The container stays up on `sleep infinity`; `~/.claude` is a persisted named volume, so
Claude auth and installed plugins survive rebuilds. A freshly created volume is empty —
authenticate once (`claude`) after the first recreate.

## Develop the rules

```bash
shellcheck hooks/*.sh templates/**/*.sh   # lint the shipped shell
pytest templates/ci                       # the adoption-check template
```

Note: `templates/ci/test_canon_adoption.py` is a template for *consuming* repos — it
asserts a `.claude/settings.json` Canon declaration that this repo doesn't carry, so it
isn't meant to pass green here. Run it against a repo that adopts Canon.

## Dogfood the plugin against your working tree

To see edits to the rule modules / SessionStart hook injected live, register *this
checkout* as a local marketplace (not the pinned GitHub release):

```bash
claude plugin marketplace add /workspaces/canon
claude plugin install canon-core@canon --scope user
# restart Claude Code (a fresh launch, not /clear) so the SessionStart hook registers
```

The hook reads from `CLAUDE_PLUGIN_ROOT`, which now points at `/workspaces/canon`, so
editing a module under `universal/` or `python/` and relaunching Claude shows the change.

To instead install the published, pinned release (the normal consumer path), point the
marketplace at the GitHub repo: `claude plugin marketplace add rinman24/canon`.

## What's intentionally omitted

This container drops gswa's "SSH everywhere" machinery (in-container `sshd`, host-key
volume, `authorized_keys`/`sshrc`/`known_hosts`, Azure CLI). Attach via VS Code
Remote-Containers or `docker exec`. If you want to `ssh canon-container` directly (and
get a forwarded SSH agent for keyless `git push` to GitHub from inside), that wiring can
be lifted from `gswa/.devcontainer` — ask and it can be added.
