# Office Floor Dashboard (live v1 state) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ให้ `dashboard/office-floor.html` แสดงสถานะจริงของทีม v1 (`dev-team`) ผ่าน Python server ที่อ่าน `.team-state.md`, `/tmp/agent-status/*.md` และ tmux

**Architecture:** `dashboard/state.py` (pure parse/derive + tmux adapter ที่ inject ได้) → `dashboard/server.py` (stdlib HTTP, `/` + `/api/state`, 127.0.0.1) → หน้าเว็บ poll ทุก 2s แล้ว map สถานะเป็นตำแหน่ง/ท่าทางตัวละคร; `start-team.sh`/`stop-team.sh` เปิด/ปิด server ผ่าน helper ใน `scripts/lib/common.sh`

**Tech Stack:** Python 3.8+ stdlib (`http.server`, `unittest`, `subprocess`), bash, three.js r128 (CDN เดิม)

**Spec:** `docs/superpowers/specs/2026-10-13-office-dashboard-live-design.md`

## Global Constraints

- v1 เท่านั้น — session `dev-team`; ไม่แตะ v2
- Python stdlib only, python3 ≥ 3.8; ไม่มี dependency ใหม่
- server bind `127.0.0.1` เท่านั้น, read-only (มีแค่ GET `/`, `/index.html`, `/api/state`)
- port default `4780`, override ด้วย `DASHBOARD_PORT`
- pid file `/tmp/agent-teams-dashboard.pid`, log `/tmp/agent-teams-dashboard.log`
- poll interval 2s; evidence ตัดที่ 600 ตัวอักษร; feed เก็บ 50 รายการ
- ทุก failure ของ dashboard ต้องไม่ทำให้ `start-team.sh` / `stop-team.sh` ล้ม
- ข้อความจาก API ใส่ DOM ผ่าน escape เท่านั้น
- ระหว่างพัฒนา/ทดสอบ: ห้ามแตะ tmux session `dev-team`, `.team-state.md` จริง, `/tmp/agent-status` จริง (ใช้ temp dir + fake adapter)

## Review Focus

1. Status file ค้างจาก session ก่อน (mtime < session_created) — ต้องไม่ทำให้ role ขึ้น working/blocked → test ใน Task 2
2. `.team-state.md` ถูก Lead แก้มือจนแถวเพี้ยน (คอลัมน์ขาด / มี `|` เกิน) — ต้องไม่ทำให้ทั้ง response พัง → test ใน Task 1
3. Session ไม่รัน / ไม่มี `.team-state.md` / ไม่มี `/tmp/agent-status` — ยังตอบ 200 `running:false` → test ใน Task 2 + smoke ใน Task 3
4. task/blocker ที่มี HTML (`<img onerror>`) — ต้องแสดงเป็นข้อความ → browser check ใน Task 5
5. Port ถูกใช้อยู่ / python3 ไม่มี — start-team ยังเริ่มทีมได้ → shell test ใน Task 4

---

### Task 1: Parsers (`dashboard/state.py` part 1)

**Files:**
- Create: `dashboard/state.py`
- Test: `dashboard/test_state.py`

**Interfaces:**
- Produces:
  - `ROLES: list[str]` — 8 roles ตามลำดับ frontend, backend, mobile, devops, designer, architect, qa, reviewer
  - `parse_team_state(text: str) -> dict` → `{"updated": str|None, "project": str|None, "stage": str|None, "recent": list[str], "rows": {role: {"pane": str, "status": str, "task": str|None}}}`
  - `parse_status_file(text: str) -> dict` → `{"status": str|None, "task": str|None, "blocker": str|None, "evidence": str|None}`

- [ ] **Step 1: Write failing tests** — `TeamStateParseTest` (full file, placeholder project `[Lead ...]` → None, `(ยังไม่มี)` → `[]`, recent bullets stripped, task `—` → None, malformed row skipped while others kept, unknown role ignored, empty text → all None/empty) and `StatusFileParseTest` (working, done+evidence truncated to 600 + `…`, blocked+blocker, garbage text → all None)
- [ ] **Step 2: Run** `python3 -m unittest dashboard/test_state.py -v` → FAIL (ImportError)
- [ ] **Step 3: Implement** parsers: split by `## ` headings; table rows = lines starting with `|`, cells = `line.strip().strip('|').split('|')` stripped; need ≥ 4 cells, cell[0] in ROLES; status file header = `key: value` lines before first blank/`## `; evidence = text after `## Verification evidence`
- [ ] **Step 4: Run tests** → PASS
- [ ] **Step 5: Commit** `feat(dashboard): parse team-state and agent status files`

### Task 2: Derivation + build_state (`dashboard/state.py` part 2)

**Files:**
- Modify: `dashboard/state.py`
- Test: `dashboard/test_state.py`

**Interfaces:**
- Consumes: Task 1 parsers, `ROLES`
- Produces:
  - `SHELLS = {"zsh","bash","sh","fish","dash"}` (compare after `lstrip("-")`)
  - `derive_status(row: dict|None, pane: dict|None, fs: dict|None) -> str` — rules 1,2,4–7 of spec §4 (`fs` already filtered for staleness by caller)
  - `class TmuxAdapter` with `session(name) -> dict|None` (`{"created": int, "panes": {pane_id: {"cmd","path","workdir","role"}}}`) and `branch(workdir, path) -> str|None`
  - `build_state(state_file: str, status_dir: str, session: str, tmux) -> dict` — JSON shape of spec §3

