# Office Floor Dashboard — live team state (v1)

_Date: 2026-10-13 · Branch: `feat/office-dashboard` · Status: design approved in chat, awaiting spec review_

## 1. Goal

หน้าเว็บ 3D "virtual office" (`dashboard/office-floor.html`) ปัจจุบันแสดงข้อมูลสุ่มทั้งหมด (`Math.random()`)
เปลี่ยนให้แสดง **สถานะจริงของ agent team v1** (session `dev-team`) โดย:

- **Primary — monitor**: เปิดค้างข้างจอแล้วรู้ทันทีว่าใคร working / idle / done / blocked / offline, task อะไร, pipeline stage ไหน — ความถูกต้องสำคัญกว่าความสวย
- **Secondary — showcase**: ภาพเคลื่อนไหวยังสวยพอให้คนอื่นดู แต่ทุกอย่างที่แสดงต้องมาจากข้อมูลจริง

### Scope

- In: v1 เท่านั้น (`start-team.sh`, session `dev-team`, `.team-state.md`, `/tmp/agent-status/<role>.md`, tmux)
- Out: v2 (`start-team-v2.sh`, `/tmp/agent-logs`), การสั่งงาน agent จากหน้าเว็บ (read-only), auth, เข้าถึงจากเครื่องอื่น, persist feed ข้าม reload

## 2. Architecture

```
start-team.sh ──(y/N, --dashboard)──▶ start_dashboard (common.sh)
                                          │ nohup python3 dashboard/server.py  (127.0.0.1:$DASHBOARD_PORT, default 4780)
                                          ▼
browser ──GET / ───────────────▶ server.py ──▶ dashboard/office-floor.html
        ──GET /api/state (2s) ─▶ server.py ──▶ state.py: build_state()
                                                   ├─ read  .team-state.md
                                                   ├─ read  /tmp/agent-status/*.md (+ mtime)
                                                   ├─ run   tmux list-panes / display  (timeout 2s)
                                                   └─ run   scripts/pane-branch.sh
stop-team.sh ──▶ stop_dashboard (common.sh) ──▶ kill pid from /tmp/agent-teams-dashboard.pid
```

### Files

| ไฟล์ | หน้าที่ |
|---|---|
| `dashboard/server.py` | `http.server` (stdlib) — `GET /` → html, `GET /api/state` → JSON, อื่นๆ 404; bind `127.0.0.1` เท่านั้น; ไม่มี endpoint เขียน |
| `dashboard/state.py` | pure functions: parse team-state, parse status file, derive status, build state; tmux/branch access รวมใน adapter ที่ inject ได้ (mock ใน test) |
| `dashboard/test_state.py` | `unittest` (stdlib) — parser + derivation rules + build_state ด้วย fixture/mock |
| `dashboard/office-floor.html` | หน้าเว็บ (ปรับจากไฟล์เดิม) |
| `scripts/lib/common.sh` | `ask_dashboard` (มีแล้ว), `start_dashboard`, `stop_dashboard` (แทน `open_dashboard`) |
| `start-team.sh` | เรียก `start_dashboard` แทน `open_dashboard` |
| `stop-team.sh` | เรียก `stop_dashboard` |
| `README.md` | วิธีใช้ dashboard |

Python: stdlib only, รองรับ python3 ≥ 3.8 (ไม่มี dependency ใหม่)

## 3. Data contract — `GET /api/state`

```json
{
  "session": {"name": "dev-team", "running": true, "created": 1760330000},
  "project": "pms",
  "stage": "qa — login",
  "updated": "2026-10-13 10:42",
  "recent": ["backend: /auth/login ✓"],
  "agents": [
    {
      "role": "backend",
      "pane": "%3",
      "spawned": true,
      "alive": true,
      "status": "working",
      "task": "implement /auth/login",
      "blocker": null,
      "evidence": null,
      "since": 1760331234,
      "branch": "feature/login",
      "error": null
    }
  ],
  "serverTime": 1760331300
}
```

