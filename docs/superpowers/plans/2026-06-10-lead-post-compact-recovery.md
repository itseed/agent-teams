# Lead Post-Compact Recovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** แก้ปัญหา Lead ลืม context หลัง auto-compact โดยเพิ่ม persistent state file, hook inject อัตโนมัติ, และเสริม rule ใน CLAUDE.md ให้แน่นขึ้น

**Architecture:** `.team-state.md` ทำหน้าที่เป็น persistent anchor ที่ `start-team.sh` เขียน pane IDs จริงตอน init และ Lead เขียนอัปเดตตลอด session — `UserPromptSubmit` hook inject ไฟล์นี้เข้า context ทุก turn อัตโนมัติ แม้หลัง compact

**Tech Stack:** Bash, tmux, Claude Code hooks (settings.json), Markdown

---

## File Map

| File | Action | What changes |
|------|--------|--------------|
| `agent-teams/.gitignore` | Modify | เพิ่ม `.team-state.md` (runtime file) |
| `agent-teams/.claude/settings.json` | Modify | เพิ่ม `hooks.UserPromptSubmit` |
| `agent-teams/CLAUDE.md` | Modify | เพิ่ม 4 sections: mandatory read, session recovery, no-code rule, QA→Reviewer pipeline |
| `agent-teams/start-team.sh` | Modify | เพิ่ม RTK detection variable + init `.team-state.md` + update Lead onboarding |

---

## Task 1: Add `.team-state.md` to `.gitignore`

**Files:**
- Modify: `agent-teams/.gitignore`

- [ ] **Step 1: เปิดไฟล์ `.gitignore` และเพิ่ม entry**

เนื้อหาปัจจุบัน:
```
.superpowers/
.claude/projects/
.claude/settings.local.json
projects.json
docs/*
!docs/superpowers/
docs/superpowers/*
!docs/superpowers/specs/
!docs/superpowers/plans/
```

เพิ่ม `.team-state.md` ที่บรรทัดสุดท้าย:
```
.superpowers/
.claude/projects/
.claude/settings.local.json
projects.json
docs/*
!docs/superpowers/
docs/superpowers/*
!docs/superpowers/specs/
!docs/superpowers/plans/
.team-state.md
```

- [ ] **Step 2: Verify**

Run:
```bash
git -C /Users/kriangkrai/project/agent-teams check-ignore -v .team-state.md
```

Expected output: `.gitignore:10:.team-state.md    .team-state.md`

- [ ] **Step 3: Commit**

```bash
git -C /Users/kriangkrai/project/agent-teams add .gitignore
git -C /Users/kriangkrai/project/agent-teams commit -m "chore: ignore .team-state.md runtime file"
```

---

## Task 2: Add UserPromptSubmit Hook to `settings.json`

**Files:**
- Modify: `agent-teams/.claude/settings.json`

- [ ] **Step 1: แก้ไข `settings.json` เพิ่ม hooks block**

เนื้อหาปัจจุบัน:
```json
{
  "autoCompactEnabled": true,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Bash(git *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(pnpm *)",
      "Bash(tmux *)"
    ]
  }
}
```

แก้เป็น:
```json
{
  "autoCompactEnabled": true,
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "allow": [
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "Bash(git *)",
      "Bash(npm *)",
      "Bash(npx *)",
      "Bash(pnpm *)",
      "Bash(tmux *)"
    ]
  },
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .team-state.md ]; then echo '=== TEAM STATE ===' && cat .team-state.md; else echo '[WARNING] .team-state.md not found — run start-team.sh first'; fi"
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 2: Validate JSON syntax**

Run:
```bash
jq . /Users/kriangkrai/project/agent-teams/.claude/settings.json
```

Expected: JSON พิมพ์ออกมาโดยไม่มี error

- [ ] **Step 3: Commit**

```bash
git -C /Users/kriangkrai/project/agent-teams add .claude/settings.json
git -C /Users/kriangkrai/project/agent-teams commit -m "feat(hooks): inject .team-state.md into every Lead turn via UserPromptSubmit"
```

---

## Task 3: Update `CLAUDE.md` — 4 rule changes

**Files:**
- Modify: `agent-teams/CLAUDE.md`

### 3a: เพิ่ม `.team-state.md` ใน mandatory read section

- [ ] **Step 1: แก้ section "การติดตามงาน"**

หา block นี้ใน CLAUDE.md (บรรทัด ~14-22):
```markdown
## การติดตามงาน (บังคับ)

