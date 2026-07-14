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
# When present and resolving to a non-empty set of names, the manifest is
# AUTHORITATIVE: it NARROWS injection to exactly those modules (still warning for
# any listed name absent from the bundle) and WINS over tier detection — an
# explicit manifest is the user's deliberate choice, so universal is not
# force-added and detection is not applied. A canon.txt listing every module
# therefore reproduces the pre-v2.0 inject-everything behavior.
#
# When canon.txt is ABSENT (or resolves to zero valid names) we use the v2.0
# DEFAULT resolution instead of the full bundle: tier-1 `universal/` modules are
# always injected, and each family tier (e.g. `python/`) is injected only when
# the consuming project is DETECTED as that kind of project (see the detection
# table below). This narrows the always-on surface to what the project needs.
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

# --- Tier detection (v2.0 default resolution) ------------------------------
# A module's tier == the name of its parent directory (universal/, python/, …),
# which equals its frontmatter `tier:` by repo invariant — so we infer the tier
# from the directory and never parse frontmatter here.
#
# DETECTION TABLE — keyed by family tier name. To gate a NEW family (e.g. rust,
# node), add a `case` arm to detect_family below; that is the whole change.
# Contract of detect_family "<tier>":
#   sets DETECT_RESULT = inject | skip
#   sets DETECT_REASON = human-readable clause for the injection manifest
# An unknown family tier with NO arm falls to the default `*)` branch and is
# injected BY DEFAULT — we fail toward inclusion and never silently drop a rule
# we don't know how to gate; the manifest records that it was an ungated tier.

# Detect a Python project under $project_dir. Checks the project root first
# (fast path), then a bounded shallow search (maxdepth 3, stop at first hit).
# On success sets PY_SIGNAL to the marker that matched; returns 0/1.
python_project_detected() {
  PY_SIGNAL=""
  # Root-level marker files, in priority order (deterministic signal name).
  for _f in pyproject.toml setup.py setup.cfg Pipfile poetry.lock tox.ini; do
    if [ -f "${project_dir}/${_f}" ]; then PY_SIGNAL="$_f"; return 0; fi
  done
  for _f in "${project_dir}"/requirements*.txt; do
    if [ -f "$_f" ]; then PY_SIGNAL="$(basename "$_f")"; return 0; fi
  done
  # Bounded shallow search for nested markers or any *.py file.
  _hit="$(find "$project_dir" -maxdepth 3 \( \
      -name pyproject.toml -o -name setup.py -o -name setup.cfg \
      -o -name Pipfile -o -name poetry.lock -o -name tox.ini \
      -o -name 'requirements*.txt' -o -name '*.py' \) -print 2>/dev/null \
    | head -n 1)"
  if [ -n "$_hit" ]; then PY_SIGNAL="$(basename "$_hit")"; return 0; fi
  return 1
}

detect_family() {
  _tier="$1"
  case "$_tier" in
    python)
      if python_project_detected; then
        DETECT_RESULT="inject"; DETECT_REASON="python detected via ${PY_SIGNAL}"
      else
        DETECT_RESULT="skip"; DETECT_REASON="python skipped — no Python project markers"
      fi
      ;;
    *)
      # No detection rule for this family tier — inject by default.
      DETECT_RESULT="inject"
      DETECT_REASON="${_tier} injected by default — no detection rule"
      ;;
  esac
}

# Decide what actually gets injected: authoritative narrow, or v2.0 default.
narrowed=0
fallback=0
defaults_desc=""
if [ "$manifest_present" -eq 1 ] && [ "${#INJECT[@]}" -gt 0 ]; then
  narrowed=1
else
  if [ "$manifest_present" -eq 1 ]; then
    fallback=1
    warnings+=("${MANIFEST_REL} selected 0 valid modules — falling back to canon defaults (universal always-on; family tiers only when detected) instead of stripping all rules.")
  fi

  # Collect the distinct family (non-universal) tiers in sorted bundle order,
  # then run detection once per tier (parallel arrays; bash 3.2 has no maps).
  FAM_TIERS=(); FAM_RESULT=(); FAM_REASON=()
  for m in ${MODULES[@]+"${MODULES[@]}"}; do
    t="$(basename "$(dirname "$m")")"
    [ "$t" = "universal" ] && continue
    seen=0
    for x in ${FAM_TIERS[@]+"${FAM_TIERS[@]}"}; do
      [ "$x" = "$t" ] && { seen=1; break; }
    done
    [ "$seen" -eq 0 ] && FAM_TIERS+=("$t")
  done
  for t in ${FAM_TIERS[@]+"${FAM_TIERS[@]}"}; do
    detect_family "$t"
    FAM_RESULT+=("$DETECT_RESULT")
    FAM_REASON+=("$DETECT_REASON")
  done

  # Build the injected set: universal always; each family only if detected.
  INJECT=()
  for m in ${MODULES[@]+"${MODULES[@]}"}; do
    t="$(basename "$(dirname "$m")")"
    if [ "$t" = "universal" ]; then INJECT+=("$m"); continue; fi
    i=0; res="inject"
    for x in ${FAM_TIERS[@]+"${FAM_TIERS[@]}"}; do
      if [ "$x" = "$t" ]; then res="${FAM_RESULT[$i]}"; break; fi
      i=$((i + 1))
    done
    [ "$res" = "inject" ] && INJECT+=("$m")
  done

  # Compose the per-tier "defaults" clause for the manifest line.
  defaults_desc="universal always-on"
  for reason in ${FAM_REASON[@]+"${FAM_REASON[@]}"}; do
    defaults_desc="${defaults_desc}; ${reason}"
  done
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
  summary="injected ${count}/${total} modules (fallback: ${MANIFEST_REL} selected 0 valid modules — using defaults: ${defaults_desc}): ${stems}"
else
  summary="injected ${count}/${total} modules (defaults: ${defaults_desc}): ${stems}"
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
