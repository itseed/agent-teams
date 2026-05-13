# Multi-Agent V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade agent-teams from tmux-IPC-based coordination to Claude Code native multi-agent using the `Agent` tool, `TaskCreate/TaskUpdate/TaskList`, keeping tmux panes as log viewers.

**Architecture:** Lead uses `Agent` tool to spawn subagents and `TaskCreate/TaskList/TaskUpdate` to track lifecycle. Agents write progress to `/tmp/agent-logs/<role>.log` (displayed in tmux panes via `tail`). Peer communication flows through sequential handoff — Lead injects prior agent results into next agent's spawn context.

**Tech Stack:** bash, tmux, Claude Code (Agent / TaskCreate / TaskUpdate / TaskList tools), `/tmp/agent-logs/`

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `start-team-v2.sh` | **Create** | New launch script: log dirs + Lead pane + log-viewer agent panes |
| `CLAUDE.md` | **Modify** | Replace tmux-IPC orchestration with Agent tool + TaskCreate workflow |
| `.claude/agents/frontend.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/backend.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/mobile.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/devops.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/designer.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/qa.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |
| `.claude/agents/reviewer.md` | **Modify** | Remove tmux comms, add log writing + TaskUpdate |

---

## Task 1: Create branch multi-agent-v2

**Files:** (git only)

- [ ] **Step 1: Create and switch to branch**

```bash
git checkout -b multi-agent-v2
```

Expected: `Switched to a new branch 'multi-agent-v2'`

- [ ] **Step 2: Verify branch**

```bash
git branch --show-current
```

Expected: `multi-agent-v2`

---

## Task 2: Create start-team-v2.sh

**Files:**
- Create: `start-team-v2.sh`

- [ ] **Step 1: Create the script**

```bash
cat > start-team-v2.sh << 'SCRIPT'
#!/usr/bin/env bash
# start-team-v2.sh — multi-agent v2: Lead + log-viewer panes (no agent Claude processes)
#
# Usage:
#   ./start-team-v2.sh              # uses "active" project from projects.json
#   ./start-team-v2.sh pms          # uses project named "pms"
#   ./start-team-v2.sh --help

set -euo pipefail

# Windows native guard
if [[ "${OS:-}" == "Windows_NT" ]] || \
   { [[ -f /proc/version ]] && grep -qi "microsoft" /proc/version && [[ -z "${WSL_DISTRO_NAME:-}" ]]; }; then
  echo "Error: start-team-v2.sh must run inside WSL2" >&2
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

Multi-agent v2: Lead runs Claude Code; agent panes display live logs.
Agents are spawned by Lead via Claude Code Agent tool — not tmux processes.

  PROJECT_NAME   project name in projects.json (default: "active" field)

Layout:
  Lead │ frontend-log │ designer-log
       │ backend-log  │ qa-log
       │ mobile-log   │ reviewer-log
       │ devops-log   │
EOF
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Dependencies
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }
command -v jq   >/dev/null || { echo "Error: jq not found" >&2; exit 1; }
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
# Prepare log directory — truncate all role logs (session-scoped)
# ──────────────────────────────────────────────────────────────
mkdir -p "$LOG_DIR"
for role in "${ROLES[@]}"; do
  truncate -s 0 "$LOG_DIR/${role}.log" 2>/dev/null || true
done

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
echo "→ Spawning session '$SESSION' (v2 multi-agent mode)..."

# 1. Create session with Lead pane
tmux new-session -d -s "$SESSION" -c "$LEAD_PATH" "$CLAUDE_CMD"

# 2. Enable mouse support + pane borders
tmux set-option -g -t "$SESSION" mouse on
tmux set-option -w -t "$SESSION:0" pane-border-status top
tmux set-option -w -t "$SESSION:0" pane-border-style "fg=colour240"
tmux set-option -w -t "$SESSION:0" pane-active-border-style "fg=yellow,bold"
tmux set-option -w -t "$SESSION:0" pane-border-format " #[fg=#{@role_color},bold]● #{@role} "
tmux set-option -p -t "$SESSION:0.0" @role "Lead"
tmux set-option -p -t "$SESSION:0.0" @role_color "yellow"

# 3. RTK Stats pane (optional — splits Lead pane vertically 70/30)
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' 'watch -n 30 rtk gain')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
  RTK_PANE_CREATED=true
fi

