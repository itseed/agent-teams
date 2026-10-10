#!/usr/bin/env bash
# start-team.sh — spawn dev-team tmux session with Lead + agent panes
#
# Usage:
#   ./start-team.sh                              # project จาก "active" + roles จาก field "roles" (หรือครบ 8)
#   ./start-team.sh pms                          # ใช้ project ชื่อ "pms"
#   ./start-team.sh pms --roles frontend,qa      # spawn เฉพาะ role ที่ระบุ
#   ./start-team.sh --help                       # แสดง help

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/scripts/lib/common.sh"   # ALL_ROLES, role_*, claude_cmd, provision_agent_dir, ...

windows_guard "start-team.sh"

SESSION="dev-team"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"

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

Spawn (or resume) tmux session "$SESSION" with Lead + agent panes.
If session already exists, prompts to resume — preserving all agent state.

  PROJECT_NAME   ชื่อ project ใน projects.json (ถ้าไม่ระบุใช้ field "active")
  --roles        เลือก role ที่จะ spawn (comma-separated) — ถ้าไม่ระบุใช้
                 field "roles" ของ project ใน projects.json; ถ้าไม่มีทั้งคู่ = ครบ 8

Roles: ${ALL_ROLES[*]}

Layout (dynamic — สร้างเฉพาะ role ที่เลือก):
  Lead │ frontend │ designer      dev roles → คอลัมน์กลาง
       │ backend  │ architect     support roles → คอลัมน์ขวา
       │ mobile   │   qa          คอลัมน์ที่ว่างทั้งคอลัมน์จะไม่ถูกสร้าง
       │ devops   │ reviewer

เพิ่ม role กลาง session ภายหลัง: ./scripts/add-role.sh <role>
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
  echo "   เหมาะกับ session explore/analysis เท่านั้น; เพิ่มทีหลังได้ด้วย ./scripts/add-role.sh qa"
  echo ""
fi

LEAD_PATH="$SCRIPT_DIR"