ใช้ **TodoWrite / TodoRead** ของ Claude Code เพื่อติดตามงานทุกชิ้น — ห้ามพึ่งความจำเพียงอย่างเดียว

- **ก่อนตอบ message ทุกข้อ** → TodoRead เพื่อดูงานค้างอยู่ก่อนเสมอ
- **เมื่อ assign งานให้ agent** → TodoWrite บันทึกทันที (format: `[role] task description`)
- **เมื่อ agent report กลับ** → อัพเดต todo เป็น completed ก่อนทำอย่างอื่น
- **ห้ามข้ามงานค้างเพื่อตอบ message ใหม่** — ถ้ามีงาน in_progress ให้ระบุสถานะก่อนรับงานใหม่
```

แก้เป็น:
```markdown
## การติดตามงาน (บังคับ)

ใช้ **TodoWrite / TodoRead** ของ Claude Code เพื่อติดตามงานทุกชิ้น — ห้ามพึ่งความจำเพียงอย่างเดียว

- **ก่อนตอบ message ทุกข้อ** → (1) TodoRead เพื่อดูงานค้างอยู่ (2) อ่าน `.team-state.md` เพื่อดูสถานะ agents และ pipeline stage — hook inject ให้อัตโนมัติแต่ต้องอ่านให้เข้าใจก่อนตอบ
- **เมื่อ assign งานให้ agent** → TodoWrite บันทึกทันที (format: `[role] task description`) + เขียน `.team-state.md` อัปเดต status และ current task
- **เมื่อ agent report กลับ** → อัพเดต todo เป็น completed + เขียน `.team-state.md` อัปเดต status → idle ก่อนทำอย่างอื่น
- **ห้ามข้ามงานค้างเพื่อตอบ message ใหม่** — ถ้ามีงาน in_progress ให้ระบุสถานะก่อนรับงานใหม่
- **เมื่อส่งงานให้ QA** → update pipeline stage ใน `.team-state.md` เป็น `qa`
- **เมื่อ QA PASS และส่งงานให้ Reviewer** → update pipeline stage เป็น `reviewer`
```

### 3b: เพิ่ม section "Session Recovery Protocol" (ใหม่)

- [ ] **Step 2: เพิ่ม section ใหม่หลัง "การติดตามงาน"**

แทรก section ใหม่นี้ต่อจาก block "การติดตามงาน":
```markdown
## Session Recovery Protocol

ถ้า Todo ว่างและไม่แน่ใจสถานะงาน (เช่น หลัง auto-compact) ให้ทำตามลำดับนี้ก่อนทุกอย่าง:

1. อ่าน `.team-state.md` (hook inject ไว้ใน context อยู่แล้ว)
2. Capture pane ทุก active agent เพื่อดูสถานะล่าสุด:
   ```bash
   tmux capture-pane -t <pane_id> -p | tail -20
   ```
