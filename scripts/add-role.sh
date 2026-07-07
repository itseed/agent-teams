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

set -euo pipefail

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
STATE_FILE="$SCRIPT_DIR/.team-state.md"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"

ALL_ROLES=(frontend backend mobile devops designer architect qa reviewer)
DEV_ROLES=(frontend backend mobile devops)
SUPPORT_ROLES=(designer architect qa reviewer)

CLAUDE_CMD="claude --model claude-sonnet-5 --dangerously-skip-permissions; read"
CLAUDE_CMD_HAIKU="claude --model claude-haiku-4-5-20251001 --dangerously-skip-permissions; read"

ROLE="${1:-}"
PROJECT_ARG="${2:-}"

[[ -n "$ROLE" ]] || { echo "Usage: $(basename "$0") <role> [project]" >&2; exit 1; }
if [[ " ${ALL_ROLES[*]} " != *" $ROLE "* ]]; then
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

# ──────────────────────────────────────────────────────────────
# Per-role attributes (ให้ตรงกับ start-team.sh)
# ──────────────────────────────────────────────────────────────
role_label() {
  case "$1" in
    frontend) echo "Frontend" ;;  backend) echo "Backend" ;;
    mobile)   echo "Mobile"   ;;  devops)  echo "DevOps"  ;;
    designer) echo "Designer" ;;  architect) echo "Architect" ;;
    qa)       echo "QA"       ;;  reviewer) echo "Reviewer" ;;
  esac
}
role_color() {
  case "$1" in
    frontend) echo "cyan"      ;;  backend)   echo "blue"      ;;
    mobile)   echo "magenta"   ;;  devops)    echo "green"     ;;
    designer) echo "colour211" ;;  architect) echo "colour141" ;;
    qa)       echo "colour208" ;;  reviewer)  echo "red"       ;;
  esac
}
role_cmd() {
  case "$1" in
    designer) echo "$CLAUDE_CMD_HAIKU" ;;
    *)        echo "$CLAUDE_CMD" ;;
  esac
}

# ──────────────────────────────────────────────────────────────
# Provision /tmp/agent-<role>/ + status file (เหมือน start-team.sh)
# ──────────────────────────────────────────────────────────────
provision_agent_dir() {
  local dir="/tmp/agent-${ROLE}"
  local src="$SCRIPT_DIR/.claude/agents/${ROLE}.md"
  [[ -f "$src" ]] || { echo "Error: $src not found" >&2; exit 1; }

  mkdir -p "$dir" "$dir/.claude" /tmp/agent-status
  > "/tmp/agent-status/${ROLE}.md"

  awk '/^---$/{found++; next} found==1{next} {print}' "$src" > "$dir/CLAUDE.md"
  echo '{"autoCompactEnabled":true}' > "$dir/.claude/settings.json"

  local proj_description proj_paths_md
  proj_description=$(jq -r --arg p "$PROJECT" '.projects[$p].description // ""' "$PROJECTS_JSON" 2>/dev/null || true)
  proj_paths_md=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "- **\(.key)**: \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null || true)

  cat >> "$dir/CLAUDE.md" <<CONTEXT

---

## Active Project: $PROJECT
${proj_description:+$proj_description$'\n'}
### Project Paths
$proj_paths_md

### สิ่งที่ต้องทำเมื่อเริ่ม session ใหม่
ก่อนรับงานแรก ให้อ่านไฟล์เหล่านี้ในแต่ละ path ที่เกี่ยวข้องกับ role ของคุณ:
- \`CLAUDE.md\` — conventions, architecture, คำสั่ง dev ของ project
- \`README.md\` — overview และ setup
- \`DESIGN.md\` — design system, tokens, UX guidelines (ถ้ามี)

หลังอ่านแล้วรอรับ task จาก Lead ได้เลย
CONTEXT
}
provision_agent_dir

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

# ──────────────────────────────────────────────────────────────
# Auto-answer trust prompt (new /tmp dir → Claude asks once)
# ──────────────────────────────────────────────────────────────
auto_trust() {
  local i=0
  while [[ $i -lt 30 ]]; do
    if tmux capture-pane -t "$NEW_PANE" -p 2>/dev/null | grep -q "trust this folder"; then
      tmux send-keys -t "$NEW_PANE" "1" Enter
      return
    fi
    sleep 0.5
    i=$((i + 1))
  done
}
auto_trust &

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

  # อัปเดต timestamp
  tmp=$(mktemp)
  sed "s/^_Updated: .*_$/_Updated: $(date '+%Y-%m-%d %H:%M')_/" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}
register_in_state

echo ""
echo "✓ Role '$ROLE' added → pane $NEW_PANE (/tmp/agent-${ROLE})"
echo "  .team-state.md updated — Lead ใช้ pane ID นี้ส่งงานได้เลยหลัง agent พร้อม (รอ trust prompt ~5s)"
