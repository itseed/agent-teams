#!/usr/bin/env bash
# set-pane-workdir.sh — ตั้ง pane option @workdir ของ role (ให้ pane-border แสดง branch ของ repo ที่ agent ทำงานอยู่)
#
# Lead เรียกก่อน dispatch งาน เมื่อ repo ที่ agent ต้องทำต่างจาก default (ดู CLAUDE.md "วิธีส่งงานให้ teammate")
#
# Usage: set-pane-workdir.sh <role> <path> [--session NAME]
#   <role>  frontend|backend|mobile|devops|designer|architect|qa|reviewer (ตรงกับ pane option @role แบบไม่สนตัวพิมพ์)
#   <path>  directory ของ repo (ต้องมีอยู่จริง)
# ไม่สร้าง/kill pane — แก้แค่ display option

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SESSION="dev-team"
ROLE="" ; WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --session) SESSION="${2:?--session ต้องระบุชื่อ}"; shift ;;
    *) if [[ -z "$ROLE" ]]; then ROLE="$1"; elif [[ -z "$WORKDIR" ]]; then WORKDIR="$1"; else echo "Unexpected arg: $1" >&2; exit 1; fi ;;
  esac
  shift
done

[[ -n "$ROLE" && -n "$WORKDIR" ]] || { echo "Usage: $(basename "$0") <role> <path> [--session NAME]" >&2; exit 1; }
[[ -d "$WORKDIR" ]] || { echo "Error: path ไม่มีอยู่: $WORKDIR" >&2; exit 1; }
tmux has-session -t "$SESSION" 2>/dev/null || { echo "Error: ไม่พบ tmux session '$SESSION'" >&2; exit 1; }

want=$(printf '%s' "$ROLE" | tr '[:upper:]' '[:lower:]')
pane_id=""
while IFS='|' read -r pid label; do
  l=$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')
  # label อาจมี suffix (เช่น v2) — match ทั้งคำเต็มหรือขึ้นต้นด้วย role
  if [[ "$l" == "$want" || "$l" == "$want"* ]]; then pane_id="$pid"; break; fi
done < <(tmux list-panes -s -t "$SESSION" -F '#{pane_id}|#{@role}')

[[ -n "$pane_id" ]] || { echo "Error: ไม่พบ pane ที่ @role = '$ROLE' ใน session '$SESSION'" >&2; exit 1; }

tmux set-option -p -t "$pane_id" @workdir "$WORKDIR"
branch=$("$SCRIPT_DIR/pane-branch.sh" "$WORKDIR" "")
echo "✅ $ROLE ($pane_id) @workdir = $WORKDIR  branch: ${branch:-<ไม่ใช่ git repo>}"