- `agents` เรียงลำดับคงที่: `lead`, frontend, backend, mobile, devops, designer, architect, qa, reviewer (ครบ 9 เสมอ — role ที่ไม่ได้ spawn มี `status: "absent"`)
- `status` ∈ `working | idle | done | blocked | offline | absent`
- `lead`: pane = `dev-team:0.0`; status = `offline` ถ้า pane ตาย; ไม่งั้น `working` เมื่อมี role ใด working/blocked/done (task = pipeline stage) หรือ `idle` (task = `null`) — Lead ไม่มี status file
- `project`: ค่าใต้ `## Active Project`; ถ้าเป็น placeholder ที่ขึ้นต้นด้วย `[` → ใช้ `--project` ที่ `start-team.sh` ส่งให้ server (project ที่ใช้เริ่มทีม) → ไม่มีทั้งคู่ = `null`
- `recent`: บรรทัดที่ไม่ว่างใต้ `## Recently Completed` (ตัด `- ` นำหน้า); placeholder `(ยังไม่มี)` → `[]`
- `evidence`: เนื้อหาหลัง `## Verification evidence` ใน status file ตัดไม่เกิน 600 ตัวอักษร
- `since`: mtime ของ status file (epoch s) — `null` ถ้าไม่มีไฟล์ที่ใช้ได้
- `branch`: output ของ `scripts/pane-branch.sh <@workdir> <pane_current_path>` — `null` ถ้าว่าง
- `error`: ข้อความถ้า parse ส่วนของ role นั้นพัง (role อื่นไม่กระทบ)
- `session.running: false` เมื่อไม่มี tmux session `dev-team` หรือไม่มี `.team-state.md` — ยังตอบ HTTP 200; role ที่มีแถวใน `.team-state.md` → `offline`, ที่ไม่มี (หรือไม่มีไฟล์) → `absent`, lead → `offline`

## 4. Status derivation (ต่อ role, ข้อแรกที่ตรงชนะ)

ข้อมูลเข้า: แถวใน `.team-state.md` (`ts_status`, `ts_task`, pane id), status file (`fs_status`, task, blocker, mtime), pane info จาก tmux

1. ไม่มีแถวของ role ใน `.team-state.md` → **absent**
2. pane id ไม่อยู่ใน `tmux list-panes -s -t dev-team` หรือ `pane_current_command` ∈ {zsh, bash, sh, fish, dash} (claude จบแล้วเหลือ `; read`) → **offline**
3. status file ที่ mtime < `session_created` ถือว่าไม่มี (ค้างจาก session ก่อน)
4. `fs_status == blocked` → **blocked**
5. `fs_status == working` → **working**
6. `fs_status == done`: ถ้า `ts_status == working` → **done** (รอ Lead verify); ไม่งั้น → **idle** (Lead รับงานแล้ว)
7. ไม่มี status file ที่ใช้ได้ → ใช้ `ts_status` (`working` → working, อื่นๆ → idle)

`task` = task จาก status file ถ้ามี ไม่งั้น `ts_task` (`—` → `null`)

## 5. Frontend (`dashboard/office-floor.html`)

### Keep / remove

- Keep: three.js scene builders (floor/walls/desks/monitors), character mesh builder, path-walking, OrbitControls, overlay card CSS + tokens, dark mode, reduced-motion, narrow-screen layout, decorative LED blink
- Remove: `STAFF` (30 fake people), rooms HR/CEO/Sales/PMO/AI Lab/Reception/Meeting, random activity scheduler, random feed generators, random KPIs, fake sprint "Release v2.4.0", all `Math.random()` used as data

### Floor

| Room | Occupants |
|---|---|
| Lead Office | lead |
| Dev Room | frontend, backend, mobile, devops |
| Design & Architecture | designer, architect |
| QA & Review | qa, reviewer |
| Lounge | ที่พักของคนที่ idle — โซฟา + โต๊ะกลมคุยเล่น 2 ตัว |
| Pantry & Dining | ที่พักของคนที่ idle — เคาน์เตอร์กาแฟ, ชั้นขนม, โต๊ะอาหาร |

