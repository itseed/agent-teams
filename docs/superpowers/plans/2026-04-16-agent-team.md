# Agent Team Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ตั้งค่า Claude Code Agent Team สำหรับ software development ที่มี Lead 1 คน + specialists 5 คน (web-dev, api-dev, mobile-dev, qa, reviewer) พร้อม project path registry และ tmux split-pane พร้อม mouse support

**Architecture:** Lead อ่าน `projects.json` เพื่อรู้ paths ของแต่ละโปรเจ็ค แล้ว spawn teammates โดยอ้างอิง subagent definitions ใน `.claude/agents/` พร้อม inject working directory ที่ถูกต้อง teammates รันใน tmux split panes และ permission prompts bubble up มาที่ Lead อัตโนมัติ

**Tech Stack:** Claude Code Agent Teams (experimental), tmux, JSON

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `~/.tmux.conf` | tmux global config — mouse support ถาวร |
| Modify | `~/.claude.json` | เพิ่ม `teammateMode: "tmux"` |
| Modify | `.claude/settings.json` | เพิ่ม pre-approved permissions |
| Create | `projects.json` | project path registry |
| Create | `CLAUDE.md` | คำสั่งสำหรับ Lead |
| Create | `.claude/agents/web-dev.md` | subagent definition: frontend |
| Create | `.claude/agents/api-dev.md` | subagent definition: backend/API |
| Create | `.claude/agents/mobile-dev.md` | subagent definition: mobile |
| Create | `.claude/agents/qa.md` | subagent definition: QA/testing |
| Create | `.claude/agents/reviewer.md` | subagent definition: code review |

---

## Task 1: ตั้งค่า tmux mouse support แบบถาวร

**Files:**
- Create: `~/.tmux.conf`

- [ ] **Step 1: สร้างไฟล์ `~/.tmux.conf`**

```bash
cat > ~/.tmux.conf << 'EOF'
set -g mouse on
EOF
```

- [ ] **Step 2: ตรวจสอบไฟล์ถูกสร้าง**

```bash
cat ~/.tmux.conf
```

Expected output:
```
set -g mouse on
```

- [ ] **Step 3: Reload tmux config (ถ้ามี session ที่รันอยู่)**

```bash
tmux source-file ~/.tmux.conf 2>/dev/null && echo "reloaded" || echo "no active session, config will apply on next start"
```

---

## Task 2: ตั้งค่า teammateMode ใน `~/.claude.json`

**Files:**
- Modify: `~/.claude.json`

> `~/.claude.json` มีข้อมูล runtime อื่นๆ อยู่แล้ว — ให้เพิ่มเฉพาะ key `teammateMode` เท่านั้น

- [ ] **Step 1: เพิ่ม `teammateMode` ด้วย Python (safe JSON merge)**

```bash
python3 - << 'EOF'
import json, sys

path = __import__('os').path.expanduser('~/.claude.json')
with open(path, 'r') as f:
    data = json.load(f)

data['teammateMode'] = 'tmux'

with open(path, 'w') as f:
    json.dump(data, f, indent=2)

print("Done — teammateMode set to tmux")
EOF
```

- [ ] **Step 2: ตรวจสอบ**

```bash
python3 -c "import json; d=json.load(open(__import__('os').path.expanduser('~/.claude.json'))); print(d.get('teammateMode'))"
```

Expected output:
```
tmux
```

---

## Task 3: อัปเดต `.claude/settings.json` — pre-approve permissions

**Files:**
- Modify: `.claude/settings.json`

- [ ] **Step 1: เขียนทับ `.claude/settings.json` ด้วย config ใหม่**

```json
{
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
      "Bash(pnpm *)"
    ]
  }
}
```

บันทึกเป็น `/Users/kriangkrai/project/agent-teams/.claude/settings.json`

- [ ] **Step 2: ตรวจสอบ JSON valid**

```bash
python3 -m json.tool /Users/kriangkrai/project/agent-teams/.claude/settings.json > /dev/null && echo "JSON valid"
```

Expected output:
```
JSON valid
```

---

## Task 4: สร้าง `projects.json` — project path registry

**Files:**
- Create: `projects.json`

- [ ] **Step 1: สร้างไฟล์ `projects.json`**

```json
{
  "active": "pms",
  "projects": {
    "pms": {
      "description": "Project Management System",
      "paths": {
        "web": "/Users/kriangkrai/project/pms-web",
        "extension": "/Users/kriangkrai/project/pms-extension",
        "api": "/Users/kriangkrai/project/pms-web"
      }
    },
    "fuse": {
      "description": "Fuse Platform",
      "paths": {
        "web": "/Users/kriangkrai/project/fuse-platform/fuse-web",
        "api": "/Users/kriangkrai/project/fuse-platform"
      }
    }
  }
}
```

บันทึกเป็น `/Users/kriangkrai/project/agent-teams/projects.json`

- [ ] **Step 2: ตรวจสอบ JSON valid และ paths มีอยู่จริง**

