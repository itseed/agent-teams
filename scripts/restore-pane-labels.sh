#!/usr/bin/env bash
# restore-pane-labels.sh — re-apply @role + @role_color to existing panes
#
# ใช้เมื่อ pane border label หลุดหลัง auto-compact หรือ session glitch
# ไม่สร้าง pane ใหม่ — อ่าน .team-state.md เพื่อดู stable %IDs แล้ว re-apply ทับ
#
# ใช้ได้ทั้ง v1 (session "dev-team") และ v2 (session "dev-team-v2") — auto-detect
# จาก tmux session ที่รันอยู่จริง; ถ้ารันอยู่พร้อมกันทั้งคู่ ต้องระบุ --session
#
# Usage:
#   ./scripts/restore-pane-labels.sh
#   ./scripts/restore-pane-labels.sh --session dev-team-v2

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
SESSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--session SESSION_NAME]

Re-apply @role + @role_color ให้ pane ที่มีอยู่แล้ว — ไม่สร้าง pane ใหม่
ใช้ได้ทั้ง v1 (dev-team) และ v2 (dev-team-v2) — auto-detect จาก session ที่รันอยู่จริง
ถ้ารันอยู่พร้อมกันทั้งคู่ ต้องระบุ --session ตรงๆ
EOF
      exit 0
      ;;
    --session)
      SESSION_OVERRIDE="${2:-}"
      [[ -n "$SESSION_OVERRIDE" ]] || { echo "Error: --session ต้องระบุชื่อ session" >&2; exit 1; }
      shift
      ;;
    --session=*)
      SESSION_OVERRIDE="${1#--session=}"
      ;;
    *)
      echo "Unknown option: $1 (run with --help)" >&2
      exit 1
      ;;
  esac
  shift
done

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/scripts/lib/common.sh"   # resolve_session: --session > tmux reality (v1/v2) > .team-state.md Mode

SESSION="$(resolve_session)"

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Error: session '$SESSION' not found" >&2
  exit 1
fi

if [[ ! -f "$STATE_FILE" ]]; then
  echo "Error: .team-state.md not found at $SCRIPT_DIR" >&2
  exit 1
fi

# v1 vs v2: labels ต่างกัน (v2 pane เป็น log viewer ชื่อ "<Role> log")
MODE="v1"
if grep -qi '^_Mode: v2' "$STATE_FILE"; then
  MODE="v2"
fi
LABEL_SUFFIX=""
if [[ "$MODE" == "v2" ]]; then
  LABEL_SUFFIX=" log"
fi
echo "Detected mode: $MODE"

# Parse stable pane IDs from .team-state.md
# Expects lines like: | frontend | %3    | idle   | —  |
parse_pane_id() {
  # `|| true` กัน set -e/pipefail ฆ่า script เมื่อ role ไม่มีแถวใน state
  # (ทีม role-selective spawn มาไม่ครบ 8 เป็นเรื่องปกติ) — apply_label จะ skip ให้เอง
  local role="$1"
  grep -i "| ${role} " "$STATE_FILE" | head -1 | awk -F'|' '{gsub(/ /,"",$3); print $3}' || true
}

# Re-apply pane border options (window level)
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
# border: "● <Role>  ⎇ <branch>" — branch มาจาก scripts/pane-branch.sh (อ่านจาก pane option @workdir,
# fallback pane_current_path; ไม่ใช่ repo = ไม่แสดง ⎇). status-interval 5s = รอบ refresh ของ #() (set ระดับ session)
PANE_BORDER_FORMAT=" #[fg=#{@role_color},bold]● #{@role}#[default]#($SCRIPT_DIR/scripts/pane-branch.sh -l \"#{@workdir}\" \"#{pane_current_path}\") "
tmux set-option -w -t "$SESSION:0" pane-border-format "$PANE_BORDER_FORMAT"
tmux set-option -t "$SESSION" status-interval 5

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
for r in "${ALL_ROLES[@]}"; do
  apply_label "$(parse_pane_id "$r")" "$(role_label "$r")${LABEL_SUFFIX}" "$(role_color "$r")"
done

echo ""
echo "Done — pane labels restored from .team-state.md"
