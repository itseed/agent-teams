# Dev Team Orchestrator

Multi-agent dev team ที่ใช้ Claude Code + tmux — **Lead** หนึ่งตัวคุม **specialist teammates 7 ตัว** ทำงานข้ามโปรเจ็คได้

แทนที่จะสั่งงาน AI ทีละขั้นตอนด้วยตัวเอง คุณแค่บอก Lead ว่าต้องการอะไร — Lead จะวิเคราะห์งาน เลือก role ที่เหมาะสม spawn agent ไปทำงานพร้อมกันหลายตัว แล้วสรุปผลลัพธ์กลับมาให้ เหมือนมีทีม dev คอยรับงานตลอดเวลา

แต่ละ role เป็น Claude Code agent ที่รันใน tmux pane ของตัวเอง มี working directory และ scope ชัดเจน — frontend แก้ UI, backend แก้ API, qa เขียน test, reviewer ตรวจ code ฯลฯ ทำงานแบบ parallel ได้โดยไม่ต้องรอกัน

รองรับหลาย project ในเครื่องเดียวกัน — สลับ context ได้ทันทีโดยระบุชื่อ project ตอน start

## Architecture

```
┌────────┬─────────┬──────────┐
│        │frontend │ designer │
│        ├─────────┼──────────┤
│        │ backend │          │
│        ├─────────┤    qa    │
│  Lead  │ mobile  │          │
│        ├─────────┼──────────┤
│        │         │ reviewer │
│        │ devops  │          │
│        │         │          │
└────────┴─────────┴──────────┘
```

- User สั่งงานผ่าน **Lead** (pane ซ้าย)
- Lead วิเคราะห์งาน → ส่งต่อให้ specialist ผ่าน `tmux paste-buffer`
- Specialist ทำเสร็จ → รายงานกลับ Lead → Lead สรุปให้ user

## How it works

### Orchestration Flow

```mermaid
flowchart TD
    U([👤 User]) -->|พิมพ์คำสั่ง| L[Lead pane\ndev-team:0.0]
    L -->|อ่าน paths| PJ[(projects.json)]
    PJ -->|project paths| L
    L --> A{วิเคราะห์งาน\nต้องใช้ role ไหน?}

    A -->|single role| S1[spawn 1 teammate]
    A -->|หลาย role| S2[spawn parallel teammates]

    S1 -->|tmux paste-buffer| T1[Teammate pane]
    S2 -->|tmux paste-buffer| T2[Teammate A]
    S2 -->|tmux paste-buffer| T3[Teammate B]

    T1 -->|แก้ไขโค้ด / สร้างไฟล์| C1[(Codebase)]
    T2 -->|แก้ไขโค้ด / สร้างไฟล์| C1
    T3 -->|แก้ไขโค้ด / สร้างไฟล์| C1

    T1 -->|report back| L
    T2 -->|report back| L
    T3 -->|report back| L

    L -->|สรุปผลลัพธ์| U
```

---

### Sequence Diagram — Single Agent

```mermaid
sequenceDiagram
    actor User
    participant Lead as Lead pane (0.0)
    participant PJ as projects.json
    participant TM as Teammate pane (0.x)
    participant FS as Codebase

    User->>Lead: พิมพ์คำสั่ง
    Lead->>PJ: อ่าน active project paths
    PJ-->>Lead: { web, api, mobile, ... }
    Lead->>Lead: วิเคราะห์งาน → เลือก role
    Lead->>TM: tmux paste-buffer (prompt + working dir)
    Lead->>TM: tmux send-keys Enter
    TM->>FS: อ่าน / แก้ไขไฟล์
    FS-->>TM: file contents
    TM->>TM: ทำงาน...
    TM->>Lead: tmux send-keys "role เสร็จแล้ว" Enter
    Lead->>Lead: capture-pane → collect results
    Lead->>User: สรุปผลลัพธ์
```

---

### Sequence Diagram — Parallel Agents

```mermaid
sequenceDiagram
    actor User
    participant Lead as Lead pane (0.0)
    participant FE as frontend (0.1)
    participant BE as backend (0.3)
    participant FS as Codebase

    User->>Lead: "ให้ frontend + backend ทำ feature X พร้อมกัน"
    Lead->>FE: paste-buffer (frontend prompt)
    Lead->>BE: paste-buffer (backend prompt)

    par ทำงานพร้อมกัน
        FE->>FS: แก้ไขไฟล์ UI
    and
        BE->>FS: แก้ไขไฟล์ API
    end

    FE->>Lead: "frontend เสร็จแล้ว"
    BE->>Lead: "backend เสร็จแล้ว"
    Lead->>User: สรุปผลจากทั้ง 2 roles
```

