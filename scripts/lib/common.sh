# scripts/lib/common.sh — shared helpers for start-team*.sh / add-role.sh / restore-*.sh
#
# Source it (don't execute):  source "<agent-teams>/scripts/lib/common.sh"
# Single source of truth for role list, labels, colors, model/effort, and per-agent dir
# provisioning — แก้ที่นี่ที่เดียว ไม่ต้องไล่แก้หลายสคริปต์
# bash 3.2 compatible (macOS default) — no associative arrays

AGENT_TEAMS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." && pwd )"

ALL_ROLES=(frontend backend mobile devops designer architect qa reviewer)
DEV_ROLES=(frontend backend mobile devops)        # คอลัมน์กลาง
SUPPORT_ROLES=(designer architect qa reviewer)    # คอลัมน์ขวา

is_valid_role() { [[ " ${ALL_ROLES[*]} " == *" $1 "* ]]; }

# Model pinned explicitly (ไม่ขึ้นกับ default ของเครื่อง): Opus 5.5 ทุก role + Lead
# ความต่างระหว่าง role อยู่ที่ --effort อย่างเดียว
MODEL_OPUS="claude-opus-5-5"

# claude_cmd <model> <effort>
claude_cmd() { echo "claude --model $1 --effort $2 --dangerously-skip-permissions; read"; }

# high = architect/reviewer/qa · medium = frontend/backend/mobile/devops · low = designer
role_effort() {
  case "$1" in
    architect|reviewer|qa) echo high ;;
    designer)              echo low ;;
    *)                     echo medium ;;
  esac
}
role_cmd() { claude_cmd "$MODEL_OPUS" "$(role_effort "$1")"; }

role_label() {
  case "$1" in
    frontend) echo "Frontend" ;;  backend)   echo "Backend"   ;;
    mobile)   echo "Mobile"   ;;  devops)    echo "DevOps"    ;;
    designer) echo "Designer" ;;  architect) echo "Architect" ;;
    qa)       echo "QA"       ;;  reviewer)  echo "Reviewer"  ;;
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

# Dynamic pane-id storage
pane_var() { echo "PANE_$(echo "$1" | tr '[:lower:]' '[:upper:]')"; }
set_pane() { eval "$(pane_var "$1")=\"\$2\""; }
get_pane() { eval "echo \"\${$(pane_var "$1"):-}\""; }

# role_workdir <role> <project> <projects.json> — repo default ของ role (ใช้แสดง branch บน border)
role_workdir() {
  local key
  case "$1" in
    frontend) key=web ;; backend) key=api ;; mobile) key=mobile ;; *) return 0 ;;
  esac
  jq -r --arg p "$2" --arg k "$key" '.projects[$p].paths[$k] // ""' "$3"
}