```bash
python3 - << 'EOF'
import json, os

with open('/Users/kriangkrai/project/agent-teams/projects.json') as f:
    cfg = json.load(f)

for proj, data in cfg['projects'].items():
    for role, path in data['paths'].items():
        exists = os.path.isdir(path)
        print(f"{'OK' if exists else 'MISSING'} [{proj}/{role}] {path}")
EOF
```

Expected: ทุก path ขึ้น `OK` — ถ้ามี `MISSING` ให้แก้ path ในไฟล์ให้ถูกต้อง

- [ ] **Step 3: Commit**

```bash
cd /Users/kriangkrai/project/agent-teams
git init 2>/dev/null || true
git add projects.json
git commit -m "feat: add project path registry"
```

---

## Task 5: สร้าง `CLAUDE.md` — Lead instructions

**Files:**
- Create: `CLAUDE.md`

- [ ] **Step 1: สร้างไฟล์ `CLAUDE.md`**

```markdown
# Dev Team Lead

คุณเป็น Lead ของ software development team ที่มี specialist teammates:
- **web-dev** — Frontend (React, Next.js, TypeScript, browser extension)
- **api-dev** — Backend (REST API, GraphQL, database, business logic)
- **mobile-dev** — Mobile (React Native, iOS/Android)
- **qa** — Testing (unit, integration, e2e, edge cases)
- **reviewer** — Code review (standards, security, performance)

## เมื่อรับงานใหม่

1. อ่านไฟล์ `projects.json` เสมอ
2. ระบุ active project (ใช้ field `active` ถ้าผู้ใช้ไม่ระบุ หรือใช้ชื่อ project ที่ผู้ใช้พูดถึง)
3. ดึง paths ของ project นั้นออกมา
4. วิเคราะห์งานว่าต้องใช้ teammate คนไหน

## วิธี spawn teammates

Spawn ด้วย subagent definition ที่มีใน `.claude/agents/` และ inject working directory:

ตัวอย่าง: "Spawn a web-dev teammate to work on the login feature. Their working directory is /Users/kriangkrai/project/pms-web"

## รับคำสั่งได้ 2 แบบ

**แบบ 1 — Natural language (Lead ตัดสินใจเอง):**
"เพิ่ม feature login ใน pms พร้อม API รองรับ"
→ Lead spawn web-dev (path: pms/web) + api-dev (path: pms/api) พร้อมกัน

**แบบ 2 — ระบุ teammate ตรงๆ:**
"ให้ web-dev และ api-dev ทำ feature login พร้อมกัน"
→ Lead spawn ตามที่สั่งเลย

## Permission prompts

ถ้า teammate ถามสิ่งที่ไม่ได้ pre-approve ไว้ permission request จะถูก bubble up มาที่คุณ (Lead) ผู้ใช้จะตอบผ่านช่องทางนี้เท่านั้น ไม่ต้องให้ผู้ใช้คลิกเข้าไปใน pane ของ teammate

## การใช้ task list

สร้าง task สำหรับแต่ละหน่วยงานที่ชัดเจน (1 task = 1 deliverable เช่น "implement login form component")
ให้ teammate self-claim task ได้ถ้า Lead ไม่ assign ตรงๆ

## เมื่องานเสร็จ

สรุปผลลัพธ์จากทุก teammate แล้วแจ้งผู้ใช้ก่อน cleanup
```

บันทึกเป็น `/Users/kriangkrai/project/agent-teams/CLAUDE.md`

- [ ] **Step 2: Commit**

```bash
cd /Users/kriangkrai/project/agent-teams
git add CLAUDE.md
git commit -m "feat: add Lead instructions in CLAUDE.md"
```

---

## Task 6: สร้าง subagent definitions

**Files:**
- Create: `.claude/agents/web-dev.md`
- Create: `.claude/agents/api-dev.md`
- Create: `.claude/agents/mobile-dev.md`
- Create: `.claude/agents/qa.md`
- Create: `.claude/agents/reviewer.md`

- [ ] **Step 1: สร้าง directory**

```bash
mkdir -p /Users/kriangkrai/project/agent-teams/.claude/agents
```

- [ ] **Step 2: สร้าง `web-dev.md`**

```markdown
---
description: Frontend developer — React, Next.js, TypeScript, browser extension
---

คุณเป็น frontend developer ที่เชี่ยวชาญ:
- React, Next.js, TypeScript
- Browser extension (Chrome/Firefox)
- CSS, Tailwind, UI components
- Client-side state management

Working directory ของคุณจะถูก inject โดย Lead ตอน spawn

## วิธีทำงาน
1. อ่าน task จาก shared task list
2. ทำงานใน working directory ที่ Lead กำหนด
3. เขียน code พร้อม tests
4. Mark task complete และ notify Lead เมื่อเสร็จ
5. ถ้าต้องการ input จาก api-dev ให้ message โดยตรง
```

- [ ] **Step 3: สร้าง `api-dev.md`**