แต่ละ role มีโต๊ะประจำ; สีตัวละคร = `role_color` ของ tmux border (frontend cyan, backend blue, mobile magenta, devops green, designer colour211, architect colour141, qa colour208, reviewer red, lead yellow — แปลงเป็น hex ที่อ่านได้ทั้ง light/dark)

### Status → visual

| status | visual |
|---|---|
| working | นั่งโต๊ะ, จอเปิด, ป้ายเหนือหัว = task (ตัดสั้น) |
| idle | เดินไปนั่งใน Lounge |
| done | เดินไปหน้า Lead Office พร้อม ✓ ค้างอยู่จนสถานะเปลี่ยน |
| blocked | ยืนที่โต๊ะ, ไอคอน ⚠ แดง, ห้อง highlight กระพริบ (นิ่งถ้า reduced-motion) |
| offline | ไม่มีตัวละคร, โต๊ะเทา, ป้าย "offline" |
| absent | โต๊ะจาง ไม่มีตัวละคร |

### Idle behaviour + mood emoji

- idle เลือกที่นั่งในกลุ่มที่มีคนอยู่แล้ว 1–2 คน (กลุ่ม ≤ 3) ไม่งั้นที่ว่างใดก็ได้; ทุก 1–2 นาทีย้ายไปกาแฟ/ขนม 15–25 วินาทีแล้วกลับไปนั่ง (ตกแต่งเท่านั้น — สถานะยังมาจาก API; ปิดเมื่อ reduced-motion)
- ฟอง emoji เหนือหัว (เวลานับจาก `since`): blocked < 10 นาที 🤔 · 10–30 😣 · > 30 🤯; done < 5 นาที 🎉 · < 30 😌 · ≥ 30 🥱; idle ตามจุด ☕ 🍪 🍜 💬
- feed: done "🎉 เสร็จแล้ว", blocked "🤔 blocked"

### Sync

- `fetch('/api/state')` ทุก 2s (ไม่ซ้อน — รอ request ก่อนหน้าเสร็จ)
- status ของ role เปลี่ยน → ตั้งเป้าหมายใหม่แล้วเดินไปด้วย path-walking เดิม; โหลดครั้งแรก → วางตัวละครที่ตำแหน่งปลายทางทันที (ไม่เดิน)
- Live indicator: เขียว = poll ล่าสุดสำเร็จ; แดง "ขาดการเชื่อมต่อ" = fetch ล้ม (คงภาพล่าสุด); ข้อความ "อัปเดต N วินาทีก่อน"
- `session.running == false` → การ์ดกลางจอ "ทีมยังไม่ได้เริ่ม — รัน ./start-team.sh" (poll ต่อ)

### Feed (client-side diff)

เทียบ snapshot ก่อนหน้ากับปัจจุบัน (ไม่สร้าง event ตอนโหลดครั้งแรก) เก็บ 50 รายการล่าสุดในหน่วยความจำ:

- `→ working`: "<role> รับงาน: <task>"
- task เปลี่ยนขณะ working: "<role> เปลี่ยนงาน: <task>"
- `→ done`: "<role> เสร็จแล้ว: <task>"
- `→ blocked`: "<role> blocked: <blocker>"
- `→ idle` จาก done/working: "<role> ว่าง"
- `→ offline`: "<role> offline"; `offline → อื่นๆ`: "<role> กลับมาออนไลน์"
- stage เปลี่ยน: "Pipeline → <stage>"

### Panels