# windows_guard <script-name> — must run inside WSL2, not CMD/PowerShell
windows_guard() {
  if [[ "${OS:-}" == "Windows_NT" ]] || \
     { [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version && [[ -z "${WSL_DISTRO_NAME:-}" ]]; }; then
    cat >&2 <<EOF
Error: $1 ต้องรันใน WSL2 เท่านั้น ไม่รองรับ Windows CMD/PowerShell โดยตรง

วิธีแก้:
  1. ติดตั้ง WSL2 ด้วย setup-windows.ps1 (PowerShell as Administrator):
       .\\setup-windows.ps1
  2. เปิด Ubuntu terminal แล้วไปที่ repo:
       cd ~/agent-teams
  3. รันใหม่:
       ./$1
EOF
    exit 1
  fi
}

# provision_agent_dir <role> <project> <projects.json>
# สร้าง /tmp/agent-<role>/CLAUDE.md (role .md ไม่มี frontmatter + team protocol + project context)
# Agents start here so Claude reads the specialist role before any task arrives.
provision_agent_dir() {
  local role="$1" project="$2" projects_json="$3"
  local dir="/tmp/agent-${role}"
  local src="$AGENT_TEAMS_DIR/.claude/agents/${role}.md"
  local protocol="$AGENT_TEAMS_DIR/templates/agent-protocol.md"
  [[ -f "$src" ]] || { echo "Error: $src not found" >&2; return 1; }

  mkdir -p "$dir/.claude" /tmp/agent-status
  : > "/tmp/agent-status/${role}.md"
  rm -f "/tmp/agent-status/${role}.key"   # pane สด → งานแรกไม่ต้อง /clear (ดู scripts/dispatch.sh)

  # Strip YAML frontmatter (--- ... ---) then write as CLAUDE.md
  awk '/^---$/{found++; next} found==1{next} {print}' "$src" > "$dir/CLAUDE.md"

  # Shared team protocol (ack / status file / report-back / peer messages) — ROLE + TEAM_SEND + HEAVY substituted
  if [[ -f "$protocol" ]]; then
    printf '\n---\n\n' >> "$dir/CLAUDE.md"
    sed -e "s|{{ROLE}}|${role}|g" -e "s|{{TEAM_SEND}}|${AGENT_TEAMS_DIR}/scripts/team-send.sh|g" \
      -e "s|{{HEAVY}}|${AGENT_TEAMS_DIR}/scripts/heavy.sh|g" \
      "$protocol" >> "$dir/CLAUDE.md"
  fi

  # auto-compact so agents don't hang at 100% context; disable Remote Control so only Lead
  # registers as an RC session (teammates run from /tmp/agent-<role>, not the repo root)
  # PreToolUse guard: heavy commands (jest/playwright/build/tsc/docker build) must go through heavy.sh
  # — one at a time machine-wide + timeout (parallel runs froze the 16 GB Mac repeatedly)
  jq -n --arg guard "$AGENT_TEAMS_DIR/scripts/heavy-guard.py" '{
    autoCompactEnabled: true, disableRemoteControl: true,
    hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: $guard, timeout: 10}]}]}
  }' > "$dir/.claude/settings.json"

  local proj_description proj_paths_md
  proj_description=$(jq -r --arg p "$project" '.projects[$p].description // ""' "$projects_json" 2>/dev/null || true)
  proj_paths_md=$(jq -r --arg p "$project" \
    '.projects[$p].paths | to_entries[] | "- **\(.key)**: \(.value)"' \
    "$projects_json" 2>/dev/null || true)

  cat >> "$dir/CLAUDE.md" <<CONTEXT

---

## Active Project: $project
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

# capture-pane -J joins wrapped lines (narrow pane wraps "trust this folder"); -S -50 includes lines
# pushed into scrollback when a later split shrinks the pane
# auto_trust <pane> — answer Claude's one-time "trust this folder" prompt (run in background)
auto_trust() {
  local pane="$1" i=0
  while [[ $i -lt 30 ]]; do
    if tmux capture-pane -J -S -50 -t "$pane" -p 2>/dev/null | grep -q "trust this folder"; then
      tmux send-keys -t "$pane" "1" Enter
      return 0
    fi
    sleep 0.5
    i=$((i + 1))   # NOT ((i++)) — returns 1 when i=0 and kills the loop under set -e
  done
}

# wait_for_claude_prompt <pane> [max_secs] — block until Claude's input prompt is visible
wait_for_claude_prompt() {
  local pane="$1" max="${2:-40}" i=0
  while ! tmux capture-pane -J -t "$pane" -p 2>/dev/null | grep -qE "❯|bypass permissions"; do
    sleep 1
    i=$((i + 1))
    [[ $i -gt $max ]] && return 1
  done
  return 0
}

# resolve_session — --session override ($SESSION_OVERRIDE) > tmux reality (v1/v2) > .team-state.md Mode
# ใช้กับ restore-*.sh (stop-team.sh มี variant แบบ interactive ของตัวเอง)
resolve_session() {
  if [[ -n "${SESSION_OVERRIDE:-}" ]]; then
    echo "$SESSION_OVERRIDE"
    return 0
  fi

  local v1_up=0 v2_up=0
  tmux has-session -t dev-team    2>/dev/null && v1_up=1
  tmux has-session -t dev-team-v2 2>/dev/null && v2_up=1

  if [[ "$v1_up" -eq 1 && "$v2_up" -eq 1 ]]; then
    echo "Error: ทั้ง 'dev-team' (v1) และ 'dev-team-v2' (v2) กำลังรันอยู่พร้อมกัน — ระบุ session ที่ต้องการด้วย --session dev-team หรือ --session dev-team-v2" >&2
    exit 1
  elif [[ "$v1_up" -eq 1 ]]; then
    echo "dev-team"; return 0
  elif [[ "$v2_up" -eq 1 ]]; then
    echo "dev-team-v2"; return 0
  fi

  if [[ -f "$AGENT_TEAMS_DIR/.team-state.md" ]] && grep -q "_Mode: v2" "$AGENT_TEAMS_DIR/.team-state.md"; then
    echo "dev-team-v2"
  else
    echo "dev-team"
  fi
}

