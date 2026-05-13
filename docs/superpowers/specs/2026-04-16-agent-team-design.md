# Agent Team Design — Software Development Team

**Date:** 2026-04-16
**Status:** Approved

## Overview

A config-driven agent team for software development work spanning web, API, and mobile projects. The user issues all commands through a single Lead; the Lead reads project context, spawns specialist teammates, and coordinates parallel work. Permission prompts from teammates bubble up to the Lead so the user never needs to click into individual panes.

---

## Team Structure

Six specialist roles defined as subagent definitions in `.claude/agents/`:

| Role | Agent File | Responsibilities |
|------|-----------|-----------------|
| **Lead** | _(main session)_ | Reads project registry, spawns teammates, coordinates tasks, surfaces permission prompts |
| **Web Dev** | `web-dev.md` | Frontend — React, Next.js, TypeScript, browser extension |
| **API Dev** | `api-dev.md` | Backend — REST API, GraphQL, database, business logic |
| **Mobile Dev** | `mobile-dev.md` | Mobile — React Native, iOS/Android |
| **QA** | `qa.md` | Tests, edge cases, regression |
| **Code Reviewer** | `reviewer.md` | Code review, standards, improvement suggestions |

### Work Flow

```
User → Lead → [web-dev, api-dev, mobile-dev] (parallel)
                        ↓ done
               [qa, reviewer] (parallel)
                        ↓ done
               Lead synthesizes → User
```

The Lead decides which teammates to spawn based on the task. If the user specifies teammates explicitly (e.g., "ให้ web-dev และ api-dev ทำ..."), the Lead follows that instruction directly.

---

## Project Registry

**`projects.json`** at the repo root. The Lead reads this on every task to resolve project paths before spawning teammates.

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

- Change `active` to switch default project
- Reference a project explicitly: "ใน project fuse ช่วย..."
- Add new projects by appending to the `projects` object

---

## File Layout

```
/Users/kriangkrai/project/agent-teams/
├── .claude/
│   ├── settings.json          ← agent teams enabled + pre-approved permissions
│   └── agents/
│       ├── web-dev.md
│       ├── api-dev.md
│       ├── mobile-dev.md
│       ├── qa.md
│       └── reviewer.md
├── projects.json              ← project path registry
├── CLAUDE.md                  ← Lead instructions
└── docs/superpowers/specs/
    └── 2026-04-16-agent-team-design.md
```

---

## CLAUDE.md (Lead Instructions)

The Lead's CLAUDE.md instructs it to:

1. Read `projects.json` at the start of every task
2. Use `active` project if none specified; otherwise use the named project
3. Spawn teammates by referencing agent definitions in `.claude/agents/`
4. Inject the correct working directory path when spawning each teammate
5. Coordinate via the shared task list
6. Surface permission prompts to the user without requiring pane clicks

---

## Subagent Definitions

Each file in `.claude/agents/` defines a role. The Lead references these by name when spawning. Example structure:

```markdown
---
description: <one-line role description>
---
<Role persona and responsibilities>
Working directory will be injected by the Lead at spawn time.
Claim tasks from the shared task list and notify the Lead when done.
```

The definition body is appended to the teammate's system prompt. Team coordination tools (`SendMessage`, task tools) are always available regardless of any `tools` restriction.

---

## Display Mode & Mouse

**`~/.tmux.conf`:**
```bash
set -g mouse on
```

This enables click and scroll in all panes permanently — no per-session setup needed.

**`~/.claude.json`:**
```json
{
  "teammateMode": "tmux"
}
```

This forces split-pane mode. Each teammate gets its own pane. Layout: Lead on the left (50% width), teammates stacked on the right.

---

## Permissions

**`.claude/settings.json`:**
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

Operations not on the allow list prompt for approval. Those prompts bubble up to the Lead automatically — the user answers from the Lead pane only.

---

## Usage

### Starting the team

```bash
cd /Users/kriangkrai/project/agent-teams
claude
```

tmux split panes open automatically when Claude spawns teammates.

### Commanding the Lead

Natural language — Lead decides who does what:
```
เพิ่ม feature login ใน pms พร้อม API รองรับ
```

Explicit teammates — Lead follows directly:
```
ให้ web-dev และ api-dev ทำ feature login พร้อมกัน
```

Switch project:
```
ใน project fuse ช่วย refactor authentication module
```

### Navigating panes

- **Click** into any pane to interact directly with that teammate
- **Shift+Down** to cycle through teammates from keyboard
- **Scroll** anywhere with mouse

### Shutting down

```
Clean up the team
```

---

## Constraints & Known Limitations

- No session resumption with in-process teammates (`/resume` won't restore teammates)
- Task status can lag — tell the Lead to nudge a teammate if a task appears stuck
- One team per session — clean up before starting a new team
- Teammates cannot spawn sub-teams
- Split-pane mode requires tmux to be running before Claude starts
