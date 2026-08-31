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

# ──────────────────────────────────────────────────────────────
# Resolve session name: --session > tmux reality (v1/v2) > .team-state.md Mode (last-resort guess)
# ──────────────────────────────────────────────────────────────
resolve_session() {
  if [[ -n "$SESSION_OVERRIDE" ]]; then
    echo "$SESSION_OVERRIDE"
    return 0
  fi

  local v1_up=0 v2_up=0
  tmux has-session -t dev-team    2>/dev/null && v1_up=1
  tmux has-session -t dev-team-v2 2>/dev/null && v2_up=1

  if [[ "$v1_up" -eq 1 && "$v2_up" -eq 1 ]]; then
    echo "Error: ทั้ง 'dev-team' (v1) และ 'dev-team-v2' (v2) กำลังรันอยู่พร้อมกัน — ระบุ session ที่ต้องการด้วย --session dev-team หรือ --session dev-team-v2" >&2
    exit 1
  elif [[ "$v1_up" -eq 1 ]]; then
    echo "dev-team"; return 0
  elif [[ "$v2_up" -eq 1 ]]; then
    echo "dev-team-v2"; return 0
  fi

  if [[ -f "$STATE_FILE" ]] && grep -q "_Mode: v2" "$STATE_FILE"; then
    echo "dev-team-v2"
  else
    echo "dev-team"
  fi
}

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

PANE_FRONTEND=$(parse_pane_id "frontend")
PANE_DESIGNER=$(parse_pane_id "designer")
PANE_ARCHITECT=$(parse_pane_id "architect")
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
apply_label "$PANE_FRONTEND" "Frontend${LABEL_SUFFIX}" "cyan"
apply_label "$PANE_DESIGNER" "Designer${LABEL_SUFFIX}" "colour211"
apply_label "$PANE_ARCHITECT" "Architect${LABEL_SUFFIX}" "colour141"
apply_label "$PANE_BACKEND"  "Backend${LABEL_SUFFIX}"  "blue"
apply_label "$PANE_MOBILE"   "Mobile${LABEL_SUFFIX}"   "magenta"
apply_label "$PANE_DEVOPS"   "DevOps${LABEL_SUFFIX}"   "green"
apply_label "$PANE_QA"       "QA${LABEL_SUFFIX}"       "colour208"
apply_label "$PANE_REVIEWER" "Reviewer${LABEL_SUFFIX}" "red"

echo ""
echo "Done — pane labels restored from .team-state.md"