# 4. Create 3 columns (Lead | middle | right) — log viewers
PANE_FRONTEND=$(tmux split-window -t "$SESSION:0.0" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/frontend.log")
PANE_DESIGNER=$(tmux split-window -t "$PANE_FRONTEND" -h -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/designer.log")
tmux select-layout -t "$SESSION:0" even-horizontal

# 5. Middle column: 4 rows (frontend, backend, mobile, devops)
PANE_BACKEND=$(tmux split-window -t "$PANE_FRONTEND" -v -l 75% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/backend.log")
PANE_MOBILE=$(tmux split-window -t "$PANE_BACKEND"   -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/mobile.log")
PANE_DEVOPS=$(tmux split-window -t "$PANE_MOBILE"    -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/devops.log")

# 6. Right column: 3 rows (designer, qa, reviewer)
PANE_QA=$(tmux split-window -t "$PANE_DESIGNER" -v -l 67% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/qa.log")
PANE_REVIEWER=$(tmux split-window -t "$PANE_QA" -v -l 50% -c "$LOG_DIR" -P -F '#{pane_id}' "tail -n 200 -f $LOG_DIR/reviewer.log")

# 7. Set @role + @role_color per pane
tmux set-option -p -t "$PANE_FRONTEND" @role "Frontend log" ; tmux set-option -p -t "$PANE_FRONTEND" @role_color "cyan"
tmux set-option -p -t "$PANE_DESIGNER" @role "Designer log" ; tmux set-option -p -t "$PANE_DESIGNER" @role_color "colour211"
tmux set-option -p -t "$PANE_BACKEND"  @role "Backend log"  ; tmux set-option -p -t "$PANE_BACKEND"  @role_color "blue"
tmux set-option -p -t "$PANE_MOBILE"   @role "Mobile log"   ; tmux set-option -p -t "$PANE_MOBILE"   @role_color "magenta"
tmux set-option -p -t "$PANE_DEVOPS"   @role "DevOps log"   ; tmux set-option -p -t "$PANE_DEVOPS"   @role_color "green"
tmux set-option -p -t "$PANE_QA"       @role "QA log"       ; tmux set-option -p -t "$PANE_QA"       @role_color "colour208"
tmux set-option -p -t "$PANE_REVIEWER" @role "Reviewer log" ; tmux set-option -p -t "$PANE_REVIEWER" @role_color "red"

# 8. Inject startup context into Lead
inject_lead_context() {
  local pane="$SESSION:0.0"
  local paths_str
  paths_str=$(jq -r --arg p "$PROJECT" \
    '.projects[$p].paths | to_entries[] | "  \(.key): \(.value)"' \
    "$PROJECTS_JSON" 2>/dev/null || true)

  local mode_note="[v2 multi-agent mode — agents spawned via Agent tool, logs at /tmp/agent-logs/]"

  local msg
  msg=$(cat <<MSG
ทีมพร้อมแล้ว ($mode_note)

project: $PROJECT
$paths_str

Log viewers กำลัง tail ที่ /tmp/agent-logs/<role>.log
Spawn agents ด้วย Agent tool ได้เลย — รอรับ task จากผู้ใช้
MSG
)

  local i=0
  while ! tmux capture-pane -t "$pane" -p 2>/dev/null | grep -qE "❯|bypass permissions"; do
    sleep 1; ((i++)); [[ $i -gt 40 ]] && break
  done

  tmux set-buffer "$msg" && tmux paste-buffer -t "$pane"
  tmux send-keys -t "$pane" Enter
}
inject_lead_context &

# 9. Focus Lead
tmux select-pane -t "$SESSION:0.0"

cat <<EOF

✓ Session '$SESSION' ready (v2 multi-agent mode).

Lead pane: $SESSION:0.0  ($LEAD_PATH)
Log viewers: /tmp/agent-logs/<role>.log

Agents are spawned by Lead via Claude Code Agent tool — not tmux processes.
EOF

if [[ -z "${TMUX:-}" ]]; then
  tmux attach-session -t "$SESSION"
else
  echo "Already inside tmux. Switch with: tmux switch-client -t $SESSION"
fi
SCRIPT
chmod +x start-team-v2.sh
```

- [ ] **Step 2: Verify script is executable and has correct shebang**

```bash
head -3 start-team-v2.sh
```

Expected:
```
#!/usr/bin/env bash
# start-team-v2.sh — multi-agent v2: Lead + log-viewer panes (no agent Claude processes)
```

- [ ] **Step 3: Commit**

```bash
git add start-team-v2.sh
git commit -m "feat(v2): add start-team-v2.sh — log-viewer panes for multi-agent mode"
```

---

## Task 3: Update CLAUDE.md Lead workflow

**Files:**
- Modify: `CLAUDE.md`

The current CLAUDE.md has tmux-IPC orchestration (tmux send-keys, pane mapping table for sending tasks, tmux capture-pane for collecting results). This task replaces that coordination layer with Agent tool + TaskCreate workflow while keeping the project loading, team roster, and session layout reference.

- [ ] **Step 1: Replace the "วิธี spawn teammates" section**

Current text to replace (lines 42–56 in CLAUDE.md, the "วิธี spawn teammates" section):

```
## วิธี spawn teammates

Spawn ด้วย subagent definition ที่มีใน `.claude/agents/` และ inject working directory:

ตัวอย่าง: "Spawn a frontend teammate to work on the login feature. Their working directory is /path/to/your/project/web"
```

Replace with:

```markdown
## วิธี spawn teammates

ใช้ **Agent tool** โดยตรง — ระบุ role, task, working directory และ task_id ในข้อความ:

```
Spawn a [role] specialist.
Working directory: [path]
Task ID: [task_id]   ← agent ใช้เรียก TaskUpdate
Task: [task description]
```

Agent definition ทุกตัวอยู่ใน `.claude/agents/` — Claude Code โหลดให้อัตโนมัติเมื่อ spawn
```

- [ ] **Step 2: Replace "วิธีส่งงานให้ teammate" and "วิธี collect results" sections**

Find and remove this entire block in CLAUDE.md (from "### วิธีส่งงานให้ teammate" through the "### Peer-to-peer communication" section):

```markdown
### วิธีส่งงานให้ teammate

ต้องรัน **2 Bash tool call แยกกัน** เสมอ ...
[entire section up through "Lead ไม่ต้อง relay ข้อความเหล่านี้ — รับรู้ไว้เพื่อ track สถานะการประสานงาน"]
```

Replace with:

```markdown
### Task lifecycle

```
Lead รับ task
  │
  ▼
TaskCreate per subtask              (status: pending)
  │
  ▼
Agent tool spawn                    (status: in_progress — inject task_id ใน prompt)
  ├── parallel ถ้า tasks independent
  └── sequential ถ้า task B ต้องการ result จาก task A
  │
  ▼
Agent executes + writes to /tmp/agent-logs/<role>.log
  │
  ├─ success → TaskUpdate(task_id, "completed") + return result
  └─ error   → TaskUpdate(task_id, "error") + return error detail
  │
  ▼
Lead: ตรวจ TaskList
  ├─ all done    → summarize, notify user
  └─ has errors  → retry once with error context; escalate if still failing
```

### วิธี collect results

Agent tool ส่ง result กลับมาโดยตรงเมื่อ subagent เสร็จ — ไม่ต้องรัน `tmux capture-pane`

ถ้าต้องการดู live progress ให้ดูที่ tmux log-viewer panes (`tail -n 200 -f /tmp/agent-logs/<role>.log`)

### Peer communication (sequential handoff)

1. Agent A เสร็จ → ส่ง result กลับมา Lead
2. Lead inject result ของ Agent A เป็น context ตอน spawn Agent B
3. ไม่มี realtime messaging ระหว่าง concurrent agents

### Error handling

| Case | Action |
|------|--------|
| Agent returns error | Retry once — append error context ใน prompt ใหม่ |
| Partial failure | Re-spawn เฉพาะ task ที่ failed |
```

- [ ] **Step 3: Update pane index table — add note that agent panes show logs not Claude**

Find the pane index table in CLAUDE.md:

```markdown
| Role | Pane index |
|---|---|
| Lead | `dev-team:0.0` |
| frontend | `dev-team:0.1` |
...
```

Add a note below the table:

```markdown
> **v2 mode (start-team-v2.sh):** agent panes แสดง `tail -f /tmp/agent-logs/<role>.log` แทน Claude process — Lead spawn agents ผ่าน Agent tool
```

- [ ] **Step 4: Remove the "วิธีส่งงานให้ agent วิเคราะห์ก่อนทำ" lesson that references tmux**

Find and update the last บทเรียน section to not reference tmux send-keys. The lesson about analysis-first still applies; just remove the tmux-specific mechanics.

- [ ] **Step 5: Verify CLAUDE.md compiles (no obvious broken markdown)**

```bash
grep -n "tmux set-buffer\|tmux paste-buffer\|tmux send-keys" CLAUDE.md | grep -v "ตัวอย่าง\|# " | head -20
```

Expected: only lines inside commented/example blocks, no active instructions

- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "feat(v2): update Lead CLAUDE.md — Agent tool + TaskCreate orchestration"
```

---

## Task 4: Update agent files — remove tmux IPC, add log writing + TaskUpdate

All 7 agent files share the same structure. Each needs:
1. **Remove** the "การสื่อสารระหว่าง agents" section (pane mapping table + tmux send-keys commands)
2. **Remove** the "การรายงานกลับเมื่อเสร็จ" tmux section
3. **Add** "การเขียน log" section (write to `/tmp/agent-logs/<role>.log`)
4. **Add** "การ update task status" section (TaskUpdate with injected task_id)
5. **Keep** everything else: SPECIALIST OVERRIDE, domain expertise, วิธีทำงาน steps

The log format standard (from spec):
```
=== Task: <task-name> [ISO-8601 timestamp] ===
[<role>] <progress message>
[<role>] ✓ <success message>
[<role>] ✗ Error: <error detail>
```

### 4a: frontend.md

**Files:**
- Modify: `.claude/agents/frontend.md`

- [ ] **Step 1: Replace the communication + report-back sections**

The section to REMOVE starts at line 22 (`## การสื่อสารระหว่าง agents`) through end of file (line 60). Replace with:

```markdown
## การเขียน log

เขียน progress ลงไฟล์ตลอดการทำงาน — tmux pane ของคุณแสดงไฟล์นี้แบบ real-time:

```bash
# เขียน header เมื่อเริ่ม task
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/frontend.log

# เขียน progress
echo "[frontend] กำลังทำ <step>" >> /tmp/agent-logs/frontend.log

# เขียนเมื่อเสร็จ
echo "[frontend] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/frontend.log

# เขียนเมื่อ error
echo "[frontend] ✗ Error: <error detail>" >> /tmp/agent-logs/frontend.log
```

## การ update task status

Lead จะ inject `task_id` ใน prompt ตอน spawn — ใช้เรียก TaskUpdate:

- เมื่อเริ่มงาน: เรียก `TaskUpdate` กับ status `in_progress`
- เมื่อเสร็จสมบูรณ์: เรียก `TaskUpdate` กับ status `completed`
- เมื่อเกิด error: เรียก `TaskUpdate` กับ status `error` แล้วใส่ error detail ใน return value

ผลลัพธ์สุดท้ายให้ **return กลับโดยตรง** — Lead รับผ่าน Agent tool result โดยอัตโนมัติ
```

- [ ] **Step 2: Also update วิธีทำงาน step 4 to remove tmux reference**

Find in frontend.md:
```
4. Mark task complete และ notify Lead เมื่อเสร็จ
```

Replace with:
```
4. TaskUpdate(task_id, "completed") แล้ว return ผลลัพธ์
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/frontend.md
git commit -m "feat(v2): frontend agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4b: backend.md

**Files:**
- Modify: `.claude/agents/backend.md`

- [ ] **Step 1: Replace communication + report-back sections (same pattern as frontend)**

Remove from line 22 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/backend.log
echo "[backend] กำลังทำ <step>" >> /tmp/agent-logs/backend.log
echo "[backend] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/backend.log
echo "[backend] ✗ Error: <error detail>" >> /tmp/agent-logs/backend.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return ผลลัพธ์
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 5**

Find:
```
5. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
5. TaskUpdate(task_id, "completed") แล้ว return ผลลัพธ์ — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/backend.md
git commit -m "feat(v2): backend agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4c: mobile.md

**Files:**
- Modify: `.claude/agents/mobile.md`

- [ ] **Step 1: Replace communication + report-back sections**

Remove from line 31 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/mobile.log
echo "[mobile] กำลังทำ <step>" >> /tmp/agent-logs/mobile.log
echo "[mobile] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/mobile.log
echo "[mobile] ✗ Error: <error detail>" >> /tmp/agent-logs/mobile.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return ผลลัพธ์
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 6**

Find:
```
6. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
6. TaskUpdate(task_id, "completed") แล้ว return ผลลัพธ์ — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/mobile.md
git commit -m "feat(v2): mobile agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4d: devops.md

**Files:**
- Modify: `.claude/agents/devops.md`

- [ ] **Step 1: Replace communication + report-back sections**

Remove from line 25 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/devops.log
echo "[devops] กำลังทำ <step>" >> /tmp/agent-logs/devops.log
echo "[devops] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/devops.log
echo "[devops] ✗ Error: <error detail>" >> /tmp/agent-logs/devops.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return ผลลัพธ์
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 6**

Find:
```
6. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
6. TaskUpdate(task_id, "completed") แล้ว return ผลลัพธ์ — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/devops.md
git commit -m "feat(v2): devops agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4e: designer.md

**Files:**
- Modify: `.claude/agents/designer.md`

- [ ] **Step 1: Replace communication + report-back sections**

Remove from line 27 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/designer.log
echo "[designer] กำลังทำ <step>" >> /tmp/agent-logs/designer.log
echo "[designer] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/designer.log
echo "[designer] ✗ Error: <error detail>" >> /tmp/agent-logs/designer.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return ผลลัพธ์
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 6**

Find:
```
6. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
6. TaskUpdate(task_id, "completed") แล้ว return spec/artifacts — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/designer.md
git commit -m "feat(v2): designer agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4f: qa.md

**Files:**
- Modify: `.claude/agents/qa.md`

- [ ] **Step 1: Replace communication + report-back sections**

Remove from line 25 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/qa.log
echo "[qa] กำลังทำ <step>" >> /tmp/agent-logs/qa.log
echo "[qa] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/qa.log
echo "[qa] ✗ Error: <error detail>" >> /tmp/agent-logs/qa.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return ผลลัพธ์ (test report + failures/coverage gaps)
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 5**

Find:
```
5. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
5. TaskUpdate(task_id, "completed") แล้ว return test report — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/qa.md
git commit -m "feat(v2): qa agent — replace tmux IPC with log writing + TaskUpdate"
```

### 4g: reviewer.md

**Files:**
- Modify: `.claude/agents/reviewer.md`

- [ ] **Step 1: Replace communication + report-back sections**

Remove from line 33 (`## การสื่อสารระหว่าง agents`) to end of file. Replace with:

```markdown
## การเขียน log

```bash
echo "=== Task: <task-name> [$(date -u +%Y-%m-%dT%H:%M:%SZ)] ===" >> /tmp/agent-logs/reviewer.log
echo "[reviewer] กำลังทำ <step>" >> /tmp/agent-logs/reviewer.log
echo "[reviewer] ✓ เสร็จสิ้น: <summary>" >> /tmp/agent-logs/reviewer.log
echo "[reviewer] ✗ Error: <error detail>" >> /tmp/agent-logs/reviewer.log
```

## การ update task status

Lead inject `task_id` ใน prompt — ใช้เรียก `TaskUpdate`:

- เมื่อเริ่มงาน: `TaskUpdate(task_id, "in_progress")`
- เมื่อเสร็จ: `TaskUpdate(task_id, "completed")` + return review report
- เมื่อ error: `TaskUpdate(task_id, "error")` + return error detail
```

- [ ] **Step 2: Update วิธีทำงาน step 6**

Find:
```
6. Mark task complete และ notify Lead เมื่อเสร็จ
```
Replace with:
```
6. TaskUpdate(task_id, "completed") แล้ว return review report — Lead รับผ่าน Agent tool
```

- [ ] **Step 3: Commit**

```bash
git add .claude/agents/reviewer.md
git commit -m "feat(v2): reviewer agent — replace tmux IPC with log writing + TaskUpdate"
```

---

## Task 5: Final verification + push

- [ ] **Step 1: Verify agent files no longer contain tmux send-keys**

```bash
grep -l "tmux set-buffer\|tmux send-keys\|tmux paste-buffer" .claude/agents/*.md
```

Expected: no output (empty — no files match)

- [ ] **Step 2: Verify all agent files have log section**

```bash
grep -l "agent-logs" .claude/agents/*.md
```

Expected: all 7 files listed

- [ ] **Step 3: Verify start-team-v2.sh exists and is executable**

```bash
ls -la start-team-v2.sh
```

Expected: `-rwxr-xr-x` permissions

- [ ] **Step 4: Verify git log on branch**

```bash
git log --oneline -12
```

Expected: branch commits for start-team-v2.sh, CLAUDE.md, and all 7 agent files

- [ ] **Step 5: Push branch**

```bash
git push -u origin multi-agent-v2
```

Expected: `Branch 'multi-agent-v2' set up to track remote branch`
