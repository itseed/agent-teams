#!/usr/bin/env bash
# start-team-v3.sh — spawn dev-team tmux session (v3 Agent Teams native mode)
#
# v3 mode: Lead pane only. Teammate panes are created NATIVELY by Agent Teams
# (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 + teammateMode: "tmux") when Lead
# calls TeamCreate. No pre-built log viewers — teammates run as real Claude
# Code processes with SendMessage peer communication.
#
# Usage:
#   ./start-team-v3.sh              # ใช้ project จาก field "active" ใน projects.json
#   ./start-team-v3.sh pms          # ใช้ project ชื่อ "pms"
#   ./start-team-v3.sh --help       # แสดง help

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Windows native guard (must run inside WSL2, not CMD/PowerShell)
# ──────────────────────────────────────────────────────────────
if [[ "${OS:-}" == "Windows_NT" ]] || \
   { [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version && [[ -z "${WSL_DISTRO_NAME:-}" ]]; }; then
  cat >&2 <<'EOF'
Error: start-team-v3.sh ต้องรันใน WSL2 เท่านั้น ไม่รองรับ Windows CMD/PowerShell โดยตรง

วิธีแก้:
  1. ติดตั้ง WSL2 ด้วย setup-windows.ps1 (PowerShell as Administrator):
       .\setup-windows.ps1
  2. เปิด Ubuntu terminal แล้วไปที่ repo:
       cd ~/agent-teams
  3. รันใหม่:
       ./start-team-v3.sh
EOF
  exit 1
fi

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"
CLAUDE_CMD="claude --dangerously-skip-permissions"
LOG_DIR="/tmp/agent-logs"
ROLES=(frontend backend mobile devops designer qa reviewer)

# ──────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: $(basename "$0") [PROJECT_NAME]

Spawn (or resume) tmux session "$SESSION" in v3 Agent Teams native mode.
Only the Lead pane is created by this script. Teammate panes are spawned
automatically by Agent Teams when Lead calls TeamCreate — each teammate
runs as a separate Claude Code process with SendMessage peer communication.

If session already exists, prompts to resume — preserving all state.

  PROJECT_NAME   ชื่อ project ใน projects.json (ถ้าไม่ระบุใช้ field "active")

Requires:
  - CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 (set in .claude/settings.json)
  - teammateMode: "tmux" (set in .claude/settings.json)
  - claude v2.1.32+ (use: claude --version to verify)

[v3 Agent Teams native mode — teammates spawned via TeamCreate, peer comm via SendMessage]
EOF
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Dependencies
# ──────────────────────────────────────────────────────────────
command -v tmux   >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }
command -v jq     >/dev/null || { echo "Error: jq not found (brew install jq)" >&2; exit 1; }
command -v claude >/dev/null || { echo "Error: claude CLI not found" >&2; exit 1; }
[[ -f "$PROJECTS_JSON" ]]   || { echo "Error: $PROJECTS_JSON not found" >&2; exit 1; }

# Verify Agent Teams env is configured
SETTINGS_FILE="$SCRIPT_DIR/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  if ! jq -e '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS == "1"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Warning: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 not found in .claude/settings.json" >&2
    echo "         Agent Teams features may not work correctly." >&2
  fi
  if ! jq -e '.teammateMode == "tmux"' "$SETTINGS_FILE" >/dev/null 2>&1; then
    echo "Warning: teammateMode: \"tmux\" not set in .claude/settings.json" >&2
    echo "         Teammate panes may not appear in tmux." >&2
  fi
fi

# ──────────────────────────────────────────────────────────────
# Determine project
# ──────────────────────────────────────────────────────────────
PROJECT="${1:-$(jq -r '.active' "$PROJECTS_JSON")}"

if ! jq -e --arg p "$PROJECT" '.projects[$p]' "$PROJECTS_JSON" >/dev/null; then
  echo "Error: project '$PROJECT' not found in projects.json" >&2
  echo "Available: $(jq -r '.projects | keys | join(", ")' "$PROJECTS_JSON")" >&2
  exit 1
fi

echo "→ Project: $PROJECT"

LEAD_PATH="$SCRIPT_DIR"

mkdir -p "$LOG_DIR"

