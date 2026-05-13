#!/usr/bin/env bash
# start-team-v2.sh — spawn dev-team tmux session (v2 multi-agent mode)
#
# v2 mode: agent panes show live log viewers (tail -f), NOT Claude processes.
# Agents are spawned by the Lead's Claude via the Agent tool and write to
# /tmp/agent-logs/<role>.log which each pane streams in real time.
#
# Usage:
#   ./start-team-v2.sh              # ใช้ project จาก field "active" ใน projects.json
#   ./start-team-v2.sh pms          # ใช้ project ชื่อ "pms"
#   ./start-team-v2.sh --help       # แสดง help

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Windows native guard (must run inside WSL2, not CMD/PowerShell)
# ──────────────────────────────────────────────────────────────
if [[ "${OS:-}" == "Windows_NT" ]] || \
   { [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version && [[ -z "${WSL_DISTRO_NAME:-}" ]]; }; then
  cat >&2 <<'EOF'
Error: start-team-v2.sh ต้องรันใน WSL2 เท่านั้น ไม่รองรับ Windows CMD/PowerShell โดยตรง

วิธีแก้:
  1. ติดตั้ง WSL2 ด้วย setup-windows.ps1 (PowerShell as Administrator):
       .\setup-windows.ps1
  2. เปิด Ubuntu terminal แล้วไปที่ repo:
       cd ~/agent-teams
  3. รันใหม่:
       ./start-team-v2.sh
EOF
  exit 1
fi

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"
CLAUDE_CMD="claude --dangerously-skip-permissions; read"
LOG_DIR="/tmp/agent-logs"
ROLES=(frontend backend mobile devops designer qa reviewer)

# ──────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: $(basename "$0") [PROJECT_NAME]

Spawn (or resume) tmux session "$SESSION" in v2 multi-agent mode.
Lead pane runs Claude; agent panes show live log streams from
/tmp/agent-logs/<role>.log — agents are spawned by Lead via the Agent tool.

If session already exists, prompts to resume — preserving all state.

  PROJECT_NAME   ชื่อ project ใน projects.json (ถ้าไม่ระบุใช้ field "active")

Layout (3 columns):
  Lead │ frontend log │ designer log
       │ backend log  │   qa log
       │ mobile log   │ reviewer log
       │ devops log   │

Agent log panes will show "(waiting for first agent spawn)" until Lead spawns the first agent.

[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]
EOF
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Dependencies
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "Error: jq not found (brew install jq)" >&2; exit 1; }
[[ -f "$PROJECTS_JSON" ]]  || { echo "Error: $PROJECTS_JSON not found" >&2; exit 1; }

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
# Create session + panes
# ──────────────────────────────────────────────────────────────
echo "→ Spawning session '$SESSION' (v2 mode)..."

# 1. Create session with Lead pane (only pane running Claude)
tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$CLAUDE_CMD"

# 2. Enable mouse support
tmux set-option -g -t "$SESSION" mouse on

# 3. Enable pane border + styling
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 4. RTK Stats pane (optional — only if rtk is installed)
#    Split Lead pane vertically before creating columns
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' 'watch -n 30 rtk gain')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
  RTK_PANE_CREATED=true
fi

# 5. Create 3 columns (Lead | middle | right) using log-viewer panes
PANE_FRONTEND=$(tmux split-window -t "$SESSION:0.0" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/frontend.log")
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/designer.log")
tmux select-layout -t "$SESSION:0" even-horizontal

# 6. Middle column: 4 rows (frontend, backend, mobile, devops)
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/backend.log")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/mobile.log")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/devops.log")

# 7. Right column: 3 rows (designer, qa, reviewer)
PANE_QA=$(tmux split-window -t "$PANE_DESIGNER"  -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/qa.log")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA"  -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/reviewer.log")

# 8. Set @role + @role_color per pane using stable IDs
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend log" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer log" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend log"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile log"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps log"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA log"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer log" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

# 9. Inject startup context to Lead (runs in background so attach isn't blocked)
inject_lead_context() {
  local pane="$SESSION:0.0"

  # Build project paths string
  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null) || paths_str=""

  local msg
  if $RTK_PANE_CREATED; then
    msg=$(cat <<MSG
ทีมพร้อมแล้ว (v2 multi-agent mode) — agent panes แสดง log streams:

  RTK Stats    → dev-team:0.1
  Frontend log → dev-team:0.2
  Backend log  → dev-team:0.3
  Mobile log   → dev-team:0.4
  DevOps log   → dev-team:0.5
  Designer log → dev-team:0.6
  QA log       → dev-team:0.7
  Reviewer log → dev-team:0.8

project: $PROJECT
$paths_str

[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]
รอรับ task จากผู้ใช้
MSG
)
  else
    msg=$(cat <<MSG
ทีมพร้อมแล้ว (v2 multi-agent mode) — agent panes แสดง log streams:

  Frontend log → dev-team:0.1
  Backend log  → dev-team:0.2
  Mobile log   → dev-team:0.3
  DevOps log   → dev-team:0.4
  Designer log → dev-team:0.5
  QA log       → dev-team:0.6
  Reviewer log → dev-team:0.7

project: $PROJECT
$paths_str

[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]
รอรับ task จากผู้ใช้
MSG
)
  fi

  # Wait for Lead's Claude prompt before injecting (max 40s)
  local i=0
  while ! tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qE "❯|bypass permissions"; do
    sleep 1; ((i++)); [[ $i -gt 40 ]] && break
  done

  tmux set-buffer "$msg" && tmux paste-buffer -t "$pane"
  tmux send-keys -t "$pane" Enter
}
inject_lead_context &

# 10. Focus Lead
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
cat <<EOF

✓ Session '$SESSION' ready (v2 multi-agent mode).

Lead pane runs Claude; agent panes stream live logs from $LOG_DIR/

Pane mapping:
  Lead         → $SESSION:0.0  ($LEAD_PATH)
  frontend log → $SESSION:0.1  ($LOG_DIR/frontend.log)
  backend log  → $SESSION:0.2  ($LOG_DIR/backend.log)
  mobile log   → $SESSION:0.3  ($LOG_DIR/mobile.log)
  devops log   → $SESSION:0.4  ($LOG_DIR/devops.log)
  designer log → $SESSION:0.5  ($LOG_DIR/designer.log)
  qa log       → $SESSION:0.6  ($LOG_DIR/qa.log)
  reviewer log → $SESSION:0.7  ($LOG_DIR/reviewer.log)

EOF

# Attach (skip if already in tmux)
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
