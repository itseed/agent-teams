#!/usr/bin/env bash
# spawn-team.sh — spawn dev-team tmux session with Lead + 7 teammates
#
# Usage:
#   ./spawn-team.sh              # ใช้ project จาก field "active" ใน projects.json
#   ./spawn-team.sh pms          # ใช้ project ชื่อ "pms"
#   ./spawn-team.sh --help       # แสดง help

set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Windows native guard (must run inside WSL2, not CMD/PowerShell)
# ──────────────────────────────────────────────────────────────
if [[ "${OS:-}" == "Windows_NT" ]] || \
   { [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version && [[ -z "${WSL_DISTRO_NAME:-}" ]]; }; then
  cat >&2 <<'EOF'
Error: start-team.sh ต้องรันใน WSL2 เท่านั้น ไม่รองรับ Windows CMD/PowerShell โดยตรง

วิธีแก้:
  1. ติดตั้ง WSL2 ด้วย setup-windows.ps1 (PowerShell as Administrator):
       .\setup-windows.ps1
  2. เปิด Ubuntu terminal แล้วไปที่ repo:
       cd ~/agent-teams
  3. รันใหม่:
       ./start-team.sh
EOF
  exit 1
fi

SESSION="dev-team"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"
CLAUDE_CMD="claude --dangerously-skip-permissions; read"

# ──────────────────────────────────────────────────────────────
# Help
# ──────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
Usage: $(basename "$0") [PROJECT_NAME]

Spawn (or resume) tmux session "$SESSION" with Lead + 7 agent panes.
If session already exists, prompts to resume — preserving all agent state.

  PROJECT_NAME   ชื่อ project ใน projects.json (ถ้าไม่ระบุใช้ field "active")

Layout (3 columns):
  Lead │ frontend │ designer
       │ backend  │   qa
       │ mobile   │ reviewer
       │ devops   │
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
# Create per-agent temp dirs with CLAUDE.md (role at system-prompt level)
# Agents start here so Claude reads the specialist role definition before
# any task arrives — prevents Lead CLAUDE.md from taking over.
# Project working directory is injected per-task by Lead.
# ──────────────────────────────────────────────────────────────
create_agent_dirs() {
  local roles=(frontend designer backend mobile devops qa reviewer)
  for role in "${roles[@]}"; do
    local dir="/tmp/agent-${role}"
    local src="$SCRIPT_DIR/.claude/agents/${role}.md"
    mkdir -p "$dir"
    [[ -f "$src" ]] || continue
    # Strip YAML frontmatter (--- ... ---) then write as CLAUDE.md
    awk '/^---$/{found++; next} found==1{next} {print}' "$src" > "$dir/CLAUDE.md"
  done
}

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
echo "→ Spawning session '$SESSION'..."

# 1. Prepare per-agent CLAUDE.md in /tmp (must run before panes spawn)
create_agent_dirs

# 2. Create session with Lead pane
tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$CLAUDE_CMD"

# 3. Enable mouse support
tmux set-option -g -t "$SESSION" mouse on

# 4. Enable pane border + styling
#    - @role + @role_color = user options (program เขียนทับไม่ได้)
#    - pane-border-style: สีเส้นกรอบเมื่อไม่ active
#    - pane-active-border-style: สีเส้นกรอบเมื่อ active (highlight)
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 5. Create 3 columns (Lead | middle | right)
# Capture stable pane IDs with -P -F '#{pane_id}' so subsequent splits always
# target the correct pane regardless of how tmux renumbers visual indexes.
PANE_FRONTEND=$(tmux split-window -t "$SESSION:0.0" -h -c "/tmp/agent-frontend" -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "/tmp/agent-designer" -P -F '#{pane_id}' "$CLAUDE_CMD")
tmux select-layout -t "$SESSION:0" even-horizontal

# 6. Middle column: 4 equal rows (frontend, backend, mobile, devops)
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "/tmp/agent-backend" -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "/tmp/agent-mobile"  -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "/tmp/agent-devops"  -P -F '#{pane_id}' "$CLAUDE_CMD")

# 7. Right column: 3 equal rows (designer, qa, reviewer)
PANE_QA=$(tmux split-window -t "$PANE_DESIGNER" -v -l 67% -c "/tmp/agent-qa"       -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA" -v -l 50% -c "/tmp/agent-reviewer" -P -F '#{pane_id}' "$CLAUDE_CMD")

# 8. Set @role + @role_color per pane using stable IDs (not visual indexes)
#    Dev roles = cool colors, Support roles = warm colors
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

# 9b. RTK Stats pane (optional — only if rtk is installed)
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' 'watch -n 30 rtk gain')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
  RTK_PANE_CREATED=true
fi

# 9. Auto-answer trust prompt for agent panes (each pane runs in background)
#    /tmp/agent-<role>/ is a new directory — Claude Code asks once per directory
auto_trust() {
  local pane="$1"
  local i=0
  while [[ $i -lt 30 ]]; do
    if tmux capture-pane -t "$pane" -p 2>/dev/null | grep -q "trust this folder"; then
      tmux send-keys -t "$pane" "1" Enter
      return
    fi
    sleep 0.5
    ((i++))
  done
}

for _pane in "$PANE_FRONTEND" "$PANE_DESIGNER" "$PANE_BACKEND" "$PANE_MOBILE" "$PANE_DEVOPS" "$PANE_QA" "$PANE_REVIEWER"; do
  auto_trust "$_pane" &
done

# 10. Inject startup context to Lead (runs in background so attach isn't blocked)
inject_lead_context() {
  local pane="$SESSION:0.0"

  # Build project paths string
  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null || true)

  local msg
  if $RTK_PANE_CREATED; then
    msg=$(cat <<MSG
ทีมพร้อมแล้ว — agents รอรับงานใน panes ต่อไปนี้:

  RTK Stats → dev-team:0.1
  Frontend  → dev-team:0.2
  Backend   → dev-team:0.3
  Mobile    → dev-team:0.4
  DevOps    → dev-team:0.5
  Designer  → dev-team:0.6
  QA        → dev-team:0.7
  Reviewer  → dev-team:0.8

project: $PROJECT
$paths_str

ส่งงานให้ agent ผ่าน tmux ได้เลย รอรับ task จากผู้ใช้
MSG
)
  else
    msg=$(cat <<MSG
ทีมพร้อมแล้ว — agents รอรับงานใน panes ต่อไปนี้:

  Frontend  → dev-team:0.1
  Backend   → dev-team:0.2
  Mobile    → dev-team:0.3
  DevOps    → dev-team:0.4
  Designer  → dev-team:0.5
  QA        → dev-team:0.6
  Reviewer  → dev-team:0.7

project: $PROJECT
$paths_str

ส่งงานให้ agent ผ่าน tmux ได้เลย รอรับ task จากผู้ใช้
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

# 11. Focus Lead
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
cat <<EOF

✓ Session '$SESSION' ready.

Pane mapping (agents start in /tmp/agent-<role>/ for role isolation):
  Lead     → $SESSION:0.0  ($LEAD_PATH)
  frontend → $SESSION:0.1  (/tmp/agent-frontend)
  designer → $SESSION:0.2  (/tmp/agent-designer)
  backend  → $SESSION:0.3  (/tmp/agent-backend)
  mobile   → $SESSION:0.4  (/tmp/agent-mobile)
  devops   → $SESSION:0.5  (/tmp/agent-devops)
  qa       → $SESSION:0.6  (/tmp/agent-qa)
  reviewer → $SESSION:0.7  (/tmp/agent-reviewer)

EOF

# Attach (skip if already in tmux)
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
