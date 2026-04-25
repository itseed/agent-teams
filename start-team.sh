#!/usr/bin/env bash
# spawn-team.sh — spawn dev-team tmux session with Lead + 7 teammates
#
# Usage:
#   ./spawn-team.sh              # ใช้ project จาก field "active" ใน projects.json
#   ./spawn-team.sh pms          # ใช้ project ชื่อ "pms"
#   ./spawn-team.sh --help       # แสดง help

set -euo pipefail

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

Spawn tmux session "$SESSION" with Lead + 7 agent panes.

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

# ──────────────────────────────────────────────────────────────
# Resolve paths (with fallbacks)
# ──────────────────────────────────────────────────────────────
get_path() {
  jq -r --arg p "$PROJECT" --arg k "$1" '.projects[$p].paths[$k] // empty' "$PROJECTS_JSON"
}

WEB_PATH=$(get_path "web")
API_PATH=$(get_path "api")
MOBILE_PATH=$(get_path "mobile")
EXTENSION_PATH=$(get_path "extension")

# First non-empty among candidates, fallback to SCRIPT_DIR
first() {
  for p in "$@"; do
    [[ -n "$p" ]] && { echo "$p"; return; }
  done
  echo "$SCRIPT_DIR"
}

LEAD_PATH="$SCRIPT_DIR"
FRONTEND_PATH=$(first "$WEB_PATH" "$EXTENSION_PATH" "$API_PATH")
BACKEND_PATH=$(first "$API_PATH" "$WEB_PATH")
MOBILE_AGENT_PATH=$(first "$MOBILE_PATH" "$API_PATH" "$WEB_PATH")
DEVOPS_PATH=$(first "$API_PATH" "$WEB_PATH" "$MOBILE_PATH")
DESIGNER_PATH=$(first "$WEB_PATH" "$MOBILE_PATH" "$API_PATH")
QA_PATH=$(first "$API_PATH" "$WEB_PATH" "$MOBILE_PATH")
REVIEWER_PATH=$(first "$API_PATH" "$WEB_PATH" "$MOBILE_PATH")

# ──────────────────────────────────────────────────────────────
# Kill existing session if present
# ──────────────────────────────────────────────────────────────
if tmux has-session -t "$SESSION" 2>/dev/null; then
  printf "Session '%s' already exists. Kill it? [y/N] " "$SESSION"
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 0; }
  tmux kill-session -t "$SESSION"
fi

# ──────────────────────────────────────────────────────────────
# Create session + panes
# ──────────────────────────────────────────────────────────────
echo "→ Spawning session '$SESSION'..."

# 1. Create session with Lead pane
tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$CLAUDE_CMD"

# 2. Enable pane border + styling
#    - @role + @role_color = user options (program เขียนทับไม่ได้)
#    - pane-border-style: สีเส้นกรอบเมื่อไม่ active
#    - pane-active-border-style: สีเส้นกรอบเมื่อ active (highlight)
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 3. Create 3 columns (Lead | middle | right)
tmux split-window -t "$SESSION:0.0" -h -c "$FRONTEND_PATH" "$CLAUDE_CMD"   # pane 1
tmux split-window -t "$SESSION:0.1" -h -c "$DESIGNER_PATH" "$CLAUDE_CMD"   # pane 2
tmux select-layout -t "$SESSION:0" even-horizontal

# 4. Middle column: 4 equal rows (frontend, backend, mobile, devops)
tmux split-window -t "$SESSION:0.1" -v -l 75% -c "$BACKEND_PATH"       "$CLAUDE_CMD"   # pane 3
tmux split-window -t "$SESSION:0.3" -v -l 67% -c "$MOBILE_AGENT_PATH"  "$CLAUDE_CMD"   # pane 4
tmux split-window -t "$SESSION:0.4" -v -l 50% -c "$DEVOPS_PATH"        "$CLAUDE_CMD"   # pane 5

# 5. Right column: 3 equal rows (designer, qa, reviewer)
tmux split-window -t "$SESSION:0.2" -v -l 67% -c "$QA_PATH"       "$CLAUDE_CMD"   # pane 6
tmux split-window -t "$SESSION:0.6" -v -l 50% -c "$REVIEWER_PATH" "$CLAUDE_CMD"   # pane 7

# 6. Set @role + @role_color per pane (user option — not affected by program output)
#    Dev roles = cool colors, Support roles = warm colors
tmux set-option -p -t "$SESSION:0.1" @role "frontend"  ; tmux set-option -p -t "$SESSION:0.1" @role_color "cyan"
tmux set-option -p -t "$SESSION:0.2" @role "designer"  ; tmux set-option -p -t "$SESSION:0.2" @role_color "colour211"
tmux set-option -p -t "$SESSION:0.3" @role "backend"   ; tmux set-option -p -t "$SESSION:0.3" @role_color "blue"
tmux set-option -p -t "$SESSION:0.4" @role "mobile"    ; tmux set-option -p -t "$SESSION:0.4" @role_color "magenta"
tmux set-option -p -t "$SESSION:0.5" @role "devops"    ; tmux set-option -p -t "$SESSION:0.5" @role_color "green"
tmux set-option -p -t "$SESSION:0.6" @role "qa"        ; tmux set-option -p -t "$SESSION:0.6" @role_color "colour208"
tmux set-option -p -t "$SESSION:0.7" @role "reviewer"  ; tmux set-option -p -t "$SESSION:0.7" @role_color "red"

# 7. Focus Lead
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
cat <<EOF

✓ Session '$SESSION' ready.

Pane mapping:
  Lead     → $SESSION:0.0  ($LEAD_PATH)
  frontend → $SESSION:0.1  ($FRONTEND_PATH)
  designer → $SESSION:0.2  ($DESIGNER_PATH)
  backend  → $SESSION:0.3  ($BACKEND_PATH)
  mobile   → $SESSION:0.4  ($MOBILE_AGENT_PATH)
  devops   → $SESSION:0.5  ($DEVOPS_PATH)
  qa       → $SESSION:0.6  ($QA_PATH)
  reviewer → $SESSION:0.7  ($REVIEWER_PATH)

EOF

# Attach (skip if already in tmux)
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
