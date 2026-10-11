# Changelog

### 2026-10-11

**Windows (WSL2)** — เพิ่ม `.gitattributes` บังคับ LF ให้ `*.sh`/`*.json`/`*.md` (กัน `$'\r': command not found`);
`install.sh` เช็ค/ติดตั้ง `lsof` (hook cleanup/reap dev server ใช้ — ไม่มีแล้ว hook เงียบ); README แนะนำวาง project
ใน filesystem ของ WSL ไม่ใช่ `/mnt/c`

**v2 ใช้ subagent ที่ลงทะเบียนแล้ว** — `.claude/agents/<role>.md` มี `name:` แล้ว Lead จึง spawn ด้วย
`subagent_type: "<role>"` ได้ตรงๆ: role .md เป็น system prompt, `model:` ใน frontmatter ถูกใช้อัตโนมัติ —
ตัด workaround เดิม (general-purpose + inject role + ส่ง model เอง) ออก, เหลือเป็น fallback เท่านั้น
`start-team-v2.sh` ไม่เปิด `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` อีก (กัน Agent tool สร้าง teammate pane ชนกับ log pane)

### 2026-10-10

**Review cleanup** — แก้ bug + ลดความซ้ำซ้อน:
- `start-team.sh`: `((i++))` ภายใต้ `set -e` ทำให้ `auto_trust`/`inject_lead_context` ตายหลังรอบแรก — แก้แล้ว + trust prompt detection อ่าน wrapped line/scrollback
- hook `cleanup-dev-on-close.sh` ไม่ trigger จากข้อความที่ agent paste เข้า Lead pane อีกต่อไป (เช่น "qa จบแล้ว PASS")
- hook `reap-zombie-devservers.sh` ทำงานบน macOS แล้ว (ps ของ macOS ไม่มี `etimes`)
- `scripts/lib/common.sh` = แหล่งเดียวของ role list / label / color / model / effort / provisioning
- protocol ของ v1 (ack / status file / report-back) ย้ายไป `templates/agent-protocol.md` — append ให้ทุก agent ตอน start; agent ส่งข้อความผ่าน `team-send.sh`
- agent .md มี `name:` ใน frontmatter แล้ว; `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` เปิดเฉพาะ v2
- `CLAUDE.md` 419 → 140 บรรทัด, `es-agent-excellence` เหลือเฉพาะกฎของทีม

### 2026-06-21

**เพิ่ม role `architect` (รวมเป็น 8 specialists)** — solution architect แบบ design-only/upstream: ออกแบบ system architecture, ADR, tech decisions, module/data boundaries แล้วเขียนเป็น `docs/architecture/<feature>.md` ให้ dev implement ตาม (เหมือน designer แต่ฝั่ง technical) — **ไม่เขียน feature code**. Pipeline: Lead → architect → dev → qa → reviewer. Model = Sonnet, pane อยู่ right column คู่กับ designer (color violet). มาพร้อม skill `es-architecture` (approach options + ADR + tradeoff matrix + boundary) และ `templates/architecture-template.md`. wire ครบทั้ง v1/v2 + restore-pane-labels.

**เพิ่ม skill `es-devops` (devops มี playbook แล้ว → ครบทั้ง 8 roles)** — ปิดช่องว่างเดียวที่เหลือ: devops เคยไม่มี team skill เฉพาะ. `es-devops` ครอบ Dockerfile/compose convention (multi-stage, non-root, pin version), CI/CD pipeline (GitHub Actions, least-privilege permissions), env/secret management (12-factor, ห้าม secret หลุด), deployment/rollback/health (expand→migrate→contract) + security checklist — progressive disclosure (references: docker / ci-cd / env-secrets / deployment). wire เข้า `devops.md` + skill-injection table.

**เพิ่ม skill `es-design-system` (designer มี playbook design token แล้ว)** — เดิม designer พึ่งแค่ `frontend-design` (ความ distinctive) แต่ไม่มี playbook คุม token/state ให้เป็นระบบ. `es-design-system` กำหนด token taxonomy 2 ชั้น (primitive→semantic), scale มาตรฐาน (spacing/type/radius/shadow/motion), theming (light/dark โดยไม่แตะ component), a11y/contrast (WCAG AA), และ **UI states ครบทุก view (loading/empty/error/has-data)** — เน้น **empty state convention: icon + heading + description action-oriented + ปุ่ม optional ที่ไปทิศทางเดียวกันทั้งแอป** (references: tokens / states / theming / a11y). wire เข้า `designer.md` + skill-injection table.

### 2026-06-15

