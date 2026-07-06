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
ROLES=(frontend backend mobile devops designer architect qa reviewer)
# Robust per-role log viewer: follows <role>*.log (รวมไฟล์ชื่อเพี้ยนที่ agent สร้าง)
# แทน `tail -f <role>.log` แบบ exact-name ที่พลาดเมื่อ sub-agent เขียนชื่อไฟล์ไม่ตรง
LOG_PANE="$SCRIPT_DIR/scripts/log-pane.sh"

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
       │ backend log  │ architect log
       │ mobile log   │   qa log
       │ devops log   │ reviewer log

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

RTK_PANE_CREATED=false

# 5. Create 3 columns (Lead | middle | right) using log-viewer panes
PANE_FRONTEND=$(tmux split-window -t "$SESSION:0.0" -h -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' frontend '$LOG_DIR'")
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' designer '$LOG_DIR'")
tmux select-layout -t "$SESSION:0" even-horizontal

# 6. Middle column: 4 rows (frontend, backend, mobile, devops)
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' backend '$LOG_DIR'")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' mobile '$LOG_DIR'")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' devops '$LOG_DIR'")

# 7. Right column: 4 rows (designer, architect, qa, reviewer)
PANE_ARCHITECT=$(tmux split-window -t "$PANE_DESIGNER" -v -l 75% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' architect '$LOG_DIR'")
PANE_QA=$(tmux split-window -t "$PANE_ARCHITECT"  -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' qa '$LOG_DIR'")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA"  -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' reviewer '$LOG_DIR'")

# 8. Set @role + @role_color per pane using stable IDs
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend log" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer log" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_ARCHITECT" @role "Architect log" ; tmux set-option -p -t "$PANE_ARCHITECT" @role_color "colour141"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend log"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile log"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps log"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA log"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer log" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

# 8b. RTK Stats pane (optional) — split Lead column vertically AFTER layout is set
#     Uses while-loop because macOS does not ship `watch`
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' \
    'while true; do clear; rtk gain 2>/dev/null || echo "(rtk unavailable)"; sleep 30; done' 2>/dev/null) || true
  if [[ -n "${PANE_RTK:-}" ]]; then
    tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
    tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
    RTK_PANE_CREATED=true
  fi
fi

# 8c. Initialize .team-state.md (v2 flavor) so the UserPromptSubmit hook has state
#     and the Lead is reminded it is in v2 mode (spawn via Agent tool, not tmux paste)
init_team_state() {
  local ts rtk
  ts=$(date '+%Y-%m-%d %H:%M')
  command -v rtk >/dev/null 2>&1 && rtk="yes" || rtk="no"

  cat > "$SCRIPT_DIR/.team-state.md" <<STATE
# Team State (v2 mode)
_Updated: ${ts}_
_Mode: v2 — agents spawned via Agent tool; panes are log viewers_
_RTK: ${rtk}_

## Active Project
[Lead ต้อง set หลังอ่าน projects.json]

## Agents (v2 — on-demand, ไม่ใช่ standing panes)
Lead spawn agent ผ่าน **Agent tool** ตาม task — ไม่ใช่ tmux paste
Agents เขียน progress ลง \`${LOG_DIR}/<role>.log\` ; panes ด้านขวาคือ \`tail -f\` ของ log เหล่านั้น (ดูได้ ไม่ใช่ task targets)

| Role | Log viewer pane | Log file |
|------|-----------------|----------|
| frontend | ${PANE_FRONTEND} | ${LOG_DIR}/frontend.log |
| backend  | ${PANE_BACKEND}  | ${LOG_DIR}/backend.log  |
| mobile   | ${PANE_MOBILE}   | ${LOG_DIR}/mobile.log   |
| devops   | ${PANE_DEVOPS}   | ${LOG_DIR}/devops.log   |
| designer | ${PANE_DESIGNER} | ${LOG_DIR}/designer.log |
| architect | ${PANE_ARCHITECT} | ${LOG_DIR}/architect.log|
| qa       | ${PANE_QA}       | ${LOG_DIR}/qa.log       |
| reviewer | ${PANE_REVIEWER} | ${LOG_DIR}/reviewer.log |

## Pipeline Stage
ยังไม่เริ่ม

## Recently Completed
(ยังไม่มี)

## Notes
v2 mode — ส่งงานผ่าน Agent tool (return value) ไม่ใช่ tmux paste; Lead ต้อง set Active Project ก่อนรับงานแรก
STATE
}
init_team_state

# 9. Inject startup context to Lead (runs in background so attach isn't blocked)
inject_lead_context() {
  local pane="$SESSION:0.0"

  # Build project paths string
  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null) || paths_str=""

  # ใช้ stable %ID เท่านั้น — numeric index (0.N) เลื่อนได้เมื่อมี RTK pane
  local rtk_line=""
  if [[ "$RTK_PANE_CREATED" == "true" ]]; then
    rtk_line="  RTK Stats     → ${PANE_RTK}
"
  fi

  local msg
  msg=$(cat <<MSG
ทีมพร้อมแล้ว (v2 multi-agent mode) — agent panes แสดง log streams (stable pane %ID):

${rtk_line}  Frontend log  → ${PANE_FRONTEND}
  Backend log   → ${PANE_BACKEND}
  Mobile log    → ${PANE_MOBILE}
  DevOps log    → ${PANE_DEVOPS}
  Designer log  → ${PANE_DESIGNER}
  Architect log → ${PANE_ARCHITECT}
  QA log        → ${PANE_QA}
  Reviewer log  → ${PANE_REVIEWER}

project: $PROJECT
$paths_str

[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]
รอรับ task จากผู้ใช้
MSG
)

  # Wait for Lead's Claude prompt before injecting (max 40s)
  local i=0
  while ! tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qE "❯|bypass permissions"; do
    sleep 1; i=$((i + 1)); [[ $i -gt 40 ]] && break
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

Pane mapping (stable %ID — numeric index เลื่อนได้เมื่อมี RTK pane):
  Lead          → $SESSION:0.0  ($LEAD_PATH)
  frontend log  → $PANE_FRONTEND  ($LOG_DIR/frontend.log)
  backend log   → $PANE_BACKEND  ($LOG_DIR/backend.log)
  mobile log    → $PANE_MOBILE  ($LOG_DIR/mobile.log)
  devops log    → $PANE_DEVOPS  ($LOG_DIR/devops.log)
  designer log  → $PANE_DESIGNER  ($LOG_DIR/designer.log)
  architect log → $PANE_ARCHITECT  ($LOG_DIR/architect.log)
  qa log        → $PANE_QA  ($LOG_DIR/qa.log)
  reviewer log  → $PANE_REVIEWER  ($LOG_DIR/reviewer.log)

EOF

# Attach or switch to session
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  tmux switch-client -t "$SESSION"
fi