# ask_dashboard <mode> — ตัดสินว่าจะเปิด dashboard ไหม → echo "yes"/"no"
# mode: "yes"/"no" (จาก --dashboard/--no-dashboard) ข้ามคำถาม; "" = ถาม (default No)
# stdin ไม่ใช่ terminal (เช่นรันจาก script อื่น) → "no" โดยไม่ถาม
ask_dashboard() {
  local mode="$1" ans
  if [[ -n "$mode" ]]; then echo "$mode"; return; fi
  if [[ ! -t 0 ]]; then echo "no"; return; fi
  printf "เปิดหน้าเว็บ Office Floor dashboard ด้วยไหม? [y/N] " >&2
  read -r ans || ans=""
  if [[ "$ans" == "y" || "$ans" == "Y" ]]; then echo "yes"; else echo "no"; fi
}

DASHBOARD_PID_FILE="/tmp/agent-teams-dashboard.pid"
DASHBOARD_LOG="/tmp/agent-teams-dashboard.log"

# _dashboard_url — URL ของ dashboard server (port จาก DASHBOARD_PORT, default 4780)
_dashboard_url() { echo "http://127.0.0.1:${DASHBOARD_PORT:-4780}/"; }

# _dashboard_up — 0 ถ้า /api/state ตอบ
_dashboard_up() {
  python3 -c 'import sys,urllib.request; urllib.request.urlopen(sys.argv[1], timeout=1)' \
    "$(_dashboard_url)api/state" >/dev/null 2>&1
}

# _open_url <url> — เปิด browser (macOS / WSL / Linux); DASHBOARD_NO_BROWSER=1 = ข้าม (ใช้ตอน test)
_open_url() {
  [[ "${DASHBOARD_NO_BROWSER:-0}" == "1" ]] && return 0
  if [[ "$(uname -s)" == "Darwin" ]] && command -v open >/dev/null 2>&1; then
    open "$1"
  elif command -v wslview >/dev/null 2>&1; then
    wslview "$1"
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$1" >/dev/null 2>&1 &
  else
    echo "⚠️  ไม่พบคำสั่งเปิด browser — เปิดเองที่: $1" >&2
  fi
}

# start_dashboard [project] — (re)start dashboard server (dashboard/server.py) เบื้องหลังแล้วเปิด browser
# มี server เดิมจาก pid file → ปิดก่อนแล้วเริ่มใหม่ (project อาจเปลี่ยนจากรอบก่อน)
# project = ชื่อที่แสดงจนกว่า Lead จะ set Active Project ใน .team-state.md
# ทุก failure แค่เตือน (return 0 เสมอ — ไม่ทำให้ start-team ล้ม)
start_dashboard() {
  local project="${1:-}" url pid i
  url=$(_dashboard_url)
  if ! command -v python3 >/dev/null 2>&1; then
    echo "⚠️  ไม่พบ python3 — ข้ามการเปิด dashboard" >&2
    return 0
  fi

  stop_dashboard >/dev/null
  for i in 1 2 3 4; do _dashboard_up || break; sleep 0.25; done   # รอ port ว่างหลังปิดตัวเดิม
  nohup python3 "$AGENT_TEAMS_DIR/dashboard/server.py" --port "${DASHBOARD_PORT:-4780}" \
    ${project:+--project "$project"} >"$DASHBOARD_LOG" 2>&1 </dev/null &
  pid=$!
  echo "$pid" > "$DASHBOARD_PID_FILE"
  for i in 1 2 3 4 5 6; do
    _dashboard_up && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.5
  done
  if ! _dashboard_up || ! kill -0 "$pid" 2>/dev/null; then
    echo "⚠️  dashboard server เริ่มไม่สำเร็จ — ดู $DASHBOARD_LOG" >&2
    kill "$pid" 2>/dev/null || true
    rm -f "$DASHBOARD_PID_FILE"
    return 0
  fi
  echo "→ dashboard server เริ่มแล้ว (pid $pid)"
  _open_url "$url"
  echo "→ dashboard: $url"
}

# stop_dashboard — ปิด dashboard server จาก pid file (ไม่มี/ตายแล้ว → เงียบ)
stop_dashboard() {
  local pid
  pid=$(cat "$DASHBOARD_PID_FILE" 2>/dev/null || true)
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    echo "  ✓ stopped dashboard server (pid $pid)"
  fi
  rm -f "$DASHBOARD_PID_FILE"
  return 0
}