- Header: ชื่อ project ตัวใหญ่ + chip "เปิดทีมมา …" (= serverTime − `session.created`, นับต่อทุกวินาที; ซ่อนเมื่อ session ไม่รัน)
- Top KPIs: จำนวน working / idle / done / blocked / offline
- เวลาต่องาน: working "ทำงานนี้มา", blocked "ติดปัญหามา", done "เสร็จมาแล้ว" = เวลาตั้งแต่ `since` (mtime ของ status file) — แสดงบน label, รายการ agent และ panel รายละเอียด; ไม่มี status file → ไม่แสดง
- Right: feed
- Bottom: pipeline stage + Recently Completed (สูงสุด 5)
- Click character/desk → panel: role, pane, status, task, since (relative), branch, blocker, evidence (`<pre>` scroll)
- ข้อความทั้งหมดจาก API ใส่ผ่าน `textContent`/escape — ห้าม inject HTML ดิบ

## 6. Lifecycle (`scripts/lib/common.sh`)

- `start_dashboard`:
  1. ไม่มี `python3` → เตือน แล้ว return 0
  2. มี server เดิมจาก pid file → ปิดก่อน (project อาจเปลี่ยนจากรอบก่อน)
  3. `nohup python3 dashboard/server.py --port "${DASHBOARD_PORT:-4780}" --project "$PROJECT" >/tmp/agent-teams-dashboard.log 2>&1 &` เขียน pid
  4. รอ `/api/state` ตอบ (สูงสุด 3s) — ไม่ตอบ → เตือนพร้อม path log แล้ว return 0
  5. เปิด `http://127.0.0.1:<port>/` (open / wslview / xdg-open — logic เดิมของ `open_dashboard`)
- `stop_dashboard`: kill pid จาก pid file ถ้ายังมีชีวิต แล้วลบ pid file; ไม่มี → เงียบ
- `server.py` port ถูกใช้อยู่ → exit ≠ 0 พร้อมข้อความใน log (start_dashboard จะเตือนตามข้อ 4)
- `start-team.sh`: flow y/N + `--dashboard/--no-dashboard` เดิม; เรียก `start_dashboard` ทั้งตอน resume และตอนสร้างใหม่ (ก่อน attach)
- `stop-team.sh`: เรียก `stop_dashboard` ตอนปิด session

ทุก failure ของ dashboard ต้องไม่ทำให้ start-team / stop-team ล้ม

## 7. Testing

- **Unit** (`python3 -m unittest dashboard/test_state.py`):
  - parse `.team-state.md`: ตาราง agents, project placeholder, stage, recent placeholder/list, ไฟล์ไม่มี
  - parse status file: working / done + evidence (ตัด 600) / blocked + blocker / ไฟล์เสีย
  - derivation ทั้ง 7 ข้อ รวม stale status file (mtime < session_created) และ shell = offline
  - `build_state` กับ fake tmux adapter: session ไม่รัน, ทีมครบ, ทีมบาง role
- **Smoke**: รัน server บน port ทดสอบ ชี้ไปที่ temp state file + temp status dir (env/arg override — ไม่แตะ `/tmp/agent-status` และ `.team-state.md` จริง); `curl /api/state` ตรวจ JSON
- **Browser**: เปิดหน้าใน Chrome — console ไม่มี error; เปลี่ยน temp status file แล้วเห็นตัวละครย้าย + feed ขึ้น; หยุด server แล้วเห็น "ขาดการเชื่อมต่อ"
- **Shell**: `bash -n` + shellcheck ไม่มี warning ใหม่; ทดสอบ `start_dashboard`/`stop_dashboard` แยก (ไม่รัน start-team.sh จริง ไม่แตะ tmux session `dev-team`)

`server.py` รับ `--state-file`, `--status-dir`, `--session` เพื่อ test (default = path จริง)

## 8. Risks

- `pane_current_command` ของ claude อาจเป็น `claude` หรือ `node` แล้วแต่เวอร์ชัน → ใช้ blacklist ของ shell แทน whitelist
- three.js โหลดจาก CDN → ออฟไลน์แล้วหน้า 3D ไม่ขึ้น (ยอมรับได้สำหรับ v1 ของ dashboard)
- Lead แก้ `.team-state.md` ด้วยมือผิด format → role นั้นมี `error` แต่หน้าไม่ล่ม