**Team skills (`.claude/skills/`)** — เพิ่ม 3 skill เป็น playbook ร่วมที่ agent โหลดก่อนเริ่มงาน (output deterministic ไม่ขึ้นกับว่าโมเดลจะนึกได้เองรอบนั้นไหม): `es-coding-convention` (frontend/backend/mobile — naming/structure/scaffold ต่อ stack), `es-code-review` (reviewer — severity + OWASP Top 10 + verdict), `es-test-strategy` (qa — test pyramid + gap severity). prefix `es-` กันชนกับ built-in `/code-review`; ทุก skill ใช้ progressive disclosure (reference แยกต่อ stack), security ครบ OWASP Top 10 ใน `references/security.md`, React Native = bare/pure RN เท่านั้น (ห้าม `expo-*`) — wire เข้า reviewer/qa/frontend/backend/mobile แล้ว ดู [Skills](#skills-team-playbooks)

### 2026-06-11

**v2 mode (`start-team-v2.sh`)** — โหมด hybrid: Lead spawn agents ผ่าน **Agent tool** (structured, return value) ส่วน agent panes เป็น **log viewer** (`tail -f /tmp/agent-logs/<role>.log`) — ได้ความน่าเชื่อถือของ structured spawn พร้อม visibility แบบ v1 (เห็น agent แยก pane); v1 ยังเป็น default ดู [Modes](#modes-v1-default--v2)

**Stable pane IDs (single source of truth)** — เลิกใช้ numeric index (`0.N`) ที่ไม่เสถียร (RTK เพิ่ม pane ทำให้ index เลื่อน +1) ทุกการ address ใช้ stable `%ID` จาก `.team-state.md` แหล่งเดียว — ลบตาราง numeric ที่ขัดกันออกจาก CLAUDE.md + agent ทุกตัว

**Model tiers (pinned)** — pin model ชัดเจน ไม่ขึ้นกับ default ของเครื่องอีกต่อไป: **Sonnet** สำหรับ frontend/backend/mobile/devops/qa/reviewer, **Haiku** สำหรับ designer (qa เลื่อน Haiku → Sonnet เพราะ edge-case reasoning; reviewer = Sonnet เพราะเป็น security gate)

**Verification gate ก่อนรายงานเสร็จ** — code agents ต้อง run typecheck/build/test/run-dev + แนบ evidence ก่อนบอก "เสร็จแล้ว" — ห้ามโยน error ที่รู้อยู่แล้วไป QA (แก้ปัญหา error โผล่ตอน run dev → rework)

**Requirement-as-file + contract-first** — แก้ requirement drift: Lead เขียน plan/spec เป็นไฟล์ใน `docs/plan/` ก่อน delegate (ไม่พึ่ง tmux paste ที่ lossy) และ backend นิยาม API contract ใน `docs/contracts/` ก่อนงาน parallel — มี template ใน `templates/`

**Ack protocol** — agent ส่ง "รับงานแล้ว: …" ทันทีที่รับ task ยืนยันว่า prompt ถึง + เข้าใจ scope (ไม่ชัด = ถามกลับ ไม่เดา)

**`scripts/team-send.sh`** — helper ส่ง task เข้า pane แบบเชื่อถือได้ (load-buffer → paste → submit → verify-landed + retry) แก้ปัญหา prompt ค้างใน input box

**Anti-generic UI** — frontend/mobile/designer invoke skill `frontend-design` ทุกครั้งที่ทำ UI เพื่อเลี่ยง generic AI aesthetic

**Reviewer governance** — รายงาน PASS/FAIL เท่านั้น ห้าม merge เอง, security ต้อง confirm ก่อน merge, + Snyk guard เมื่อไม่มี snyk ติดตั้ง

**Cleanup** — gitignore `.mcp.json`/`.DS_Store`, ลบไฟล์ขยะ, ลบ dead code (`RTK_PANE_CREATED`)

### 2026-05-09 (2)

**Windows support (Beta)** — เพิ่ม `setup-windows.ps1` สำหรับ Windows user: ติดตั้ง WSL2 + Ubuntu + clone repo + รัน `install.sh` อัตโนมัติ  
`start-team.sh` ตรวจสอบและแสดง error ถ้ารันบน Windows native (CMD/PowerShell) พร้อมแนะนำ WSL2  
ดูรายละเอียดทั้งหมดที่ [Windows Setup (Beta)](#windows-setup-beta)

### 2026-05-09

**Role isolation** — agents แต่ละตัวเริ่มใน `/tmp/agent-<role>/` ที่มี CLAUDE.md ระบุ specialist role ไว้ตั้งแต่ต้น ป้องกันปัญหา agent คิดว่าตัวเองเป็น Lead เมื่อเริ่มบน project ใหม่

**Startup context injection** — Lead ได้รับ context อัตโนมัติเมื่อ session เริ่ม (project name, paths, pane mapping) ไม่ต้องบอก Lead ซ้ำทุกครั้ง

**Peer-to-peer communication** — agent คุยกันตรงได้ผ่าน tmux โดย CC Lead ทุกครั้ง ลดการ bottleneck ที่ Lead

**Clarified responsibilities** — ขีดเส้นแบ่งชัดขึ้นเพื่อลด overlap:
- Designer: output spec/tokens เท่านั้น (ไม่เขียน feature code)
- QA: integration/e2e เท่านั้น (unit test = หน้าที่ dev agent)
- Reviewer: performance จาก code เท่านั้น (ไม่ใช่ regression testing)

**Submit reliability** — รวม `paste-buffer` + `sleep 0.5` + `send-keys Enter` ไว้ในคำสั่งเดียว ป้องกัน submit ไม่สมบูรณ์

**Auto trust prompt** — `start-team.sh` ตอบ Claude Code folder trust prompt อัตโนมัติสำหรับทุก agent pane

**Mobile: Capacitor.js** — เพิ่ม Capacitor.js เข้า mobile agent skill set

---

