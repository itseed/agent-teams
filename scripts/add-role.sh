#!/usr/bin/env bash
# add-role.sh — เพิ่ม agent pane role ใหม่เข้า session ที่รันอยู่ (v1 เท่านั้น)
#
# นี่คือ "ทางเดียว" ที่อนุญาตให้สร้าง pane เพิ่มหลัง start-team.sh —
# Lead ห้าม tmux split-window เองเด็ดขาด (layout เพี้ยน + state ไม่ตรง)
#
# Usage:
#   ./scripts/add-role.sh <role> [project]
#
#   role      หนึ่งใน: frontend backend mobile devops designer architect qa reviewer
#   project   ชื่อ project ใน projects.json (ถ้าไม่ระบุ อ่านจาก .team-state.md
#             แล้ว fallback เป็น field "active")
#
# Session name: hardcoded "dev-team" โดยตั้งใจ — สคริปต์นี้ spawn Claude interactive
# process ใหม่เข้า pane (role_cmd) ซึ่งเป็นสถาปัตยกรรมของ v1 เท่านั้น และ
# guard ไว้แล้วด้านล่าง (grep "_Mode: v2" → error + exit) ไม่ให้รันกับ v2 session
# (dev-team-v2, log-viewer panes) เลย จึงไม่ต้อง resolve_session() แบบ shared scripts อื่น

set -euo pipefail

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/scripts/lib/common.sh"   # ALL_ROLES, role_*, provision_agent_dir, auto_trust (ตรงกับ start-team.sh)

ROLE="${1:-}"
PROJECT_ARG="${2:-}"

[[ -n "$ROLE" ]] || { echo "Usage: $(basename "$0") <role> [project]" >&2; exit 1; }
if ! is_valid_role "$ROLE"; then
  echo "Error: unknown role '$ROLE' (valid: ${ALL_ROLES[*]})" >&2; exit 1
fi

command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "Error: jq not found" >&2; exit 1; }
tmux has-session -t "$SESSION" 2>/dev/null || { echo "Error: session '$SESSION' not found — run start-team.sh first" >&2; exit 1; }
[[ -f "$STATE_FILE" ]] || { echo "Error: $STATE_FILE not found" >&2; exit 1; }
[[ -f "$PROJECTS_JSON" ]] || { echo "Error: $PROJECTS_JSON not found" >&2; exit 1; }

if grep -qi '^_Mode: v2' "$STATE_FILE"; then
  echo "Error: session นี้เป็น v2 (log-viewer panes) — spawn agent ผ่าน Agent tool ไม่ใช่ add-role.sh" >&2
  exit 1
fi

if grep -qE "^\| *${ROLE} " "$STATE_FILE"; then
  echo "Error: role '$ROLE' มี pane อยู่แล้ว (ดู .team-state.md)" >&2
  exit 1
fi

# ──────────────────────────────────────────────────────────────
# Resolve project (arg > .team-state.md "Active Project" > projects.json .active)
# ──────────────────────────────────────────────────────────────
PROJECT="$PROJECT_ARG"
if [[ -z "$PROJECT" ]]; then
  PROJECT=$(awk '/^## Active Project/{getline; if (match($0, /\*\*[^*]+\*\*/)) { print substr($0, RSTART+2, RLENGTH-4); exit } }' "$STATE_FILE" || true)
fi
if [[ -z "$PROJECT" ]] || ! jq -e --arg p "$PROJECT" '.projects[$p]' "$PROJECTS_JSON" >/dev/null 2>&1; then
  PROJECT=$(jq -r '.active' "$PROJECTS_JSON")
fi
jq -e --arg p "$PROJECT" '.projects[$p]' "$PROJECTS_JSON" >/dev/null || {
  echo "Error: project '$PROJECT' not found in projects.json" >&2; exit 1; }

echo "→ Adding role '$ROLE' (project: $PROJECT)"

provision_agent_dir "$ROLE" "$PROJECT" "$PROJECTS_JSON"

# ──────────────────────────────────────────────────────────────
# Find a sibling pane in the same column group to split from
# ──────────────────────────────────────────────────────────────
column_of() {
  if [[ " ${DEV_ROLES[*]} " == *" $1 "* ]]; then echo "dev"; else echo "support"; fi
}

pane_of_role() {
  # ดึง pane %ID ของ role จากตาราง .team-state.md ($3 = Pane ID column)
  grep -E "^\| *${1} " "$STATE_FILE" | head -1 | awk -F'|' '{gsub(/ /,"",$3); print $3}'
}

SIBLING_PANE=""
MY_COL=$(column_of "$ROLE")
for r in "${ALL_ROLES[@]}"; do
  [[ "$r" == "$ROLE" ]] && continue
  [[ "$(column_of "$r")" == "$MY_COL" ]] || continue
  p=$(pane_of_role "$r" || true)
  if [[ -n "$p" ]] && tmux display-message -t "$p" -p '#{pane_id}' >/dev/null 2>&1; then
    SIBLING_PANE="$p"   # เอาตัวสุดท้ายที่เจอ = ล่างสุดของคอลัมน์
  fi