# ──────────────────────────────────────────────────────────────
# Per-agent temp dirs with CLAUDE.md (role + team protocol + project context)
# Agents start in /tmp/agent-<role>/ so Claude reads the specialist role before
# any task arrives — prevents Lead CLAUDE.md from taking over.
# ──────────────────────────────────────────────────────────────
create_agent_dirs() {
  local role
  for role in "${SELECTED_ROLES[@]}"; do
    provision_agent_dir "$role" "$PROJECT" "$PROJECTS_JSON"
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
tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$(claude_cmd "$MODEL_OPUS" high)"

# 3. Enable mouse support
tmux set-option -g -t "$SESSION" mouse on

# 4. Enable pane border + styling
#    - @role + @role_color = user options (program เขียนทับไม่ได้)
#    - pane-border-style: สีเส้นกรอบเมื่อไม่ active
#    - pane-active-border-style: สีเส้นกรอบเมื่อ active (highlight)
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
# border: "● <Role>  ⎇ <branch>" — branch มาจาก scripts/pane-branch.sh (อ่านจาก pane option @workdir,
# fallback pane_current_path; ไม่ใช่ repo = ไม่แสดง ⎇). status-interval 5s = รอบ refresh ของ #() (set ระดับ session)
PANE_BORDER_FORMAT=" #[fg=#{@role_color},bold]● #{@role}#[default]#($SCRIPT_DIR/scripts/pane-branch.sh -l \"#{@workdir}\" \"#{pane_current_path}\") "
tmux set-option -w -t "$SESSION:0" pane-border-format "$PANE_BORDER_FORMAT"
tmux set-option -t "$SESSION" status-interval 5
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 5. Create columns dynamically (Lead | middle=dev | right=support)
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
  MID_HEAD=$(tmux split-window -t "$SESSION:0.0" -h -c "/tmp/agent-${_r}" -P -F '#{pane_id}' "$(role_cmd "$_r")")
  set_pane "$_r" "$MID_HEAD"
fi
RIGHT_HEAD=""
if [[ ${#RIGHT_SELECTED[@]} -gt 0 ]]; then
  _r="${RIGHT_SELECTED[0]}"
  RIGHT_HEAD=$(tmux split-window -t "${MID_HEAD:-$SESSION:0.0}" -h -c "/tmp/agent-${_r}" -P -F '#{pane_id}' "$(role_cmd "$_r")")
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
    prev=$(tmux split-window -t "$prev" -v -l "${pct}%" -c "/tmp/agent-${_r}" -P -F '#{pane_id}' "$(role_cmd "$_r")")
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

# 8. Set @role + @role_color per pane using stable IDs (not visual indexes)
# Note: 'model:' frontmatter in agent .md files applies only when spawned via Agent tool, not bare CLI
# — every role launches with Opus 5.5; only --effort differs per role (see role_cmd)
# @workdir = repo ที่ agent ทำงาน (pane cwd คือ /tmp/agent-<role> ไม่ใช่ repo) — ใช้แสดง branch บน border
# default จาก projects.json: frontend->web, backend->api, mobile->mobile; role อื่นว่าง (Lead ใช้ pane_current_path)
for _r in "${SELECTED_ROLES[@]}"; do
  _p=$(get_pane "$_r")
  tmux set-option -p -t "$_p" @role "$(role_label "$_r")"
  tmux set-option -p -t "$_p" @role_color "$(role_color "$_r")"
  _wd=$(role_workdir "$_r" "$PROJECT" "$PROJECTS_JSON")
  if [[ -n "$_wd" ]]; then tmux set-option -p -t "$_p" @workdir "$_wd"; fi
done

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
for _r in "${SELECTED_ROLES[@]}"; do
  auto_trust "$(get_pane "$_r")" &
done

# 10a. Patch pane mapping in each agent's CLAUDE.md with actual visual indexes
#       Must run after all panes are created so indexes are stable.
#       Appends an "override" section that takes precedence over any hardcoded table.
patch_pane_maps() {
  local pane_rows="| Lead      | \`$SESSION:0.0\` |"
  local r
  for r in "${SELECTED_ROLES[@]}"; do
    pane_rows="${pane_rows}
| $r | \`$(get_pane "$r")\` |"
  done

  for role in "${SELECTED_ROLES[@]}"; do
    cat >> "/tmp/agent-${role}/CLAUDE.md" <<MAP

---

## Pane Addresses (stable ID — ใช้ตัวนี้เสมอ)
| Role      | Stable Pane ID       |
|-----------|----------------------|
$pane_rows

> ทีมนี้ spawn เฉพาะ role ข้างบน — role อื่นไม่มี pane อยู่ในทีมตอนนี้
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

  local agent_rows="" r
  for r in "${SELECTED_ROLES[@]}"; do
    agent_rows="${agent_rows}| $r | $(get_pane "$r") | idle | — |
"
  done

  local inactive=()
  for r in "${ALL_ROLES[@]}"; do
    role_selected "$r" || inactive+=("$r")
  done
  local inactive_note=""
  if [[ ${#inactive[@]} -gt 0 ]]; then
    inactive_note="Role ที่ไม่ได้ spawn: ${inactive[*]} — ถ้างานต้องใช้ ให้รัน \`./scripts/add-role.sh <role>\` (ห้าม split-window เอง)"
  fi

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
${agent_rows}
## Pipeline Stage
ยังไม่เริ่ม

## Recently Completed
(ยังไม่มี)

## Notes
Session เริ่มใหม่ — Lead ต้อง set Active Project ก่อนรับงาน
${inactive_note}
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

  local pane_lines="" r
  for r in "${SELECTED_ROLES[@]}"; do
    pane_lines="${pane_lines}  $(printf '%-9s' "$(role_label "$r")") → $(get_pane "$r")
"
  done

  local inactive=()
  for r in "${ALL_ROLES[@]}"; do
    role_selected "$r" || inactive+=("$r")
  done
  local inactive_line=""
  if [[ ${#inactive[@]} -gt 0 ]]; then
    inactive_line="
role ที่ไม่ได้ spawn: ${inactive[*]} — ถ้างานต้องใช้ รัน ./scripts/add-role.sh <role> (ห้าม split-window เอง)"
  fi

  local msg
  msg=$(cat <<MSG
[SYSTEM: SESSION_INITIALIZED — อ่านเพื่อรับทราบเท่านั้น ห้ามทำอะไรเพิ่ม]

ทีมพร้อมแล้ว — agents รอรับงาน (stable pane IDs):

$pane_lines$inactive_line

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
  wait_for_claude_prompt "$pane" 40 || true

  tmux set-buffer "$msg" && tmux paste-buffer -t "$pane"
  tmux send-keys -t "$pane" Enter
}
inject_lead_context &

# 11. Focus Lead
tmux select-pane -t "$SESSION:0.0"

# ──────────────────────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────────────────────
echo ""
echo "✓ Session '$SESSION' ready."
echo ""
echo "Pane mapping (stable %ID — agents start in /tmp/agent-<role>/ for role isolation):"
echo "  Lead     → $SESSION:0.0  ($LEAD_PATH)"
for _r in "${SELECTED_ROLES[@]}"; do
  printf '  %-9s→ %s  (/tmp/agent-%s)\n' "$_r" "$(get_pane "$_r")" "$_r"
done
echo ""
echo "(numeric index 0.N ไม่เสถียร — RTK เลื่อน +1; ใช้ stable %ID จาก .team-state.md เสมอ)"
echo "(เพิ่ม role ภายหลัง: ./scripts/add-role.sh <role>)"
echo ""

# Attach (skip if already in tmux)
if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
