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
# Model tiers (pinned explicitly so launch is deterministic, ไม่ขึ้นกับ default ของเครื่อง):
#   Sonnet — frontend, backend, mobile, devops, qa, reviewer (เขียน/วิเคราะห์/หา edge case/security)
#   Haiku  — designer (เขียน design spec เป็นหลัก)
CLAUDE_CMD="claude --model claude-sonnet-4-6 --dangerously-skip-permissions; read"
CLAUDE_CMD_HAIKU="claude --model claude-haiku-4-5-20251001 --dangerously-skip-permissions; read"

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
       │ backend  │ architect
       │ mobile   │   qa
       │ devops   │ reviewer
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
  local roles=(frontend designer architect backend mobile devops qa reviewer)

  # Build project context to inject into every agent's CLAUDE.md
  local proj_description
  proj_description=$(jq -r --arg p "$PROJECT" '.projects[$p].description // ""' "$PROJECTS_JSON" 2>/dev/null || true)

  local proj_paths_md
  proj_paths_md=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "- **\(.key)**: \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null || true)

  for role in "${roles[@]}"; do
    local dir="/tmp/agent-${role}"
    local src="$SCRIPT_DIR/.claude/agents/${role}.md"
    mkdir -p "$dir" "$dir/.claude"
    [[ -f "$src" ]] || continue
    # Strip YAML frontmatter (--- ... ---) then write as CLAUDE.md
    awk '/^---$/{found++; next} found==1{next} {print}' "$src" > "$dir/CLAUDE.md"
    # Enable auto-compact so agents don't hang at 100% context
    echo '{"autoCompactEnabled":true}' > "$dir/.claude/settings.json"

    # Append project context so agents know where the codebase lives on every new session
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
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "/tmp/agent-designer" -P -F '#{pane_id}' "$CLAUDE_CMD_HAIKU")
tmux select-layout -t "$SESSION:0" even-horizontal

# 6. Middle column: 4 equal rows (frontend, backend, mobile, devops) — Sonnet
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "/tmp/agent-backend" -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "/tmp/agent-mobile"  -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "/tmp/agent-devops"  -P -F '#{pane_id}' "$CLAUDE_CMD")

