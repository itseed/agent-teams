#!/usr/bin/env bash
# check-stuck-panes.sh — scan every teammate pane for a stuck interactive prompt
# (AskUserQuestion menu, a permission dialog, a bare y/n confirm) so Lead doesn't
# have to capture-pane each one by hand.
#
# Root cause this guards against: a teammate's tool call (AskUserQuestion, a
# permission prompt, an interactive CLI confirm) blocks its ENTIRE turn waiting
# for a menu selection in its own pane. Unlike a normal tmux-paste status report,
# nothing pushes this to Lead automatically — Lead only finds out by looking.
#
# Usage:
#   ./scripts/check-stuck-panes.sh          # scan all roles in .team-state.md
#   ./scripts/check-stuck-panes.sh backend  # scan one role only
#
# Exit code: 0 = none stuck, 1 = at least one pane looks stuck (prints which).

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
ROLES=(frontend backend mobile devops designer architect qa reviewer)

[[ -f "$STATE_FILE" ]] || { echo "Error: $STATE_FILE not found — run start-team.sh first" >&2; exit 1; }

ONLY_ROLE="${1:-}"

# Patterns that mean "a menu/confirm is sitting here waiting for input, not normal output"
STUCK_PATTERNS='Enter to select|Do you want to proceed|Press up to edit queued|\(y/n\)|\[y/N\]|❯ [0-9]+\.'

FOUND_STUCK=0

for role in "${ROLES[@]}"; do
  [[ -n "$ONLY_ROLE" && "$role" != "$ONLY_ROLE" ]] && continue

  # Pull this role's pane id straight from the table (col 2), same convention team-state.sh uses
  PANE=$(awk -F'|' -v role="$role" '$2 ~ "^ *"role" *$" { gsub(/ /,"",$3); print $3 }' "$STATE_FILE")
  [[ -z "$PANE" || "$PANE" == "—" ]] && continue

  if ! CAPTURE=$(tmux capture-pane -t "$PANE" -p 2>/dev/null); then
    echo "⚠️  $role ($PANE) — pane not found, skipping"
    continue
  fi

  TAIL=$(echo "$CAPTURE" | tail -15)
  if echo "$TAIL" | grep -qE "$STUCK_PATTERNS"; then
    FOUND_STUCK=1
    echo "🔴 $role ($PANE) — looks stuck on an interactive prompt:"
    echo "$TAIL" | sed 's/^/     /'
    echo
  fi
done

if [[ $FOUND_STUCK -eq 0 ]]; then
  echo "✓ no stuck prompts found in any active pane"
  exit 0
fi

echo "→ resolve stuck panes directly: tmux send-keys -t <pane> Down / Enter (pick the safe option), or capture-pane -p to read the full question first."
exit 1