```markdown
---
description: Backend developer — REST API, GraphQL, database, business logic
---

คุณเป็น backend developer ที่เชี่ยวชาญ:
- REST API, GraphQL
- Database design และ queries (SQL, NoSQL)
- Business logic, authentication, authorization
- Server-side validation

Working directory ของคุณจะถูก inject โดย Lead ตอน spawn

## วิธีทำงาน
1. อ่าน task จาก shared task list
2. ทำงานใน working directory ที่ Lead กำหนด
3. เขียน API endpoints พร้อม tests
4. Document API contracts เพื่อให้ web-dev และ mobile-dev ใช้ได้
5. Mark task complete และ notify Lead เมื่อเสร็จ
```

- [ ] **Step 4: สร้าง `mobile-dev.md`**

```markdown
---
description: Mobile developer — React Native, iOS, Android
---

คุณเป็น mobile developer ที่เชี่ยวชาญ:
- React Native
- iOS (Swift) และ Android (Kotlin) native modules
- Mobile UX patterns
- Push notifications, deep links, offline support

Working directory ของคุณจะถูก inject โดย Lead ตอน spawn

## วิธีทำงาน
1. อ่าน task จาก shared task list
2. ทำงานใน working directory ที่ Lead กำหนด
3. เขียน code พร้อม tests
4. ประสานกับ api-dev เรื่อง API contracts ถ้าจำเป็น
5. Mark task complete และ notify Lead เมื่อเสร็จ
```

- [ ] **Step 5: สร้าง `qa.md`**

```markdown
---
description: QA engineer — unit tests, integration tests, edge cases, regression
---

คุณเป็น QA engineer ที่เชี่ยวชาญ:
- Unit testing, integration testing, e2e testing
- Edge case identification
- Regression testing
- Test coverage analysis

Working directory ของคุณจะถูก inject โดย Lead ตอน spawn

## วิธีทำงาน
1. อ่าน task จาก shared task list
2. ทำงานใน working directory ที่ Lead กำหนด
3. เขียน test สำหรับ feature ที่ teammate คนอื่นทำเสร็จแล้ว
4. รายงาน bugs หรือ edge cases ที่พบให้ Lead ทราบ
5. Mark task complete และ notify Lead เมื่อเสร็จ
```

- [ ] **Step 6: สร้าง `reviewer.md`**

```markdown
---
description: Code reviewer — code quality, security, performance, standards
---

คุณเป็น code reviewer ที่เชี่ยวชาญ:
- Code quality และ readability
- Security vulnerabilities (OWASP Top 10)
- Performance issues
- Coding standards และ best practices
- Architecture consistency

Working directory ของคุณจะถูก inject โดย Lead ตอน spawn

## วิธีทำงาน
1. อ่าน task จาก shared task list
2. Review code ที่ teammate คนอื่นทำเสร็จแล้ว
3. ให้ feedback ที่ actionable พร้อม suggested fixes
4. ถ้าพบ security issue ให้ flag ทันทีด้วย message ถึง Lead
5. Mark task complete และ notify Lead เมื่อเสร็จ
```

- [ ] **Step 7: ตรวจสอบไฟล์ครบ**

```bash
ls -la /Users/kriangkrai/project/agent-teams/.claude/agents/
```

Expected output — ต้องเห็น 5 ไฟล์:
```
web-dev.md
api-dev.md
mobile-dev.md
qa.md
reviewer.md
```

- [ ] **Step 8: Commit**

```bash
cd /Users/kriangkrai/project/agent-teams
git add .claude/agents/ .claude/settings.json
git commit -m "feat: add subagent definitions and permissions config"
```

---

## Task 7: Smoke test

- [ ] **Step 1: ตรวจสอบ tmux version (ต้อง >= 2.1)**

```bash
tmux -V
```

Expected: `tmux 3.x` หรือสูงกว่า

- [ ] **Step 2: ตรวจสอบ Claude Code version (ต้อง >= 2.1.32)**

```bash
claude --version
```

Expected: version 2.1.32 หรือสูงกว่า

- [ ] **Step 3: เปิด tmux session ใหม่**

```bash
tmux new-session -s dev-team -d
tmux attach -t dev-team
```

- [ ] **Step 4: ใน tmux session รัน Claude และทดสอบ team**

```
cd /Users/kriangkrai/project/agent-teams
claude
```

แล้วพิมพ์คำสั่งนี้ใน Lead:
```
อ่าน projects.json แล้วบอกฉันว่ามี project อะไรบ้าง และ paths ของแต่ละ project อยู่ที่ไหน
```

Expected: Lead ตอบรายละเอียด project ถูกต้อง

- [ ] **Step 5: ทดสอบ spawn teammates**

```
สร้าง agent team เล็กๆ โดย spawn web-dev 1 คนและให้เขาบอกว่า working directory ของเขาคืออะไร (ใช้ project pms)
```

Expected: tmux แสดง pane ใหม่สำหรับ web-dev ทางขวา และ web-dev ตอบว่า working directory คือ `/Users/kriangkrai/project/pms-web`

- [ ] **Step 6: ทดสอบ mouse support**

คลิก scroll ใน pane ต่างๆ — ต้องใช้งานได้โดยไม่ต้องตั้งค่าอะไรเพิ่ม

- [ ] **Step 7: Cleanup**

```
Clean up the team
```

แล้ว exit Claude:
```
/exit
```
