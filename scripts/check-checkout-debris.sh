#!/usr/bin/env bash
# check-checkout-debris.sh — warn about untracked files aging in a shared checkout
#
# Root cause this guards against: an agent creates files, then checks out a
# different branch without `git add`/commit/stash first. The untracked files
# survive the checkout silently (git never touches untracked files on
# checkout) and pile up across sessions — days later they can break another
# agent's typecheck/build (e.g. a stray e2e spec importing a package that was
# since removed) with nobody able to tell "debris" from "in-progress work".
# Seen in practice: one web repo piled up 132 debris files, one of which broke
# every agent's typecheck; an earlier occurrence of the same pattern needed a
# whole PR just to rescue orphaned e2e specs and planning docs.
#
# This script only DETECTS and REPORTS — it never deletes or moves anything.
# Age alone cannot tell debris from real unfinished work (PR#62 found 3/8
# aged untracked files were still-open, undone work, not debris) — a human
# (Lead) or a QA triage pass must decide per file, same as was done there.
#
# Usage:
#   ./scripts/check-checkout-debris.sh                 # scan every path in projects.json
#   ./scripts/check-checkout-debris.sh his              # scan only the "his" project's paths
#   ./scripts/check-checkout-debris.sh /path/to/repo     # scan one explicit checkout path
#   ./scripts/check-checkout-debris.sh -a 12 his         # override age threshold (hours)
#
# Exit code: 0 = nothing aged past the threshold, 1 = at least one path has aged untracked files.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PROJECTS_FILE="$SCRIPT_DIR/projects.json"

AGE_HOURS=6

while getopts "a:" opt; do
  case "$opt" in
    a) AGE_HOURS="$OPTARG" ;;
    *) echo "Usage: $0 [-a hours] [project-name|path]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))

ARG="${1:-}"

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 2; }
[[ -f "$PROJECTS_FILE" ]] || { echo "Error: $PROJECTS_FILE not found" >&2; exit 2; }

AGE_SECONDS=$(( AGE_HOURS * 3600 ))
NOW=$(date +%s)

# Build the list of checkout paths to scan, de-duplicated (many projects
# reuse the same path under several role keys, e.g. "root" == "api").
declare -a PATHS=()

collect_all_paths() {
  while IFS= read -r p; do
    PATHS+=("$p")
  done < <(jq -r '.projects[].paths[]' "$PROJECTS_FILE" | sort -u)
}

collect_project_paths() {
  local name="$1"
  local found
  found=$(jq -r --arg n "$name" '.projects[$n].paths[]? // empty' "$PROJECTS_FILE")
  if [[ -z "$found" ]]; then
    return 1
  fi
  while IFS= read -r p; do
    PATHS+=("$p")
  done < <(printf '%s\n' "$found" | sort -u)
  return 0
}

if [[ -z "$ARG" ]]; then
  collect_all_paths
elif [[ -d "$ARG" ]]; then
  PATHS=("$ARG")
elif ! collect_project_paths "$ARG"; then
  echo "Error: '$ARG' is neither a known project in projects.json nor an existing directory" >&2
  exit 2
fi

FOUND_DEBRIS=0

for path in "${PATHS[@]}"; do
  [[ -d "$path" ]] || continue
  [[ -d "$path/.git" ]] || continue

  UNTRACKED=$(git -C "$path" status --porcelain 2>/dev/null | grep '^??' | sed 's/^?? //') || true
  [[ -z "$UNTRACKED" ]] && continue

  declare -a AGED=()
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    full="$path/$f"
    [[ -e "$full" ]] || continue
    mtime=$(stat -f "%m" "$full" 2>/dev/null || stat -c "%Y" "$full" 2>/dev/null) || continue
    age=$(( NOW - mtime ))
    if (( age >= AGE_SECONDS )); then
      AGED+=("$f|$age")
    fi
  done <<< "$UNTRACKED"

  if (( ${#AGED[@]} > 0 )); then
    FOUND_DEBRIS=1
    branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "?")
    echo "🟡 $path (branch: $branch) — ${#AGED[@]} untracked file(s) older than ${AGE_HOURS}h:"
    for entry in "${AGED[@]}"; do
      f="${entry%%|*}"
      age="${entry##*|}"
      hrs=$(( age / 3600 ))
      mtime_human=$(date -j -f "%s" "$(( NOW - age ))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || date -d "@$(( NOW - age ))" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "?")
      echo "     ${hrs}h old  ${mtime_human}  $f"
    done
    echo
  fi
  unset AGED
done

if [[ $FOUND_DEBRIS -eq 0 ]]; then
  echo "✓ no untracked files older than ${AGE_HOURS}h found in scanned checkout(s)"
  exit 0
fi

echo "→ this script never deletes/moves files. Report to Lead for a per-file decision"
echo "  (age alone doesn't prove debris — verify against develop/merged PRs before archiving, see PR#62 precedent)."
exit 1