- [ ] **Step 1: Write failing tests** — `DeriveStatusTest` (one test per rule incl. shell `-zsh`, done+ts working → done, done+ts idle → idle, no fs → ts status) and `BuildStateTest` with `FakeTmux` + temp dir: session not running (spawned → offline, others absent, lead offline, running false), full team mix, stale status file ignored (mtime set via `os.utime` before `created`), missing state file → running false + all absent, lead found by `@role == "Lead"`, evidence/branch passthrough, agents order = lead + ROLES
- [ ] **Step 2: Run** → FAIL
- [ ] **Step 3: Implement** `derive_status`, `TmuxAdapter` (`tmux display -p -t =<s> '#{session_created}'`, `tmux list-panes -s -t =<s> -F '#{pane_id}\t#{pane_current_command}\t#{pane_current_path}\t#{@workdir}\t#{@role}'`, timeout 2s, any error → None; branch via `scripts/pane-branch.sh`), `build_state` (per-role try/except → `error`)
- [ ] **Step 4: Run tests** → PASS
- [ ] **Step 5: Commit** `feat(dashboard): derive live agent status from team state, status files and tmux`

### Task 3: HTTP server (`dashboard/server.py`)

**Files:**
- Create: `dashboard/server.py`
- Test: `dashboard/test_state.py` (`ServerTest` — starts server on port 0 in a thread with FakeTmux injected)

**Interfaces:**
- Consumes: `build_state`, `TmuxAdapter`
- Produces: CLI `python3 dashboard/server.py [--port N] [--state-file P] [--status-dir D] [--session S]`; `make_server(port, state_file, status_dir, session, tmux) -> ThreadingHTTPServer`

- [ ] **Step 1: Write failing test** — GET `/api/state` → 200 JSON with `agents` len 9 + `Cache-Control: no-store`; GET `/` → 200 `text/html`; GET `/etc/passwd` and `/../state.py` → 404; POST `/api/state` → 405/501
- [ ] **Step 2: Run** → FAIL
- [ ] **Step 3: Implement** handler (quiet `log_message`, build_state exception → 500 JSON `{"error": ...}`), argparse, bind `127.0.0.1`, port in use → stderr message + exit 1
- [ ] **Step 4: Run tests** → PASS; smoke: run CLI with temp `--state-file`/`--status-dir`/`--session agent-teams-nonexistent`, `curl -s 127.0.0.1:<port>/api/state | python3 -m json.tool`
- [ ] **Step 5: Commit** `feat(dashboard): local read-only HTTP server for live state`

### Task 4: Lifecycle wiring (shell)

**Files:**
- Modify: `scripts/lib/common.sh` (replace `open_dashboard` with `_open_url`, `start_dashboard`, `stop_dashboard`)
- Modify: `start-team.sh` (2 call sites → `start_dashboard`)
- Modify: `stop-team.sh` (call `stop_dashboard`)
- Modify: `README.md` (dashboard section)

**Interfaces:**
- Consumes: `dashboard/server.py` CLI
- Produces: `start_dashboard` / `stop_dashboard` (no args; env `DASHBOARD_PORT`; always return 0)

- [ ] **Step 1: Implement** per spec §6 (reuse server if pid alive + `/api/state` answers; wait ≤3s via `curl -sf` loop or python urllib fallback; open via open/wslview/xdg-open)
- [ ] **Step 2: Verify** `bash -n`, shellcheck (no new warnings); in a subshell with `DASHBOARD_PORT=4799`: `start_dashboard` (browser open stubbed via `DASHBOARD_NO_BROWSER=1`) → curl OK → `start_dashboard` again reuses same pid → `stop_dashboard` → port closed; python3 missing simulated with `PATH` stripped → warning + return 0; port occupied by another listener → warning + return 0
- [ ] **Step 3: Commit** `feat(dashboard): start/stop live dashboard server with the team`

### Task 5: Frontend rewrite (`dashboard/office-floor.html`)

**Files:**
- Modify: `dashboard/office-floor.html`

**Interfaces:**
- Consumes: `GET /api/state` (spec §3)

- [ ] **Step 1: Rewrite** per spec §5 — keep scene/furniture/person builders, walking, camera, CSS; new ROOMS (lead, dev, design, qa, lounge), one desk per role, lounge idle spots ≥ 8, done spots in Lead Office, role colors, per-agent HTML labels (role + status + short task / ⚠ / ✓ / offline), blocked room highlight, KPIs, feed diff, pipeline panel, detail panel, Live/disconnected, not-running overlay, `esc()` for all API text; remove all random data
- [ ] **Step 2: Verify in Chrome** against server with temp state (Task 3 CLI): no console errors; mutate temp status files (working → done → idle, blocked, kill pane simulated via FakeTmux not possible in CLI → use `--session` nonexistent for offline overlay); feed lines appear; XSS task string renders as text; stop server → "ขาดการเชื่อมต่อ"
- [ ] **Step 3: Commit** `feat(dashboard): render live agent team in Office Floor`

### Task 6: Final verification

- [ ] `python3 -m unittest dashboard/test_state.py -v` all pass
- [ ] `bash -n start-team.sh stop-team.sh scripts/lib/common.sh` + shellcheck no new warnings
- [ ] Review full branch diff vs `main`; no push
