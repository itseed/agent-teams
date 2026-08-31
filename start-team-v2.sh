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

SESSION="dev-team-v2"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"
CLAUDE_CMD="claude --dangerously-skip-permissions; read"
LOG_DIR="/tmp/agent-logs"
ALL_ROLES=(frontend backend mobile devops designer architect qa reviewer)
DEV_ROLES=(frontend backend mobile devops)        # คอลัมน์กลาง
SUPPORT_ROLES=(designer architect qa reviewer)    # คอลัมน์ขวา
# Robust per-role log viewer: follows <role>*.log (รวมไฟล์ชื่อเพี้ยนที่ agent สร้าง)
# แทน `tail -f <role>.log` แบบ exact-name ที่พลาดเมื่อ sub-agent เขียนชื่อไฟล์ไม่ตรง
LOG_PANE="$SCRIPT_DIR/scripts/log-pane.sh"

# ──────────────────────────────────────────────────────────────
# Parse args: [PROJECT_NAME] [--roles a,b,c]
# ──────────────────────────────────────────────────────────────
PROJECT_ARG=""
ROLES_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [PROJECT_NAME] [--roles ROLE1,ROLE2,...]

Spawn (or resume) tmux session "$SESSION" in v2 multi-agent mode.
Lead pane runs Claude; agent panes show live log streams from
/tmp/agent-logs/<role>.log — agents are spawned by Lead via the Agent tool.

If session already exists, prompts to resume — preserving all state.

  PROJECT_NAME   ชื่อ project ใน projects.json (ถ้าไม่ระบุใช้ field "active")
  --roles        เลือก role ที่จะ spawn log pane (comma-separated) — ถ้าไม่ระบุใช้
                 field "roles" ของ project ใน projects.json; ถ้าไม่มีทั้งคู่ = ครบ 8

Roles: ${ALL_ROLES[*]}

Layout (dynamic — สร้างเฉพาะ log pane ของ role ที่เลือก):
  Lead │ frontend log │ designer log      dev roles → คอลัมน์กลาง
       │ backend log  │ architect log     support roles → คอลัมน์ขวา
       │ mobile log   │   qa log          คอลัมน์ที่ว่างทั้งคอลัมน์จะไม่ถูกสร้าง
       │ devops log   │ reviewer log

Agent log panes will show "(waiting for first agent spawn)" until Lead spawns the first agent.

[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]
EOF
      exit 0
      ;;
    --roles)
      ROLES_ARG="${2:-}"
      [[ -n "$ROLES_ARG" ]] || { echo "Error: --roles ต้องระบุรายชื่อ role" >&2; exit 1; }
      shift
      ;;
    --roles=*)
      ROLES_ARG="${1#--roles=}"
      ;;
    -*)
      echo "Unknown option: $1 (run with --help)" >&2
      exit 1
      ;;
    *)
      PROJECT_ARG="$1"
      ;;
  esac
  shift
done

# ──────────────────────────────────────────────────────────────
# Dependencies
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "Error: jq not found (brew install jq)" >&2; exit 1; }
[[ -f "$PROJECTS_JSON" ]]  || { echo "Error: $PROJECTS_JSON not found" >&2; exit 1; }

# ──────────────────────────────────────────────────────────────
# Determine project
# ──────────────────────────────────────────────────────────────
PROJECT="${PROJECT_ARG:-$(jq -r '.active' "$PROJECTS_JSON")}"

if ! jq -e --arg p "$PROJECT" '.projects[$p]' "$PROJECTS_JSON" >/dev/null; then
  echo "Error: project '$PROJECT' not found in projects.json" >&2
  echo "Available: $(jq -r '.projects | keys | join(", ")' "$PROJECTS_JSON")" >&2
  exit 1
fi

echo "→ Project: $PROJECT"

LEAD_PATH="$SCRIPT_DIR"

# ──────────────────────────────────────────────────────────────
# Resolve selected roles: --roles > projects.json .roles > all 8
# ──────────────────────────────────────────────────────────────
if [[ -z "$ROLES_ARG" ]]; then
  ROLES_ARG=$(jq -r --arg p "$PROJECT" '.projects[$p].roles // [] | join(",")' "$PROJECTS_JSON" 2>/dev/null || true)