3. ประเมินว่ามี agent กำลังทำงานอยู่ไหม
4. ถ้ามี → รอหรือถาม agent นั้นก่อน ห้ามสั่งงานใหม่ทับ
5. ห้ามสรุปเองว่า "งานเสร็จแล้ว" โดยไม่ verify จาก pane capture
```

### 3c: เพิ่มใน section "Lead ห้ามทำงานเอง"

- [ ] **Step 3: เพิ่ม 2 bullet ใน section "Lead ห้ามทำงานเอง"**

หา block นี้ (บรรทัด ~198-201):
```markdown
### Lead ห้ามทำงานเอง
- Lead มีหน้าที่วางแผน ส่งงาน และ collect results เท่านั้น
- ห้ามแก้ไขโค้ดหรือไฟล์เองโดยตรง ให้ delegate ให้ teammate เสมอ
- ถ้าต้องอ่านไฟล์เพื่อเขียน task spec → ทำได้ แต่การแก้ไขต้องส่งให้ agent
```

แก้เป็น:
```markdown
### Lead ห้ามทำงานเอง
- Lead มีหน้าที่วางแผน ส่งงาน และ collect results เท่านั้น
- ห้ามแก้ไขโค้ดหรือไฟล์เองโดยตรง ให้ delegate ให้ teammate เสมอ
- ถ้าต้องอ่านไฟล์เพื่อเขียน task spec → ทำได้ แต่การแก้ไขต้องส่งให้ agent
- **แม้ Todo ว่าง แม้ context หาย แม้ดูเหมือนง่าย → ยังห้ามแก้ไฟล์เอง**
- **ใช้ Pane ID จาก `.team-state.md` เสมอ — ห้ามใช้ numeric index จาก CLAUDE.md โดยตรง** (RTK เลื่อน index +1 บนเครื่องที่ติดตั้ง)
```

### 3d: เพิ่ม section "QA → Reviewer Pipeline"

- [ ] **Step 4: เพิ่ม section ใหม่ต่อจาก "Lead ห้ามทำงานเอง"**

```markdown
### QA → Reviewer Pipeline (sequential เสมอ)
- **ห้าม spawn Reviewer จนกว่า QA จะ report PASS** — ทำงาน sequential เท่านั้น ไม่ใช่ parallel
- Flow: งานเสร็จ → QA → (QA PASS) → Reviewer → (Reviewer approve) → merge
- ถ้า QA FAIL → ส่งกลับ agent ที่รับผิดชอบก่อน ไม่ส่ง Reviewer
```

- [ ] **Step 5: Verify ว่า CLAUDE.md มี 4 sections ครบ**

Run:
```bash
grep -n "Session Recovery\|ห้ามแก้ไฟล์เอง\|Pane ID จาก\|QA → Reviewer Pipeline\|team-state.md" \
  /Users/kriangkrai/project/agent-teams/CLAUDE.md
```

Expected: ได้อย่างน้อย 5 บรรทัดที่ match

- [ ] **Step 6: Commit**

```bash
git -C /Users/kriangkrai/project/agent-teams add CLAUDE.md
git -C /Users/kriangkrai/project/agent-teams commit -m "feat(lead): add session recovery protocol, state file reads, QA→Reviewer sequential rule"
```

---

## Task 4: Update `start-team.sh` — RTK detection + state file init

**Files:**
- Modify: `agent-teams/start-team.sh`

### 4a: เพิ่ม RTK_INSTALLED variable

- [ ] **Step 1: เพิ่ม RTK detection หลัง block `RTK_PANE_CREATED` (บรรทัด ~201-209)**

หา block นี้:
```bash
# 9b. RTK Stats pane (optional — only if rtk is installed)
RTK_PANE_CREATED=false
if command -v rtk >/dev/null 2>&1; then
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' \
    'bash -c "while true; do clear; rtk gain 2>/dev/null; sleep 30; done"')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
  RTK_PANE_CREATED=true
fi
```

แก้เป็น:
```bash
# 9b. RTK Stats pane (optional — only if rtk is installed)
RTK_PANE_CREATED=false
RTK_INSTALLED="no"
if command -v rtk >/dev/null 2>&1; then
  RTK_INSTALLED="yes"
  PANE_RTK=$(tmux split-window -t "$SESSION:0.0" -v -l 30% -c ~ -P -F '#{pane_id}' \
    'bash -c "while true; do clear; rtk gain 2>/dev/null; sleep 30; done"')
  tmux set-option -p -t "$PANE_RTK" @role "RTK Stats"
  tmux set-option -p -t "$PANE_RTK" @role_color "colour46"
  RTK_PANE_CREATED=true
fi
```

### 4b: เพิ่ม state file init หลัง `patch_pane_maps`

- [ ] **Step 2: หา `patch_pane_maps` call (บรรทัด ~263) และเพิ่ม `init_team_state` function + call ต่อจากนั้น**

หา:
```bash
patch_pane_maps
```

แก้เป็น (เพิ่ม function และ call ต่อจาก `patch_pane_maps`):
```bash
patch_pane_maps

