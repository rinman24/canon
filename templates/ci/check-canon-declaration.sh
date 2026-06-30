#!/usr/bin/env bash
# Language-agnostic CI gate: verify THIS repo still declares the Canon plugin.
# The jq-based equivalent of test_canon_adoption.py, for repos without pytest.
# A ready-made implementation of the README's "Enforcing that the rules are
# installed" declaration-check. Requires `jq`. Run from the repo root.
set -euo pipefail

SETTINGS=".claude/settings.json"
CANON_TXT=".claude/canon.txt"

# --- knobs (match .claude/settings.json) ---------------------------------------
MARKETPLACE="canon"
REPO="rinman24/canon"
PLUGIN="canon-core@canon"
# Space-separated modules this repo requires in .claude/canon.txt:
REQUIRED_MODULES="architecture-closed delivery-vertical-slice dev-hygiene git-semilinear testing-conventions worktree-isolation"
# -------------------------------------------------------------------------------

command -v jq >/dev/null || { echo "canon-check: jq is required"; exit 2; }
[ -f "$SETTINGS" ]  || { echo "canon-check: $SETTINGS missing"; exit 1; }
[ -f "$CANON_TXT" ] || { echo "canon-check: $CANON_TXT missing"; exit 1; }

fail() { echo "canon-check: FAIL — $1"; exit 1; }
src()  { jq -r ".extraKnownMarketplaces.\"$MARKETPLACE\".source.$1 // empty" "$SETTINGS"; }

[ "$(src source)" = "github" ] || fail "marketplace source must be 'github'"
[ "$(src repo)" = "$REPO" ]    || fail "marketplace repo must be '$REPO'"

ref="$(src ref)"
[[ "$ref" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "ref must be a pinned semver tag (vX.Y.Z), got '$ref'"

[ "$(jq -r ".extraKnownMarketplaces.\"$MARKETPLACE\".autoUpdate" "$SETTINGS")" = "false" ] \
    || fail "autoUpdate must be false"
[ "$(jq -r ".enabledPlugins.\"$PLUGIN\"" "$SETTINGS")" = "true" ] \
    || fail "$PLUGIN must be enabled"

declared="$(grep -vE '^[[:space:]]*(#|$)' "$CANON_TXT" | tr -d '[:space:]')"
for m in $REQUIRED_MODULES; do
    printf '%s\n' "$declared" | grep -qx "$m" || fail ".claude/canon.txt missing required module: $m"
done

echo "canon-check: OK (ref $ref)"