fi

SELECTED_ROLES=()
if [[ -z "$ROLES_ARG" ]]; then
  SELECTED_ROLES=("${ALL_ROLES[@]}")
else
  IFS=',' read -r -a _raw_roles <<< "$ROLES_ARG"
  for _r in "${_raw_roles[@]}"; do
    _r=$(echo "$_r" | tr -d '[:space:]')
    [[ -n "$_r" ]] || continue
    if [[ " ${ALL_ROLES[*]} " != *" $_r "* ]]; then
      echo "Error: unknown role '$_r' (valid: ${ALL_ROLES[*]})" >&2
      exit 1
    fi
    if [[ " ${SELECTED_ROLES[*]-} " != *" $_r "* ]]; then
      SELECTED_ROLES+=("$_r")
    fi
  done
fi

[[ ${#SELECTED_ROLES[@]} -gt 0 ]] || { echo "Error: ไม่มี role ที่จะ spawn" >&2; exit 1; }

role_selected() { [[ " ${SELECTED_ROLES[*]} " == *" $1 "* ]]; }

echo "→ Roles (${#SELECTED_ROLES[@]}): ${SELECTED_ROLES[*]}"

if ! role_selected qa || ! role_selected reviewer; then
  echo ""
  echo "⚠️  ทีมนี้ไม่มี qa/reviewer ครบ — pipeline QA→Reviewer ก่อน merge จะใช้ไม่ได้"
  echo "   เหมาะกับ session explore/analysis เท่านั้น; เพิ่มทีหลังได้ด้วยการรัน --roles ใหม่พร้อม qa/reviewer"
  echo ""
fi

# ──────────────────────────────────────────────────────────────
# Per-role attributes (log pane label / border color)
# ──────────────────────────────────────────────────────────────
role_label() {
  case "$1" in
    frontend) echo "Frontend log" ;;  backend) echo "Backend log" ;;
    mobile)   echo "Mobile log"   ;;  devops)  echo "DevOps log"  ;;
    designer) echo "Designer log" ;;  architect) echo "Architect log" ;;
    qa)       echo "QA log"       ;;  reviewer) echo "Reviewer log" ;;
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

# Dynamic pane-id storage (bash 3.2 compatible — no associative arrays)
pane_var() { echo "PANE_$(echo "$1" | tr '[:lower:]' '[:upper:]')"; }
set_pane() { eval "$(pane_var "$1")=\"\$2\""; }
get_pane() { eval "echo \"\${$(pane_var "$1"):-}\""; }

# ──────────────────────────────────────────────────────────────
# Prepare /tmp/agent-logs/ — create dir and truncate each selected role's log
# ──────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
for role in "${SELECTED_ROLES[@]}"; do
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

# 5. Create columns dynamically (Lead | middle=dev | right=support) using log-viewer panes
# สร้างเฉพาะคอลัมน์ที่มี role ถูกเลือก — คอลัมน์ว่างไม่สร้าง pane ที่เหลือได้พื้นที่มากขึ้น
# Capture stable pane IDs with -P -F '#{pane_id}' so subsequent splits always
# target the correct pane regardless of how tmux renumbers visual indexes.
MID_SELECTED=()
for _r in "${DEV_ROLES[@]}"; do role_selected "$_r" && MID_SELECTED+=("$_r") || true; done
RIGHT_SELECTED=()
for _r in "${SUPPORT_ROLES[@]}"; do role_selected "$_r" && RIGHT_SELECTED+=("$_r") || true; done

