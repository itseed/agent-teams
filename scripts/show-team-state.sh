#!/usr/bin/env bash
# show-team-state.sh — UserPromptSubmit hook: inject .team-state.md into every Lead prompt
#
# Resolves the repo from the script's own path (works from any cwd, e.g. after `cd dashboard/`)
# and flags the table as stale when the team's tmux session is gone — the file outlives
# stop-team.sh / a crashed tmux server, and a stale table makes the Lead dispatch into dead panes.

REPO_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="${TEAM_STATE_FILE:-$REPO_DIR/.team-state.md}"

if [[ ! -f "$STATE_FILE" ]]; then
  echo "[WARNING] .team-state.md not found — run start-team.sh first"
  exit 0
fi

SESSION="dev-team"
grep -qi '^_Mode: v2' "$STATE_FILE" && SESSION="dev-team-v2"

echo "=== TEAM STATE ==="
if ! tmux has-session -t "=$SESSION" 2>/dev/null; then
  echo "[STALE] tmux session '$SESSION' ไม่ได้รันอยู่ — ตารางด้านล่างเป็นสถานะเก่า pane เหล่านี้ไม่มีแล้ว"
  echo "        ห้ามส่งงานเข้า pane · ต้องการทีม → ให้ผู้ใช้รัน ./start-team.sh"
  echo
fi
cat "$STATE_FILE"
