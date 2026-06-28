#!/usr/bin/env bash
# canon-core SessionStart hook: inject the bundled rule modules as
# session context, and warn loudly if a required module is missing or the
# install looks broken.
#
# NOTE: SessionStart hooks cannot block a session — this WARNS, it does not gate.
# The hard gate lives in CI (see the repo README, "Enforcing that the rules are
# installed").
#
# Portability: written for bash 3.2 (the macOS system bash) — no `mapfile`,
# no bash-4 features.
set -uo pipefail

# --- Locate the bundled rule modules ---------------------------------------
# The plugin root IS the repo root (single-plugin marketplace), so the rule
# modules live in tier subdirs (universal/, python/) directly beneath it.
RULES_ROOT="${CLAUDE_PLUGIN_ROOT:?CLAUDE_PLUGIN_ROOT is not set}"

# A rule module is any *.md whose frontmatter declares `module:` (the repo's own
# contract, per README). Filtering on that — rather than on filename — keeps
# README.md, the plugin manifests, and any stray docs out of the injection.
MODULES=()
while IFS= read -r f; do
  if head -n 10 "$f" | grep -q '^module:'; then
    MODULES+=("$f")
  fi
done < <(find "$RULES_ROOT" -type f -name '*.md' ! -path '*/.claude-plugin/*' | sort)

warnings=()
if [ "${#MODULES[@]}" -eq 0 ]; then
  warnings+=("No rule modules found under ${RULES_ROOT} — the canon-core install looks broken.")
fi

# --- Optional: per-project required-module manifest ------------------------
# A consuming project may declare which modules it requires in:
#   ${CLAUDE_PROJECT_DIR}/.claude/canon.txt   (one module name per line; # = comment)
# Module name = the *.md basename without extension (e.g. architecture-closed).
# For each required name, verify a matching module file is present in the bundle.
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
manifest="${project_dir}/.claude/canon.txt"
if [ -f "$manifest" ]; then
  while IFS= read -r raw; do
    name="${raw%%#*}"
    name="$(printf '%s' "$name" | xargs 2>/dev/null)"   # trim whitespace
    [ -z "$name" ] && continue
    found=0
    for m in ${MODULES[@]+"${MODULES[@]}"}; do
      case "$m" in */"$name".md) found=1; break ;; esac
    done
    if [ "$found" -eq 0 ]; then
      warnings+=("Project requires rule module '${name}', but it is not present in the installed canon-core bundle.")
    fi
  done < "$manifest"
fi

# --- Emit context (plain stdout is injected as SessionStart context) -------
if [ "${#warnings[@]}" -gt 0 ]; then
  echo "## ⚠️ REQUIRED CANON RULES PROBLEM"
  echo
  echo "Claude may be operating WITHOUT this project's required engineering standards:"
  for w in "${warnings[@]}"; do echo "- ${w}"; done
  echo
  echo "Fix: install or repair the rules plugin, e.g.:"
  echo '  /plugin install canon-core@canon'
  echo
  printf 'canon-core: %s\n' "${warnings[@]}" >&2   # human-visible under --debug / on stderr
fi

echo "# Engineering rules (injected by canon-core)"
echo
for f in ${MODULES[@]+"${MODULES[@]}"}; do
  echo "<!-- source: ${f#"$RULES_ROOT"/} -->"
  cat "$f"
  echo
done

exit 0
