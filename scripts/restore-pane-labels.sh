#!/usr/bin/env bash
# restore-pane-labels.sh — re-apply @role + @role_color to existing panes
#
# ใช้เมื่อ pane border label หลุดหลัง auto-compact หรือ session glitch
# ไม่สร้าง pane ใหม่ — อ่าน .team-state.md เพื่อดู stable %IDs แล้ว re-apply ทับ
#
# Usage:
#   ./scripts/restore-pane-labels.sh

set -euo pipefail

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Error: session '$SESSION' not found" >&2
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: .team-state.md not found at $SCRIPT_DIR" >&2
  exit 1
fi

# Parse stable pane IDs from .team-state.md
# Expects lines like: | frontend | %3    | idle   | —  |
parse_pane_id() {
  local role="$1"
  grep -i "| ${role} " "$STATE_FILE" | head -1 | awk -F'|' '{gsub(/ /,"",$3); print $3}'
}

PANE_FRONTEND=$(parse_pane_id "frontend")
PANE_DESIGNER=$(parse_pane_id "designer")
PANE_BACKEND=$(parse_pane_id "backend")
PANE_MOBILE=$(parse_pane_id "mobile")
PANE_DEVOPS=$(parse_pane_id "devops")
PANE_QA=$(parse_pane_id "qa")
PANE_REVIEWER=$(parse_pane_id "reviewer")

# Re-apply pane border options (window level)
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "

# Lead pane (index 0 is always stable)
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# Apply role labels to each pane by stable %ID
apply_label() {
  local pane_id="$1" role="$2" color="$3"
  if [[ -z "$pane_id" ]]; then
    echo "  ⚠️  $role — pane ID not found in .team-state.md (skipped)"
    return
  fi
  if ! tmux set-option -p -t "$pane_id" @role "$role" 2>/dev/null; then
    echo "  ⚠️  $role ($pane_id) — pane not found in session (skipped)"
    return
  fi
  tmux set-option -p -t "$pane_id" @role_color "$color"
  echo "  ✅ $role ($pane_id)"
}

echo "Restoring pane labels in session '$SESSION'..."
apply_label "$PANE_FRONTEND" "Frontend" "cyan"
apply_label "$PANE_DESIGNER" "Designer" "colour211"
apply_label "$PANE_BACKEND"  "Backend"  "blue"
apply_label "$PANE_MOBILE"   "Mobile"   "magenta"
apply_label "$PANE_DEVOPS"   "DevOps"   "green"
apply_label "$PANE_QA"       "QA"       "colour208"
apply_label "$PANE_REVIEWER" "Reviewer" "red"

echo ""
echo "Done — pane labels restored from .team-state.md"
