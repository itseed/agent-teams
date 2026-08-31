#!/usr/bin/env bash
# restore-layout.sh — rebuild the intended 3-column layout without killing any pane
#
# ใช้เมื่อ layout เพี้ยน (เช่น เผลอ resize-pane -y ทับกันจนคอลัมน์บิด) — สร้าง
# layout string ใหม่จากสัดส่วนเดิมของ start-team.sh (Lead[+RTK] | dev roles | support roles)
# แล้ว apply ด้วย `tmux select-layout` ตรงๆ — ไม่มี pane ไหนถูกปิด/สร้างใหม่ agent state ปลอดภัย
#
# ใช้ได้ทั้ง v1 (session "dev-team") และ v2 (session "dev-team-v2") — auto-detect
# จาก tmux session ที่รันอยู่จริง; ถ้ารันอยู่พร้อมกันทั้งคู่ ต้องระบุ --session
#
# Usage:
#   ./scripts/restore-layout.sh
#   ./scripts/restore-layout.sh --session dev-team-v2

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
SESSION_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [--session SESSION_NAME]

Rebuild 3-column layout โดยไม่ปิด/สร้าง pane ใหม่ — ใช้ได้ทั้ง v1 (dev-team) และ
v2 (dev-team-v2) — auto-detect จาก session ที่รันอยู่จริง ถ้ารันอยู่พร้อมกันทั้งคู่
ต้องระบุ --session ตรงๆ
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

command -v python3 >/dev/null || { echo "Error: python3 required (checksum calc)" >&2; exit 1; }
tmux has-session -t "$SESSION" 2>/dev/null || { echo "Error: session '$SESSION' not found" >&2; exit 1; }
[[ -f "$STATE_FILE" ]] || { echo "Error: $STATE_FILE not found" >&2; exit 1; }

DEV_ROLES=(frontend backend mobile devops)
SUPPORT_ROLES=(designer architect qa reviewer)

parse_pane_id() {
  local role="$1"
  grep -i "| ${role} " "$STATE_FILE" | head -1 | awk -F'|' '{gsub(/ /,"",$3); print $3}' || true
}

# Collect existing panes per column (skip roles with no pane in this session)
MID_IDS=(); for r in "${DEV_ROLES[@]}"; do p=$(parse_pane_id "$r"); [[ -n "$p" ]] && tmux list-panes -t "$SESSION" -F '#{pane_id}' | grep -qx "$p" && MID_IDS+=("$p"); done
RIGHT_IDS=(); for r in "${SUPPORT_ROLES[@]}"; do p=$(parse_pane_id "$r"); [[ -n "$p" ]] && tmux list-panes -t "$SESSION" -F '#{pane_id}' | grep -qx "$p" && RIGHT_IDS+=("$p"); done

LEAD_ID="0"
tmux list-panes -t "$SESSION" -F '#{pane_id}' | grep -qx '%0' || LEAD_ID=$(tmux list-panes -t "$SESSION:0.0" -F '#{pane_id}' | head -1 | tr -d '%')

RTK_ID=""
while read -r pid; do
  role=$(tmux show-options -p -t "$pid" @role 2>/dev/null | awk -F'"' '{print $2}')
  [[ "$role" == "RTK Stats" ]] && RTK_ID="$pid"
done < <(tmux list-panes -t "$SESSION" -F '#{pane_id}')

