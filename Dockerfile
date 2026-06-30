# Canon dev container — develop the Canon rules plugin in its own container.
#
# Deliberately lean next to gswa's Dockerfile. Canon is a Claude Code plugin repo:
# markdown rule modules (universal/, python/), a bash SessionStart hook (hooks/), a
# plugin manifest (.claude-plugin/), and a small adoption kit (templates/). There is
# no application, no database, and no project venv — so this is a single-stage image
# carrying only what you need to:
#   * lint the shipped shell (hooks/*.sh, templates/**/*.sh) with shellcheck,
#   * run the pytest adoption-check template, and
#   * exercise the plugin + SessionStart hook live with the Claude Code CLI.
#
# Conventions kept in common with the gswa image (so this container behaves the same
# way when you attach to it): a non-root `dev` user at uid/gid 1000 with passwordless
# sudo, Claude Code installed via Anthropic's native installer as `dev`, and a
# persisted ~/.claude (wired in docker-compose.yml).
FROM python:3.11-bookworm AS development

ENV PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive

# System tooling for developing Canon:
#   git        — version control (GitHub remote; stock bookworm git is fine for GitHub)
#   curl       — fetch the Claude Code native installer
#   jq         — used by templates/ci/check-canon-declaration.sh and general JSON work
#   shellcheck — lint the hook + template shell scripts (Canon's shipped deliverables)
#   sudo       — passwordless for `dev` (see the user block below)
#   less       — pager ergonomics for git / claude
# ca-certificates is already present in the base image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        curl \
        jq \
        shellcheck \
        sudo \
        less \
    && rm -rf /var/lib/apt/lists/*

# pytest for the adoption-check template (templates/ci/test_canon_adoption.py) and any
# python-tier work. Installed to the system interpreter on purpose — this is a
# single-purpose container, so there is no project venv to keep clean.
RUN pip install --no-cache-dir pytest

# Run the container as a non-root `dev` user (uid/gid 1000), same as the gswa image and
# for the same two reasons:
#   * Claude Code refuses `--dangerously-skip-permissions` as root (uid 0), which is the
#     unattended posture this image targets.
#   * The repo is bind-mounted from the VM (host uid 1000); a matching container uid
#     aligns ownership with zero chown of the mount.
# Passwordless sudo is the same accepted dev-convenience trade-off as gswa (dev can sudo
# back to root — this is a blast-radius reducer, not a hard jail).
RUN groupadd -g 1000 dev \
    && useradd -u 1000 -g 1000 -m -s /bin/bash dev \
    && echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev \
    && chmod 0440 /etc/sudoers.d/dev \
    # Pre-create the .claude mountpoint owned by dev so the persisted named volume
    # (docker-compose.yml) comes up dev-owned instead of root:root, letting the CLI
    # write its auth + installed plugins there.
    && install -d -o dev -g dev -m 0700 /home/dev/.claude

# Dev git ergonomics, baked system-wide / into dev's home so they hold on every launch
# path (matches the gswa image):
#   * a plain `git push` on a new branch auto-creates the same-named upstream
#   * trust the bind-mounted repo
#   * no commit gpg-signing (no signing key in-container)
RUN git config --system push.autoSetupRemote true \
    && su dev -c 'git config --global safe.directory /workspaces/canon' \
    && su dev -c 'git config --global commit.gpgsign false'

# Install Claude Code via Anthropic's native installer as `dev` (NOT `npm install -g`
# as root): the native installer lands the binary in /home/dev/.local (dev-owned) and
# self-updates in the background, which a root-owned npm global dir would block under
# the non-root runtime user. ~/.local lives in the image layer, so the .claude named
# volume mounted at runtime does not shadow it. PATH below puts ~/.local/bin first so
# `claude` resolves on every entry path (docker exec, VS Code attach, compose command).
ENV PATH=/home/dev/.local/bin:${PATH}
RUN su dev -c 'curl -fsSL https://claude.ai/install.sh | bash'

WORKDIR /workspaces/canon

# Drop to non-root for every entry path (docker exec, VS Code attach, compose command).
# devcontainer.json also sets "remoteUser": "dev" as belt-and-suspenders.
USER dev
