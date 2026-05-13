# Multi-Agent V2 Design

**Date:** 2026-05-14
**Branch:** multi-agent-v2

## Overview

Upgrade agent-teams from tmux-IPC-based coordination to Claude Code native multi-agent using `Agent` tool, `TaskCreate/TaskUpdate/TaskList`, and `SendMessage`. tmux panes are retained as log viewers for visibility.

## Goals

- Lead tracks agent state in real-time (pending → in_progress → done/error)
- Error recovery: detect failure, retry or escalate automatically
- Structured task assignment replacing free-text tmux paste
- Sequential peer handoff: agent results flow back to Lead, Lead injects context into next agent

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Lead (dev-team:0.0)               │
│  Agent tool │ TaskCreate │ TaskList │ TaskUpdate       │
└──────┬──────────────────────────────────────────────┘
       │ spawns via Agent tool (parallel if independent)
       ▼
┌──────────────────┐    ┌──────────────────┐
│  frontend agent  │    │  backend agent   │
│  (subagent)      │    │  (subagent)      │
└──────┬───────────┘    └──────┬───────────┘
       │ writes progress        │ writes progress
       ▼                        ▼
  /tmp/agent-logs/         /tmp/agent-logs/
  frontend.log             backend.log
       │                        │
       ▼                        ▼
┌──────────────┐         ┌──────────────┐
│ tmux pane    │         │ tmux pane    │
│ tail -n 200  │         │ tail -n 200  │  (display only)
└──────────────┘         └──────────────┘
```

### 4 Layers

| Layer | Mechanism |
|-------|-----------|
| Orchestration | Lead uses `Agent` tool + `TaskCreate` / `TaskList` |
| Execution | Agents run as Claude Code subagents (not tmux processes) |
| State | `TaskCreate` / `TaskUpdate` / `TaskList` — lifecycle tracking |
| Display | tmux panes run `tail -n 200 -f /tmp/agent-logs/<role>.log` |

## Components

### Files Changed / Created

```
agent-teams/
├── start-team.sh          ← unchanged (legacy mode)
├── start-team-v2.sh       ← new (multi-agent mode)
├── CLAUDE.md              ← updated Lead workflow
└── .claude/agents/
    └── *.md               ← updated (remove tmux comms, add log writing)
```

### start-team-v2.sh

1. Create `/tmp/agent-logs/` and truncate all log files (session-scoped)
2. Create tmux session: Lead pane = Claude Code interactive
3. Agent panes = `tail -n 200 -f /tmp/agent-logs/<role>.log`
4. RTK Stats pane (conditional — same logic as start-team.sh)
5. No auto-trust loop (agents don't run Claude CLI in panes)

### CLAUDE.md (Lead)

- Remove: tmux IPC instructions, pane mapping table for sending tasks
- Add: Agent tool spawn patterns, TaskCreate/TaskList workflow
- Add: task lifecycle management, retry/escalation rules
- Keep: project loading, team roster, session layout reference

### .claude/agents/*.md (all 7 roles)

- Remove: tmux communication section, pane mapping table
- Add: write progress to `/tmp/agent-logs/<role>.log`
- Add: TaskUpdate calls on status change — Lead injects the task ID into spawn context so agent can reference it
- Keep: specialist role definition, working directory injection

## Log Format Standard

```
=== Task: <task-name> [ISO-8601 timestamp] ===
[<role>] <progress message>
[<role>] ✓ <success message>
[<role>] ✗ Error: <error detail>
```

**Session management:** `start-team-v2.sh` truncates all log files on start. Each task writes a `=== Task: ... ===` header to separate runs within a session. tmux panes use `tail -n 200 -f` to show the last 200 lines only.

## Task Lifecycle

```
Lead receives user task
      │
      ▼
TaskCreate per subtask              status: pending
      │
      ▼
Agent tool spawn                    status: in_progress
(parallel if tasks are independent)
      │
      ▼
Agent executes + writes to log
      │
      ├─ success → TaskUpdate(completed) + return result
      └─ error   → TaskUpdate(error) + return error detail
      │
      ▼
Lead: TaskList / TaskGet
      │
      ├─ all done    → summarize, notify user
      └─ has errors  → retry or escalate
```

## Peer Communication

Agents communicate via **sequential handoff** through Lead:

1. Agent A completes → returns structured result to Lead
2. Lead injects Agent A's result as context when spawning Agent B
3. No realtime messaging between concurrent agents

**Rationale:** subagents run in Lead's conversation context. Lead acts as the single source of truth — no shared state required.

## Error Handling

| Case | Handling |
|------|----------|
| Agent returns error | Lead retries once with error context appended |
| Agent times out | Lead calls `TaskStop` + spawns fresh agent |
| Partial failure | Successful subtasks are not re-run — Lead spawns only failed tasks |

## Pane Layout

Same 3-column visual layout as current system:

```
┌────────┬──────────┬──────────┐
│        │ frontend │ designer │
│        ├──────────┼──────────┤
│  Lead  │ backend  │    qa    │
│        ├──────────┼──────────┤
│ [RTK?] │ mobile   │ reviewer │
│        ├──────────┤          │
│        │  devops  │          │
└────────┴──────────┴──────────┘
```

> `[RTK?]` — RTK Stats pane present only if `rtk` is installed (same conditional as start-team.sh)

Agent pane indexes (with RTK installed, Lead pane = 0.0, RTK = 0.1, all agents +1):

| Role | Without RTK | With RTK |
|------|-------------|----------|
| Frontend | 0.1 | 0.2 |
| Backend | 0.2 | 0.3 |
| Mobile | 0.3 | 0.4 |
| DevOps | 0.4 | 0.5 |
| Designer | 0.5 | 0.6 |
| QA | 0.6 | 0.7 |
| Reviewer | 0.7 | 0.8 |

## Out of Scope

- Realtime agent-to-agent messaging while both running concurrently
- Persistent log archive across sessions (logs are session-scoped)
- Web dashboard UI for task monitoring