[[ ${#MID_IDS[@]} -gt 0 || ${#RIGHT_IDS[@]} -gt 0 ]] || { echo "Error: ไม่พบ pane ของ dev/support role เลยใน .team-state.md" >&2; exit 1; }

read -r WIN_W WIN_H <<< "$(tmux display-message -t "$SESSION:0" -p '#{window_width} #{window_height}')"

num_id() { echo "${1#%}"; }

# ── column width split (Lead | mid | right) — only among columns that exist ──
NCOLS=1
[[ ${#MID_IDS[@]} -gt 0 ]] && NCOLS=$((NCOLS+1))
[[ ${#RIGHT_IDS[@]} -gt 0 ]] && NCOLS=$((NCOLS+1))
USABLE_W=$((WIN_W - (NCOLS - 1)))
BASE_W=$((USABLE_W / NCOLS))
REM_W=$((USABLE_W % NCOLS))
col_width() { # $1 = 1-indexed column position among existing columns
  local idx="$1" w="$BASE_W"
  [[ "$idx" -le "$REM_W" ]] && w=$((w + 1))
  echo "$w"
}

CUR_X=0
CUR_COL=1

# ── Lead(+RTK) column ──
LEAD_W=$(col_width "$CUR_COL"); CUR_COL=$((CUR_COL+1))
if [[ -n "$RTK_ID" ]]; then
  RTK_H=$(( WIN_H * 30 / 100 ))
  LEAD_H=$(( WIN_H - RTK_H - 1 ))
  LEAD_NODE="${LEAD_W}x${WIN_H},${CUR_X},0[${LEAD_W}x${LEAD_H},${CUR_X},0,$(num_id "%$LEAD_ID"),${LEAD_W}x${RTK_H},${CUR_X},$((LEAD_H+1)),$(num_id "$RTK_ID")]"
else
  LEAD_NODE="${LEAD_W}x${WIN_H},${CUR_X},0,$(num_id "%$LEAD_ID")"
fi
CUR_X=$((CUR_X + LEAD_W + 1))

# ── generic "fill column with N equal rows" node builder ──
build_column_node() {
  local width="$1" x="$2"; shift 2
  local ids=("$@")
  local n=${#ids[@]}
  local avail=$(( WIN_H - (n - 1) ))
  local base=$(( avail / n ))
  local rem=$(( avail % n ))
  local y=0 i h leaves=()
  for ((i=0; i<n; i++)); do
    h=$base
    [[ $i -lt $rem ]] && h=$((h+1))
    leaves+=("${width}x${h},${x},${y},$(num_id "${ids[$i]}")")
    y=$((y + h + 1))
  done
  local joined
  joined=$(IFS=,; echo "${leaves[*]}")
  if [[ $n -eq 1 ]]; then
    echo "${width}x${WIN_H},${x},0,$(num_id "${ids[0]}")"
  else
    echo "${width}x${WIN_H},${x},0[${joined}]"
  fi
}

TOP_CHILDREN=("$LEAD_NODE")

if [[ ${#MID_IDS[@]} -gt 0 ]]; then
  MID_W=$(col_width "$CUR_COL"); CUR_COL=$((CUR_COL+1))
  MID_NODE=$(build_column_node "$MID_W" "$CUR_X" "${MID_IDS[@]}")
  TOP_CHILDREN+=("$MID_NODE")
  CUR_X=$((CUR_X + MID_W + 1))
fi

if [[ ${#RIGHT_IDS[@]} -gt 0 ]]; then
  RIGHT_W=$(col_width "$CUR_COL"); CUR_COL=$((CUR_COL+1))
  RIGHT_NODE=$(build_column_node "$RIGHT_W" "$CUR_X" "${RIGHT_IDS[@]}")
  TOP_CHILDREN+=("$RIGHT_NODE")
fi

TOP_JOINED=$(IFS=,; echo "${TOP_CHILDREN[*]}")
LAYOUT_BODY="${WIN_W}x${WIN_H},0,0{${TOP_JOINED}}"

FULL_LAYOUT=$(python3 - "$LAYOUT_BODY" <<'PYEOF'
import sys
layout = sys.argv[1]
csum = 0
for ch in layout:
    csum = (csum >> 1) + ((csum & 1) << 15)
    csum = (csum + ord(ch)) & 0xffff
print(f"{csum:04x},{layout}")
PYEOF
)

echo "→ Applying layout: $FULL_LAYOUT"
tmux select-layout -t "$SESSION:0" "$FULL_LAYOUT"
echo "✓ Layout restored — no pane killed/created."
echo ""
echo "หมายเหตุ: ถ้า pane border label หาย ให้รัน ./scripts/restore-pane-labels.sh ต่อ"