# 10b. Initialize .team-state.md with verified pane IDs
init_team_state() {
  local session_ts
  session_ts=$(date '+%Y-%m-%d %H:%M')

  cat > "$SCRIPT_DIR/.team-state.md" <<STATE
# Team State
_Updated: ${session_ts}_
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
```

### 4c: อัปเดต Lead onboarding message

- [ ] **Step 3: หา `inject_lead_context` function และอัปเดต onboarding message**

ใน `inject_lead_context()` หา block ที่สร้าง `msg` (บรรทัดประมาณ 276+) — มีทั้ง RTK และ non-RTK branch

ใน **ทั้งสอง branch** ให้หาบรรทัดที่ขึ้นต้นด้วย `ทีมพร้อมแล้ว — agents รอรับงานใน panes ต่อไปนี้:` และเพิ่ม 2 บรรทัดนี้ต่อท้าย message ก่อน heredoc สิ้นสุด:

```
.team-state.md ถูกสร้างแล้วใน agent-teams/ พร้อม Pane IDs จริง
→ ใช้ Pane ID จาก .team-state.md เสมอ ห้ามใช้ numeric index
→ ตั้งค่า Active Project ใน .team-state.md ก่อนรับงานแรก
```

- [ ] **Step 4: Verify ว่า `start-team.sh` มี `init_team_state` และ `RTK_INSTALLED`**

Run:
```bash
grep -n "RTK_INSTALLED\|init_team_state\|team-state.md" \
  /Users/kriangkrai/project/agent-teams/start-team.sh
```

Expected: ได้อย่างน้อย 4 บรรทัด — RTK_INSTALLED declaration, RTK_INSTALLED="yes", function definition, function call

- [ ] **Step 5: Test run dry**

Run (ไม่ต้อง attach — แค่ verify ว่า script syntax ถูก):
```bash
bash -n /Users/kriangkrai/project/agent-teams/start-team.sh && echo "syntax OK"
```

Expected: `syntax OK`

- [ ] **Step 6: Commit**

```bash
git -C /Users/kriangkrai/project/agent-teams add start-team.sh
git -C /Users/kriangkrai/project/agent-teams commit -m "feat(start-team): init .team-state.md with RTK detection and verified pane IDs"
```

---

## Task 5: Integration Verify

- [ ] **Step 1: ตรวจว่า settings.json hook ถูก format**

Run:
```bash
jq '.hooks.UserPromptSubmit' /Users/kriangkrai/project/agent-teams/.claude/settings.json
```

Expected: array ที่มี hook command อยู่

- [ ] **Step 2: ตรวจว่า `.gitignore` exclude `.team-state.md`**

```bash
echo "test" > /Users/kriangkrai/project/agent-teams/.team-state.md
git -C /Users/kriangkrai/project/agent-teams status --short | grep team-state || echo "correctly ignored"
rm /Users/kriangkrai/project/agent-teams/.team-state.md
```

Expected: `correctly ignored` (ไฟล์ไม่โผล่ใน git status)

- [ ] **Step 3: ตรวจ CLAUDE.md ครบ 4 changes**

```bash
grep -c "Session Recovery\|Pane ID จาก\|QA → Reviewer Pipeline\|team-state.md" \
  /Users/kriangkrai/project/agent-teams/CLAUDE.md
```

Expected: `4` หรือมากกว่า

- [ ] **Step 4: Final commit (ถ้ายังมีไฟล์ที่ยังไม่ได้ commit)**

```bash
git -C /Users/kriangkrai/project/agent-teams status
```

ถ้า clean ก็เสร็จ

---

## Success Criteria

- [ ] `.team-state.md` ถูก gitignore
- [ ] Hook inject state file ทุก turn — ทดสอบโดยส่ง message ใดก็ได้ใน Lead แล้วดูว่า `=== TEAM STATE ===` โผล่ใน system context
- [ ] `start-team.sh` สร้าง `.team-state.md` พร้อม pane IDs จริง
- [ ] CLAUDE.md มี Session Recovery Protocol
- [ ] CLAUDE.md บังคับ QA ก่อน Reviewer
- [ ] Lead ใช้ Pane ID จาก state file แทน numeric index