done

# ──────────────────────────────────────────────────────────────
# Split pane: ใต้ sibling ในคอลัมน์เดียวกัน หรือคอลัมน์ใหม่ขวาสุดถ้าไม่มี
# ──────────────────────────────────────────────────────────────
if [[ -n "$SIBLING_PANE" ]]; then
  NEW_PANE=$(tmux split-window -t "$SIBLING_PANE" -v -l 50% -c "/tmp/agent-${ROLE}" -P -F '#{pane_id}' "$(role_cmd "$ROLE")")
else
  # ไม่มี role ในกลุ่มคอลัมน์เดียวกันเลย → เปิดคอลัมน์ใหม่จาก pane ขวาสุดของ window
  RIGHTMOST=$(tmux list-panes -t "$SESSION:0" -F '#{pane_right} #{pane_id}' | sort -n | tail -1 | awk '{print $2}')
  NEW_PANE=$(tmux split-window -t "$RIGHTMOST" -h -c "/tmp/agent-${ROLE}" -P -F '#{pane_id}' "$(role_cmd "$ROLE")")
fi

tmux set-option -p -t "$NEW_PANE" @role "$(role_label "$ROLE")"
tmux set-option -p -t "$NEW_PANE" @role_color "$(role_color "$ROLE")"

# @workdir default จาก projects.json (frontend->web, backend->api, mobile->mobile; อื่นว่าง) — ใช้แสดง branch บน border
_wd=$(role_workdir "$ROLE" "$PROJECT" "$PROJECTS_JSON")
if [[ -n "$_wd" ]]; then tmux set-option -p -t "$NEW_PANE" @workdir "$_wd"; fi

# ──────────────────────────────────────────────────────────────
# Auto-answer trust prompt (new /tmp dir → Claude asks once)
# ──────────────────────────────────────────────────────────────
auto_trust "$NEW_PANE" &

# ──────────────────────────────────────────────────────────────
# Append pane map to the new agent's CLAUDE.md (Lead + ทีมปัจจุบันจาก state)
# ──────────────────────────────────────────────────────────────
append_pane_map() {
  local rows="| Lead      | \`$SESSION:0.0\` |"
  local r p
  for r in "${ALL_ROLES[@]}"; do
    if [[ "$r" == "$ROLE" ]]; then
      p="$NEW_PANE"
    else
      p=$(pane_of_role "$r" || true)
      [[ -n "$p" ]] || continue
    fi
    rows="${rows}
| $r | \`$p\` |"
  done

  cat >> "/tmp/agent-${ROLE}/CLAUDE.md" <<MAP

---

## Pane Addresses (stable ID — ใช้ตัวนี้เสมอ)
| Role      | Stable Pane ID       |
|-----------|----------------------|
$rows

> ใช้ stable %ID เหล่านี้โดยตรงกับ tmux — ไม่ใช้ numeric index (0.N) เพราะ RTK เลื่อน +1
> ดู .team-state.md เพื่อ refresh ทุกครั้งหลัง session restart
MAP
}
append_pane_map

# ──────────────────────────────────────────────────────────────
# Register row in .team-state.md (แทรกท้ายตาราง Agents in Panes)
# ──────────────────────────────────────────────────────────────
register_in_state() {
  local tmp
  tmp=$(mktemp)
  awk -v row="| $ROLE | $NEW_PANE | idle | — |" '
    { lines[NR] = $0 }
    /^## Agents in Panes/ { in_sec = 1 }
    in_sec && /^\|/ { last_row = NR }
    in_sec && /^## / && !/^## Agents in Panes/ { in_sec = 0 }
    END {
      for (i = 1; i <= NR; i++) {
        print lines[i]
        if (i == last_row) print row
      }
    }
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  # เอา role นี้ออกจากบรรทัด "Role ที่ไม่ได้ spawn: ..." (ถ้าว่างแล้ว ลบทั้งบรรทัด)
  tmp=$(mktemp)
  awk -v role="$ROLE" '
    /^Role ที่ไม่ได้ spawn: / {
      split($0, parts, " — "); head = parts[1]; rest = substr($0, length(head) + 1)
      sub(/^Role ที่ไม่ได้ spawn: /, "", head)
      n = split(head, rs, " "); out = ""
      for (i = 1; i <= n; i++) if (rs[i] != role) out = out (out == "" ? "" : " ") rs[i]
      if (out == "") next
      print "Role ที่ไม่ได้ spawn: " out rest; next
    }
    { print }
  ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

  # อัปเดต timestamp
  tmp=$(mktemp)
  sed "s/^_Updated: .*_$/_Updated: $(date '+%Y-%m-%d %H:%M')_/" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
register_in_state

echo ""
echo "✓ Role '$ROLE' added → pane $NEW_PANE (/tmp/agent-${ROLE})"
echo "  .team-state.md updated — Lead ใช้ pane ID นี้ส่งงานได้เลยหลัง agent พร้อม (รอ trust prompt ~5s)"
