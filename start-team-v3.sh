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

# ──────────────────────────────────────────────────────────────
# Prepare /tmp/agent-logs/ — create dir and truncate each role log
# ──────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
for role in "${ROLES[@]}"; do
  > "$LOG_DIR/${role}.log"
done
echo "→ Log dir ready: $LOG_DIR"

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

# Mouse support
tmux set-option -g -t "$SESSION" mouse on

# Pane border styling
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 3-column layout: Lead | middle (dev roles) | right (support roles)
PANE_FRONTEND=$(tmux split-window -t "$SESSION:0.0" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/frontend.log")
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/designer.log")
tmux select-layout -t "$SESSION:0" even-horizontal

# Middle column: frontend / backend / mobile / devops
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/backend.log")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/mobile.log")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/devops.log")

# Right column: designer / qa / reviewer
PANE_QA=$(tmux split-window -t "$PANE_DESIGNER"  -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/qa.log")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA"  -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/reviewer.log")

# Role labels on log-viewer panes
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend log" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer log" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend log"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile log"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps log"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA log"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer log" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

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

# RTK Stats pane (optional) — split below Lead in left column
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' \
    'while true; do clear; rtk gain 2>/dev/null || echo "(rtk unavailable)"; sleep 30; done' 2>/dev/null) || true
  if [[ -n "${PANE_RTK:-}" ]]; then
    tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
    tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
    RTK_PANE_CREATED=true
  fi
fi

# Focus Lead
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
cat <<EOF

✓ Session '$SESSION' ready (v3 Agent Teams native mode).

  Lead         → $SESSION:0.0  ($LEAD_PATH)
  frontend log → (log viewer — $LOG_DIR/frontend.log)
  backend log  → (log viewer — $LOG_DIR/backend.log)
  mobile log   → (log viewer — $LOG_DIR/mobile.log)
  devops log   → (log viewer — $LOG_DIR/devops.log)
  designer log → (log viewer — $LOG_DIR/designer.log)
  qa log       → (log viewer — $LOG_DIR/qa.log)
  reviewer log → (log viewer — $LOG_DIR/reviewer.log)

When Lead calls TeamCreate, Agent Teams spawns actual Claude Code processes
as additional panes with native SendMessage peer communication.

Settings: teammateMode=tmux + CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

EOF

# Attach or switch to session
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  tmux switch-client -t "$SESSION"
fi