MID_HEAD=""
if [[ ${#MID_SELECTED[@]} -gt 0 ]]; then
  _r="${MID_SELECTED[0]}"
  MID_HEAD=$(tmux split-window -t "$SESSION:0.0" -h -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' $_r '$LOG_DIR'")
  set_pane "$_r" "$MID_HEAD"
fi
RIGHT_HEAD=""
if [[ ${#RIGHT_SELECTED[@]} -gt 0 ]]; then
  _r="${RIGHT_SELECTED[0]}"
  RIGHT_HEAD=$(tmux split-window -t "${MID_HEAD:-$SESSION:0.0}" -h -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' $_r '$LOG_DIR'")
  set_pane "$_r" "$RIGHT_HEAD"
fi
tmux select-layout -t "$SESSION:0" even-horizontal

# 6-7. Fill each column with equal rows for its remaining roles
# split percentage: เพิ่ม pane ที่ k จาก n → เหลือพื้นที่ (n-k+1)/(n-k+2) (เทียบเท่า 75/67/50 เดิมเมื่อ n=4)
fill_column() {
  local prev="$1"; shift
  local total=$(( $# + 1 ))
  local k=2 _r pct
  for _r in "$@"; do
    pct=$(( (total - k + 1) * 100 / (total - k + 2) ))
    prev=$(tmux split-window -t "$prev" -v -l "${pct}%" -c "$LOG_DIR" -P -F '#{pane_id}' "'$LOG_PANE' $_r '$LOG_DIR'")
    set_pane "$_r" "$prev"
    k=$(( k + 1 ))
  done
}
if [[ ${#MID_SELECTED[@]} -gt 1 ]]; then
  fill_column "$MID_HEAD" "${MID_SELECTED[@]:1}"
fi
if [[ ${#RIGHT_SELECTED[@]} -gt 1 ]]; then
  fill_column "$RIGHT_HEAD" "${RIGHT_SELECTED[@]:1}"
fi

# 8. Set @role + @role_color per pane using stable IDs
for _r in "${SELECTED_ROLES[@]}"; do
  _p=$(get_pane "$_r")
  tmux set-option -p -t "$_p" @role "$(role_label "$_r")"
  tmux set-option -p -t "$_p" @role_color "$(role_color "$_r")"
done

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

  local agent_rows="" r
  for r in "${SELECTED_ROLES[@]}"; do
    agent_rows="${agent_rows}| $r | $(get_pane "$r") | ${LOG_DIR}/${r}.log |
"
  done

  local inactive=()
  for r in "${ALL_ROLES[@]}"; do
    role_selected "$r" || inactive+=("$r")
  done
  local inactive_note=""
  if [[ ${#inactive[@]} -gt 0 ]]; then
    inactive_note="Role ที่ไม่ได้ spawn log pane: ${inactive[*]} — spawn agent ได้ปกติผ่าน Agent tool แต่จะไม่มี log pane ให้ tail"
  fi

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
${agent_rows}
## Pipeline Stage
ยังไม่เริ่ม

## Recently Completed
(ยังไม่มี)

## Notes
v2 mode — ส่งงานผ่าน Agent tool (return value) ไม่ใช่ tmux paste; Lead ต้อง set Active Project ก่อนรับงานแรก
${inactive_note}
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

  local pane_lines="" r
  for r in "${SELECTED_ROLES[@]}"; do
    pane_lines="${pane_lines}  $(printf '%-13s' "$(role_label "$r")") → $(get_pane "$r")
"
  done

  local inactive=()
  for r in "${ALL_ROLES[@]}"; do
    role_selected "$r" || inactive+=("$r")
  done
  local inactive_line=""
  if [[ ${#inactive[@]} -gt 0 ]]; then
    inactive_line="
role ที่ไม่มี log pane: ${inactive[*]} — spawn agent ได้ปกติผ่าน Agent tool แต่จะไม่มี pane ให้ tail log"
  fi

  local msg
  msg=$(cat <<MSG
ทีมพร้อมแล้ว (v2 multi-agent mode) — agent panes แสดง log streams (stable pane %ID):

${rtk_line}${pane_lines}${inactive_line}

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
echo ""
echo "✓ Session '$SESSION' ready (v2 multi-agent mode)."
echo ""
echo "Lead pane runs Claude; agent panes stream live logs from $LOG_DIR/"
echo ""
echo "Pane mapping (stable %ID — numeric index เลื่อนได้เมื่อมี RTK pane):"
echo "  Lead          → $SESSION:0.0  ($LEAD_PATH)"
for _r in "${SELECTED_ROLES[@]}"; do
  printf '  %-13s → %s  (%s/%s.log)\n' "$(role_label "$_r")" "$(get_pane "$_r")" "$LOG_DIR" "$_r"
done
echo ""

# Attach or switch to session
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  tmux switch-client -t "$SESSION"
fi
