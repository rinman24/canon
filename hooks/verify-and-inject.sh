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

# --- Optional: per-project module manifest (verify + narrow) ---------------
# A consuming project may declare which modules it wants in:
#   ${CLAUDE_PROJECT_DIR}/.claude/canon.txt   (one module name per line; # = comment)
# Module name = the *.md basename without extension (e.g. architecture-closed).
# When present and resolving to a non-empty set of names, the manifest NARROWS
# injection to those modules (still warning for any listed name absent from the
# bundle). If it resolves to zero valid names we fall back to the full bundle
# rather than stripping every rule — narrowing must never silently disarm canon.
MANIFEST_REL=".claude/canon.txt"
project_dir="${CLAUDE_PROJECT_DIR:-$PWD}"
manifest="${project_dir}/${MANIFEST_REL}"

requested=()          # names read from canon.txt (present in bundle or not)
manifest_present=0
if [ -f "$manifest" ]; then
  manifest_present=1
  while IFS= read -r raw || [ -n "$raw" ]; do
    name="${raw%%#*}"
    name="$(printf '%s' "$name" | xargs 2>/dev/null)"   # trim whitespace
    [ -z "$name" ] && continue
    requested+=("$name")
  done < "$manifest"
fi

# Verify each requested name against the bundle, and build the injected subset
# in the existing sorted bundle order (NOT canon.txt order).
INJECT=()
if [ "$manifest_present" -eq 1 ] && [ "${#requested[@]}" -gt 0 ]; then
  for name in ${requested[@]+"${requested[@]}"}; do
    found=0
    for m in ${MODULES[@]+"${MODULES[@]}"}; do
      case "$m" in */"$name".md) found=1; break ;; esac
    done
    if [ "$found" -eq 0 ]; then
      warnings+=("Project requires rule module '${name}', but it is not present in the installed canon-core bundle.")
    fi
  done
  for m in ${MODULES[@]+"${MODULES[@]}"}; do
    stem="$(basename "$m" .md)"
    for name in ${requested[@]+"${requested[@]}"}; do
      if [ "$stem" = "$name" ]; then
        INJECT+=("$m")
        break
      fi
    done
  done
fi

# Decide what actually gets injected: narrowed subset, or full-bundle fallback.
narrowed=0
fallback=0
if [ "$manifest_present" -eq 1 ] && [ "${#INJECT[@]}" -gt 0 ]; then
  narrowed=1
else
  if [ "$manifest_present" -eq 1 ]; then
    fallback=1
    warnings+=("${MANIFEST_REL} selected 0 valid modules — injecting the full bundle instead of stripping all rules.")
  fi
  INJECT=(${MODULES[@]+"${MODULES[@]}"})
fi

# --- Build the injection-manifest summary line -----------------------------
total="${#MODULES[@]}"
count="${#INJECT[@]}"
stems=""
for m in ${INJECT[@]+"${INJECT[@]}"}; do
  s="$(basename "$m" .md)"
  if [ -z "$stems" ]; then stems="$s"; else stems="${stems}, ${s}"; fi
done
if [ "$narrowed" -eq 1 ]; then
  summary="injected ${count}/${total} modules (narrowed by ${MANIFEST_REL}): ${stems}"
elif [ "$fallback" -eq 1 ]; then
  summary="injected ${count}/${total} modules (fallback: ${MANIFEST_REL} selected 0 valid modules): ${stems}"
else
  summary="injected ${count}/${total} modules (full bundle; no ${MANIFEST_REL}): ${stems}"
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

printf 'canon-core: %s\n' "$summary" >&2            # inspectable under --debug / on stderr

echo "# Engineering rules (injected by canon-core)"
echo "<!-- canon-core: ${summary} -->"
echo
for f in ${INJECT[@]+"${INJECT[@]}"}; do
  echo "<!-- source: ${f#"$RULES_ROOT"/} -->"
  cat "$f"
  echo
done

exit 0
