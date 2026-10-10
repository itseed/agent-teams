#!/usr/bin/env bash
# team-state.sh — atomic updates to .team-state.md (ลด drift จากการแก้ markdown ด้วยมือ)
#
# Usage:
#   ./scripts/team-state.sh set <role> <status> [task]   # update agent row + timestamp
#   ./scripts/team-state.sh stage <text>                 # update pipeline stage + timestamp
#   ./scripts/team-state.sh show                         # print current state
#
# Examples:
#   ./scripts/team-state.sh set backend working "implement /auth/login (docs/plan/login.md)"
#   ./scripts/team-state.sh set backend idle
#   ./scripts/team-state.sh stage "qa — รอ QA verdict ของ feature login"

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
ROLES=(frontend backend mobile devops designer architect qa reviewer)

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}"; exit 1; }

[[ -f "$STATE_FILE" ]] || { echo "Error: $STATE_FILE not found — run start-team.sh first" >&2; exit 1; }

CMD="${1:-}"; shift || true

touch_timestamp() {
  local ts tmp
  ts=$(date '+%Y-%m-%d %H:%M')
  tmp=$(mktemp)
  sed "s/^_Updated: .*_$/_Updated: ${ts}_/" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

case "$CMD" in
  set)
    ROLE="${1:-}"; STATUS="${2:-}"; TASK="${3:-—}"
    [[ -n "$ROLE" && -n "$STATUS" ]] || usage
    if [[ ! " ${ROLES[*]} " == *" $ROLE "* ]]; then
      echo "Error: unknown role '$ROLE' (valid: ${ROLES[*]})" >&2; exit 1
    fi
    if ! grep -qE "^\| *${ROLE} " "$STATE_FILE"; then
      echo "Error: no table row for role '$ROLE' in $STATE_FILE" >&2; exit 1
    fi
    # Replace status ($3) + task ($4) in the role's table row, keep pane id ($2)
    # "|" in text would split the markdown table → replace with "/"; pass via ENVIRON
    # (awk -v would interpret backslash escapes in the task text)
    TMP=$(mktemp)
    TS_STATUS="${STATUS//|//}" TS_TASK="${TASK//|//}" \
    awk -F'|' -v OFS='|' -v role="$ROLE" '
      $2 ~ "^ *"role" *$" { $4 = " " ENVIRON["TS_STATUS"] " "; $5 = " " ENVIRON["TS_TASK"] " " }
      { print }
    ' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    touch_timestamp
    echo "✓ $ROLE → $STATUS${TASK:+ ($TASK)}"
    ;;
  stage)
    STAGE="${1:-}"
    [[ -n "$STAGE" ]] || usage
    # Replace the single line after "## Pipeline Stage"
    TMP=$(mktemp)
    TS_STAGE="$STAGE" awk '
      prev == "## Pipeline Stage" { print ENVIRON["TS_STAGE"]; prev = $0; next }
      { print; prev = $0 }
    ' "$STATE_FILE" > "$TMP" && mv "$TMP" "$STATE_FILE"
    touch_timestamp
    echo "✓ pipeline stage → $STAGE"
    ;;
  show)
    cat "$STATE_FILE"
    ;;
  *)
    usage
    ;;
esac