## Team roster

| Role | Scope |
|---|---|
| **frontend** | React, Next.js, TypeScript, browser extension |
| **backend** | REST/GraphQL, database, business logic |
| **mobile** | React Native, iOS/Android native modules |
| **devops** | CI/CD, Docker, deployment, env config |
| **designer** | Figma-to-code, design system, UX review, a11y |
| **qa** | Unit/integration/e2e tests, edge cases |
| **reviewer** | Code review, security, performance |

Agent definitions อยู่ใน [.claude/agents/](.claude/agents/)

## Prerequisites

| Requirement | Install |
|---|---|
| [tmux](https://github.com/tmux/tmux) 3.1+ | `brew install tmux` |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` |
| [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) | `npm install -g @anthropic-ai/claude-code` แล้ว `claude login` |

หรือรัน `./install.sh` เพื่อตรวจและติดตั้ง dependencies อัตโนมัติ

## Quick start

```bash
git clone https://github.com/itseed/agent-teams.git
cd agent-teams
./install.sh
```

`install.sh` จะ:
- ตรวจและติดตั้ง dependencies (tmux, jq, Claude CLI)
- สร้าง projects.json จาก example
- ตั้งค่า Snyk (optional)

### หลัง install.sh รัน — แก้ paths ใน projects.json ให้ตรงกับเครื่องของคุณ

`projects.json` ไม่ได้อยู่ใน repo เพราะมี absolute paths ของแต่ละเครื่อง — `install.sh` สร้างไฟล์นี้ให้แล้ว แต่ต้องแก้ paths ให้ตรงกับเครื่องของคุณ:

แก้ `projects.json`:

```json
{
  "active": "myproject",
  "projects": {
    "myproject": {
      "description": "My awesome project",
      "paths": {
        "web": "/absolute/path/to/web",
        "api": "/absolute/path/to/api",
        "mobile": "/absolute/path/to/mobile"
      }
    }
  }
}
```

- `active` = project ที่ใช้เมื่อเรียก `./start-team.sh` โดยไม่ระบุชื่อ
- `paths` = working directory ของ role ที่เกี่ยวข้อง (key ไม่จำเป็นต้องครบ — script มี fallback)

### เริ่ม session

```bash
# เริ่ม session (ใช้ active project จาก projects.json)
./start-team.sh

# เริ่ม session สำหรับ project ที่ระบุ
./start-team.sh pms

# จบ session (ถาม confirm)
./stop-team.sh

# จบทันทีไม่ถาม
./stop-team.sh -f
```

หลัง `start-team.sh` รัน Lead pane จะพร้อมรับคำสั่ง

> **ปิด terminal ไปโดยไม่ได้ตั้งใจ?** รัน `./start-team.sh` อีกครั้ง — script จะถามให้ resume session เดิม agent ที่ทำงานค้างอยู่จะยังอยู่ครบ

## วิธีใช้งาน

### สั่งงานผ่าน Lead

พิมพ์คำสั่งเป็นภาษาธรรมชาติใน Lead pane (ซ้าย):

```
เพิ่ม feature login พร้อม API
```

```
ให้ frontend และ backend ทำ feature X พร้อมกัน
```

```
รีวิว code ใน auth module ให้หน่อย
```

Lead จะวิเคราะห์งาน → เลือก role ที่เหมาะสม → spawn teammate → collect results → สรุปกลับ

### รูปแบบคำสั่ง

| แบบ | ตัวอย่าง | พฤติกรรม |
|---|---|---|
| **Natural language** | "เพิ่ม feature login" | Lead ตัดสินใจเองว่าต้องใช้ role ไหน |
| **ระบุ role ตรงๆ** | "ให้ frontend ทำ X" | Lead spawn ตาม role ที่ระบุเลย |
| **หลาย role พร้อมกัน** | "ให้ frontend + backend ทำ X พร้อมกัน" | Lead spawn parallel |

### ติดตามผล

Teammate รายงานกลับผ่าน Lead pane อัตโนมัติ Lead จะสรุปผลลัพธ์ให้หลังทุก role เสร็จ

ดูสถานะ pane ใด ๆ ได้ตรงๆ:

```bash
tmux capture-pane -t dev-team:0.1 -p | tail -20
```

## File structure

```
agent-teams/
├── CLAUDE.md                  # คู่มือการทำงานของ Lead (โหลดอัตโนมัติทุก session)
├── README.md                  # ไฟล์นี้
├── projects.json.example      # template — copy เป็น projects.json แล้วแก้ paths
├── projects.json              # (gitignored) paths เฉพาะเครื่องของคุณ
├── install.sh                 # one-command setup (ตรวจ deps, สร้าง projects.json, ตั้งค่า Snyk)
├── start-team.sh              # spawn tmux session + 8 panes
├── stop-team.sh               # kill session
└── .claude/
    ├── agents/                # agent definitions (7 roles)
    │   ├── frontend.md
    │   ├── backend.md
    │   ├── mobile.md
    │   ├── devops.md
    │   ├── designer.md
    │   ├── qa.md
    │   └── reviewer.md
    └── settings.json          # permissions + hooks
```

## Pane index mapping

tmux assign pane index ตาม order ของ split — **ไม่เรียงตามตำแหน่งสายตา**:

| Role | Pane |
|---|---|
| Lead | `dev-team:0.0` |
| frontend | `dev-team:0.1` |
| designer | `dev-team:0.2` |
| backend | `dev-team:0.3` |
| mobile | `dev-team:0.4` |
| devops | `dev-team:0.5` |
| qa | `dev-team:0.6` |
| reviewer | `dev-team:0.7` |

Pane title ใช้ tmux user option `@role` (ไม่โดน claude เขียนทับ)

## Customizing agents

แต่ละ role มี agent definition อยู่ใน `.claude/agents/<role>.md` — แก้ได้โดยตรงเพื่อปรับ scope, เพิ่ม constraints, หรือ inject context เฉพาะ project:

```
.claude/agents/
├── frontend.md   # แก้เพื่อเพิ่ม design system, component library ที่ใช้
├── backend.md    # แก้เพื่อระบุ ORM, auth pattern, API convention
├── mobile.md     # แก้เพื่อระบุ RN version, navigation library
├── devops.md     # แก้เพื่อระบุ cloud provider, CI/CD platform
├── designer.md   # แก้เพื่อเพิ่ม Figma link, design token system
├── qa.md         # แก้เพื่อระบุ test framework, coverage target
└── reviewer.md   # แก้เพื่อเพิ่ม coding standards, security checklist
```

การเปลี่ยนแปลงมีผลทันทีในครั้งถัดไปที่ Lead spawn role นั้น ไม่ต้อง restart session

---

## Troubleshooting

### Prompt ค้างใน pane ไม่ submit

สาเหตุ: `paste-buffer` วาง prompt ลงไปแต่ยังไม่กด Enter

```bash
# ตรวจสอบว่า prompt ค้างอยู่ไหม
tmux capture-pane -t dev-team:0.1 -p | tail -5

# ถ้าเห็น prompt ค้างในช่อง input — ส่ง Enter เพิ่ม
tmux send-keys -t dev-team:0.1 Enter

# ถ้ายังไม่ผ่าน ส่ง Escape ก่อนแล้วค่อย Enter
tmux send-keys -t dev-team:0.1 Escape
tmux send-keys -t dev-team:0.1 Enter
```

### Agent ทำงานเสร็จแต่ไม่ report back

```bash
# ดู output ล่าสุดของ pane ที่ต้องการ
tmux capture-pane -t dev-team:0.1 -p | tail -20
```

ถ้าเห็นว่า agent เสร็จแล้ว สามารถ collect results เองได้เลยโดยไม่ต้องรอ

### Session หาย / pane ไม่ตรงกับที่คาด

```bash
# ดู pane ทั้งหมดใน session
tmux list-panes -t dev-team -F "#{pane_index} #{@role}"

# kill แล้ว start ใหม่
./stop-team.sh -f && ./start-team.sh
```

---

## อ่านต่อ

- [CLAUDE.md](CLAUDE.md) — คู่มือการวางแผน, spawn, collect results ของ Lead
- [.claude/agents/](.claude/agents/) — scope + rules ของแต่ละ role
