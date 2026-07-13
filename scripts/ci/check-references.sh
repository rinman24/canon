#!/usr/bin/env bash
# Reference-integrity check: every repo-relative link target in tracked
# markdown must exist in the tree.
#
# Scans `git ls-files '*.md'` (untracked working docs are neither scanned nor
# required to exist) for markdown links `](target)` and @import-style lines
# (`@path` at the start of a line). Fenced code blocks are excluded — they hold
# examples for consuming repos, not references into this one.
#
# Skips external targets (http://, https://, mailto:) and pure #anchors,
# strips #fragments, URL-decodes %XX escapes, and resolves each target
# relative to the linking file's directory. On failure prints
# `file: broken-target` lines and exits 1. Offline and deterministic.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Print a file's content with fenced code blocks (``` / ~~~) removed.
strip_fences() {
  awk '/^[[:space:]]*(```|~~~)/ { fence = !fence; next } !fence' "$1"
}

# Decode %XX escapes (e.g. Canon%20Brand%20Kit.html). %b turns \xXX into bytes.
urldecode() {
  printf '%b' "${1//%/\\x}"
}

# Emit one candidate target per line for a file: markdown-link targets and
# @import paths. `|| true`: no matches is fine.
extract_targets() {
  strip_fences "$1" | grep -oE '\]\([^()]*\)' | sed -e 's/^](//' -e 's/)$//' -e 's/[[:space:]].*$//' || true
  strip_fences "$1" | grep -oE '^@[^[:space:]]+' | sed 's/^@//' || true
}

status=0
checked=0

while IFS= read -r -d '' md; do
  dir="$(dirname "$md")"
  while IFS= read -r raw; do
    [ -n "$raw" ] || continue
    target="$raw"
    # Unwrap <target> form.
    case "$target" in "<"*">") target="${target#<}"; target="${target%>}" ;; esac
    # External schemes and in-page anchors are out of scope.
    case "$target" in
      http://*|https://*|mailto:*) continue ;;
      "#"*) continue ;;
    esac
    target="${target%%#*}"   # drop any #fragment
    [ -n "$target" ] || continue
    target="$(urldecode "$target")"
    checked=$((checked + 1))
    if [ ! -e "$dir/$target" ]; then
      echo "$md: $raw"
      status=1
    fi
  done < <(extract_targets "$md")
done < <(git ls-files -z -- '*.md')

if [ "$status" -ne 0 ]; then
  echo "check-references: FAIL — the target(s) above do not exist in the tree." >&2
else
  echo "check-references: OK ($checked repo-relative reference(s) verified)."
fi
exit "$status"
