# Dev Team Orchestrator

Multi-agent dev team ที่ใช้ Claude Code + tmux — **Lead** หนึ่งตัวคุม **specialist teammates 7 ตัว** ทำงานข้ามโปรเจ็คได้

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

- [tmux](https://github.com/tmux/tmux) 3.1+
- [jq](https://jqlang.github.io/jq/) (`brew install jq`)
- [Claude Code CLI](https://docs.claude.com/en/docs/claude-code) พร้อม login

## Quick start

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

หลัง `start-team.sh` รัน Lead pane จะพร้อมรับคำสั่ง เช่น:

> "เพิ่ม feature login พร้อม API"
>
> "ให้ frontend และ backend ทำ feature X พร้อมกัน"

## Project registry

แก้ [projects.json](projects.json) เพื่อลงทะเบียน project ใหม่:

```json
{
  "active": "hh-app",
  "projects": {
    "myproject": {
      "description": "...",
      "paths": {
        "web": "/absolute/path/to/web",
        "api": "/absolute/path/to/api",
        "mobile": "/absolute/path/to/mobile"
      }
    }
  }
}
```

- `active` = project ที่จะใช้เมื่อเรียก `./start-team.sh` โดยไม่ระบุชื่อ
- `paths` = working directory ของ role ที่เกี่ยวข้อง (key ไม่จำเป็นต้องครบทุก role — script มี fallback)

## File structure

```
agent-teams/
├── CLAUDE.md              # คู่มือการทำงานของ Lead (โหลดอัตโนมัติทุก session)
├── README.md              # ไฟล์นี้
├── projects.json          # registry ของโปรเจ็ค
├── start-team.sh          # spawn tmux session + 8 panes
├── stop-team.sh           # kill session
└── .claude/
    ├── agents/            # agent definitions (7 roles)
    │   ├── frontend.md
    │   ├── backend.md
    │   ├── mobile.md
    │   ├── devops.md
    │   ├── designer.md
    │   ├── qa.md
    │   └── reviewer.md
    └── settings.json      # permissions + hooks
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

## อ่านต่อ

- [CLAUDE.md](CLAUDE.md) — คู่มือการวางแผน, spawn, collect results ของ Lead
- [.claude/agents/](.claude/agents/) — scope + rules ของแต่ละ role