# ──────────────────────────────────────────────────────────────
# Resume or restart existing session
# ──────────────────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
  printf "Session '%s' already exists. Resume it? [Y/n] " "$SESSION"
  read -r ans
  if [[ "${ans:-Y}" != "n" && "${ans:-Y}" != "N" ]]; then
    echo "→ Resuming session '$SESSION'..."
    if [[ -z "${TMUX:-}" ]]; then
      tmux attach-session -t "$SESSION"
    else
      tmux switch-client -t "$SESSION"
    fi
    exit 0
  fi
  printf "Kill existing session and start fresh? [y/N] "
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 0; }
  tmux kill-session -t "$SESSION"
fi

# ──────────────────────────────────────────────────────────────
# Create session + pre-built log-viewer panes (3-column layout)
# Agent Teams will spawn actual Claude processes on top when TeamCreate is called
# ──────────────────────────────────────────────────────────────
echo "→ Spawning session '$SESSION' (v3 Agent Teams native mode)..."

tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$CLAUDE_CMD"
tmux rename-window -t "$SESSION:0" "main"
tmux set-option -wg -t "$SESSION:0" automatic-rename off

# Mouse support
tmux set-option -g -t "$SESSION" mouse on

# Pane border styling
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# v3: ไม่มี pre-built log viewer panes — Agent Teams จัดการ panes เองเมื่อ TeamCreate ถูกเรียก

# ──────────────────────────────────────────────────────────────
# Inject startup context to Lead
# ──────────────────────────────────────────────────────────────
inject_lead_context() {
  local pane="$SESSION:0.0"

  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null) || paths_str=""

  local msg
  msg=$(cat <<MSG
ทีมพร้อมแล้ว (v3 Agent Teams native mode)

project: $PROJECT
$paths_str

[v3 mode] — teammate panes จะถูกสร้างโดย Agent Teams อัตโนมัติเมื่อ spawn
- ใช้ TeamCreate เพื่อสร้าง team และ spawn teammates เป็น Claude Code processes ใน tmux panes
- Teammates สื่อสารกันผ่าน SendMessage โดยตรง (native Mailbox)
- ใช้ TaskCreate/TaskList/TaskUpdate สำหรับ task tracking
- ใช้ ToolSearch เพื่อโหลด TeamCreate schema ก่อนเรียกใช้

รอรับ task จากผู้ใช้
MSG
)

  # Wait for Lead's Claude prompt before injecting (max 40s)
  local i=0
  while ! tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qE "❯|bypass permissions|>"; do
    sleep 1; ((i++)); [[ $i -gt 40 ]] && break
  done

  tmux set-buffer "$msg" && tmux paste-buffer -t "$pane"
  tmux send-keys -t "$pane" Enter
}
inject_lead_context &

# Step 1: สร้าง right-column "agent zone" ก่อน (horizontal split จาก Lead)
# ทำให้ tmux layout tree ล็อก left column = Lead เท่านั้น
# เมื่อ Agent Teams spawn ใหม่ จะ split จาก right column ไม่กระทบ Lead/RTK
PANE_AGENT_ZONE=$(tmux split-window -t "$SESSION:0.0" -h -l 67% -c "$LEAD_PATH" \
  -P -F '#{pane_id}' 'cat' 2>/dev/null) || PANE_AGENT_ZONE=""
if [[ -n "${PANE_AGENT_ZONE:-}" ]]; then
  tmux set-option -p -t "$PANE_AGENT_ZONE" @role "Agents"
  tmux set-option -p -t "$PANE_AGENT_ZONE" @role_color "colour240"
fi

# Step 2: สร้าง RTK ใต้ Lead (vertical split จาก Lead — อยู่ใน left column เสมอ)
# ต้องสร้างหลัง right column เพื่อให้ layout tree ถูกต้อง
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 25% -c ~ -P -F '#{pane_id}' \
    'while true; do clear; rtk gain 2>/dev/null || echo "(rtk unavailable)"; sleep 30; done' 2>/dev/null) || true
  if [[ -n "${PANE_RTK:-}" ]]; then
    tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
    tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
    RTK_PANE_CREATED=true
  fi
fi

# Focus Lead (ไม่ใช่ agent zone หรือ RTK)
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
cat <<EOF

✓ Session '$SESSION' ready (v3 Agent Teams native mode).

  Lead      → $SESSION:0.0  (left top)
  RTK Stats → below Lead    (left bottom, stays fixed)
  Agents    → right column  (Agent Teams spawns here)

Layout: [Lead | Agents...]
        [RTK  |           ]

Settings: teammateMode=tmux + CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

EOF

# Attach or switch to session
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  tmux switch-client -t "$SESSION"
fi