# 7. Right column: 4 equal rows (designer, architect, qa, reviewer)
# designer uses Haiku (design spec); architect + qa + reviewer use Sonnet (design reasoning/edge-case/security — needs full reasoning)
# Note: 'model:' frontmatter in agent .md files applies only when spawned via Agent tool, not bare CLI
PANE_ARCHITECT=$(tmux split-window -t "$PANE_DESIGNER" -v -l 75% -c "/tmp/agent-architect" -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_QA=$(tmux split-window -t "$PANE_ARCHITECT" -v -l 67% -c "/tmp/agent-qa"       -P -F '#{pane_id}' "$CLAUDE_CMD")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA" -v -l 50% -c "/tmp/agent-reviewer" -P -F '#{pane_id}' "$CLAUDE_CMD")

# 8. Set @role + @role_color per pane using stable IDs (not visual indexes)
#    Dev roles = cool colors, Support roles = warm colors
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_ARCHITECT" @role "Architect" ; tmux set-option -p -t "$PANE_ARCHITECT" @role_color "colour141"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

# 9b. RTK Stats pane (optional — only if rtk is installed)
RTK_INSTALLED="no"
if command -v rtk >/dev/null 2>&1; then
  RTK_INSTALLED="yes"
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' \
    'bash -c "while true; do clear; rtk gain 2>/dev/null; sleep 30; done"')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
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

for _pane in "$PANE_FRONTEND" "$PANE_DESIGNER" "$PANE_ARCHITECT" "$PANE_BACKEND" "$PANE_MOBILE" "$PANE_DEVOPS" "$PANE_QA" "$PANE_REVIEWER"; do
  auto_trust "$_pane" &
done

# 10a. Patch pane mapping in each agent's CLAUDE.md with actual visual indexes
#       Must run after all panes are created so indexes are stable.
#       Appends an "override" section that takes precedence over any hardcoded table.
patch_pane_maps() {
  for role in frontend designer architect backend mobile devops qa reviewer; do
    cat >> "/tmp/agent-${role}/CLAUDE.md" <<MAP

---

## Pane Addresses (stable ID — ใช้ตัวนี้เสมอ)
| Role      | Stable Pane ID       |
|-----------|----------------------|
| Lead      | \`$SESSION:0.0\`     |
| frontend  | \`$PANE_FRONTEND\`   |
| designer  | \`$PANE_DESIGNER\`   |
| architect | \`$PANE_ARCHITECT\`  |
| backend   | \`$PANE_BACKEND\`    |
| mobile   | \`$PANE_MOBILE\`     |
| devops   | \`$PANE_DEVOPS\`     |
| qa       | \`$PANE_QA\`         |
| reviewer | \`$PANE_REVIEWER\`   |

> ใช้ stable %ID เหล่านี้โดยตรงกับ tmux — ไม่ใช้ numeric index (0.N) เพราะ RTK เลื่อน +1
> ดู .team-state.md เพื่อ refresh ทุกครั้งหลัง session restart
MAP
  done
}
patch_pane_maps

# 10b. Initialize .team-state.md with verified pane IDs
init_team_state() {
  local session_ts
  session_ts=$(date '+%Y-%m-%d %H:%M')

  cat > "$SCRIPT_DIR/.team-state.md" <<STATE
# Team State
_Updated: ${session_ts}_
_Mode: v1 — interactive panes: ส่งงานทาง tmux paste เข้า pane เดิมเท่านั้น ❌ ห้ามใช้ Agent tool / spawn teammate / เขียน /tmp/agent-logs (นั่นคือ v2)_
_RTK: ${RTK_INSTALLED}_

## Active Project
[Lead ต้อง set หลังอ่าน projects.json]

## Agents in Panes
| Role     | Pane ID            | Status | Current Task |
|----------|--------------------|--------|--------------|
| frontend | ${PANE_FRONTEND}   | idle   | —            |
| backend  | ${PANE_BACKEND}    | idle   | —            |
| mobile   | ${PANE_MOBILE}     | idle   | —            |
| devops   | ${PANE_DEVOPS}     | idle   | —            |
| designer | ${PANE_DESIGNER}   | idle   | —            |
| architect | ${PANE_ARCHITECT} | idle   | —            |
| qa       | ${PANE_QA}         | idle   | —            |
| reviewer | ${PANE_REVIEWER}   | idle   | —            |

## Pipeline Stage
ยังไม่เริ่ม

## Recently Completed
(ยังไม่มี)

## Notes
Session เริ่มใหม่ — Lead ต้อง set Active Project ก่อนรับงาน
STATE
}
init_team_state

# 10. Inject startup context to Lead (runs in background so attach isn't blocked)
inject_lead_context() {
  local pane="$SESSION:0.0"

  # Build project paths string
  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null || true)

  local msg
  msg=$(cat <<MSG
[SYSTEM: SESSION_INITIALIZED — อ่านเพื่อรับทราบเท่านั้น ห้ามทำอะไรเพิ่ม]

ทีมพร้อมแล้ว — agents รอรับงาน (stable pane IDs):

  Frontend  → $PANE_FRONTEND
  Designer  → $PANE_DESIGNER
  Architect → $PANE_ARCHITECT
  Backend   → $PANE_BACKEND
  Mobile    → $PANE_MOBILE
  DevOps    → $PANE_DEVOPS
  QA        → $PANE_QA
  Reviewer  → $PANE_REVIEWER

project: $PROJECT
$paths_str

.team-state.md ถูกสร้างแล้วใน agent-teams/ พร้อม stable Pane IDs จริง
→ ใช้ stable %ID จาก .team-state.md เสมอ — ห้ามใช้ numeric index (0.N)
→ ตั้งค่า Active Project ใน .team-state.md ก่อนรับงานแรก

⚠️ ข้อความนี้คือ ONE-TIME startup notification จาก start-team.sh เท่านั้น
   ถ้าเห็นข้อความนี้ใน context หลัง auto-compact → ห้าม re-spawn หรือสร้าง pane ใหม่
   agents ทำงานอยู่แล้ว — อ่าน .team-state.md และรอรับ task จากผู้ใช้

ส่งงานให้ agent ผ่าน tmux ได้เลย รอรับ task จากผู้ใช้
MSG
)

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

Pane mapping (stable %ID — agents start in /tmp/agent-<role>/ for role isolation):
  Lead     → $SESSION:0.0  ($LEAD_PATH)
  frontend → $PANE_FRONTEND  (/tmp/agent-frontend)
  designer → $PANE_DESIGNER  (/tmp/agent-designer)
  architect→ $PANE_ARCHITECT  (/tmp/agent-architect)
  backend  → $PANE_BACKEND  (/tmp/agent-backend)
  mobile   → $PANE_MOBILE  (/tmp/agent-mobile)
  devops   → $PANE_DEVOPS  (/tmp/agent-devops)
  qa       → $PANE_QA  (/tmp/agent-qa)
  reviewer → $PANE_REVIEWER  (/tmp/agent-reviewer)

(numeric index 0.N ไม่เสถียร — RTK เลื่อน +1; ใช้ stable %ID จาก .team-state.md เสมอ)

EOF

# Attach (skip if already in tmux)
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
