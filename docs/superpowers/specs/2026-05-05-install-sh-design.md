# install.sh Design

**Date:** 2026-05-05
**Status:** Approved

## Overview

`install.sh` — one-command setup script สำหรับ user ที่ clone agent-teams repo มาใหม่
รองรับ macOS และ Linux (Debian/Ubuntu)

## Goals

- ตรวจและติดตั้ง dependencies อัตโนมัติ
- ตั้งค่า Claude CLI (ถามก่อน install)
- สร้าง `projects.json` จาก example
- ตั้งค่า Snyk (optional) — รับ token + patch reviewer.md
- แสดง summary ชัดเจนว่าพร้อมใช้งานหรือยังขาดอะไร

## Platform Support

| Platform | Package Manager |
|---|---|
| macOS | `brew install` |
| Linux (Debian/Ubuntu) | `sudo apt-get install -y` |

ถ้า brew/apt ไม่มี → บอก user ลง manual พร้อมแสดงชื่อ package

## Function Structure

```
install.sh
├── check_os()         → detect macOS / Linux
├── check_deps()       → tmux, jq
├── setup_claude()     → claude CLI
├── setup_projects()   → projects.json + chmod scripts
├── setup_snyk()       → optional token + patch reviewer.md
└── verify()           → summary checklist
```

## Function Details

### `check_os()`
- Detect OS via `uname -s`
- Set `PKG_MANAGER` = `brew` (macOS) หรือ `apt-get` (Linux)
- ถ้า OS ไม่รองรับ → warn และให้ user ลง deps เอง แต่ไม่ exit

### `check_deps()` — tmux, jq
- ตรวจทั้งคู่ รวม missing list ก่อน
- ถาม once: "Install missing deps? [y/N]"
- macOS: `brew install <pkg>`
- Linux: `sudo apt-get install -y <pkg>`
- ถ้า user ปฏิเสธ → warn แต่เดินหน้าต่อ

### `setup_claude()` — Claude CLI
```
✗ claude not found
Install it now? (npm install -g @anthropic-ai/claude-code) [y/N]
```
- ถ้า yes → run npm install แล้ว verify อีกครั้ง
- ถ้า no → แสดง install URL แล้วเดินหน้าต่อ (ไม่ exit)
- ต้องการ `node` / `npm` — ถ้าไม่มีให้แจ้ง error ชัดเจน

### `setup_projects()` — projects.json
- ถ้า `projects.json` ไม่มี → copy จาก `projects.json.example`
- ถ้ามีอยู่แล้ว → skip (ไม่ทับ)
- `chmod +x start-team.sh stop-team.sh` ทำในขั้นนี้
- แสดง path ของไฟล์ที่ต้องแก้:
  ```
  → Copied projects.json.example → projects.json
  → Edit it to add your project paths: nano projects.json
  ```

### `setup_snyk()` — optional
```
Set up Snyk for security scanning? [y/N] y

Get your token from one of these:
  1. Run: snyk config get api
  2. Visit: https://app.snyk.io/account → Auth Token

Paste token:
```
- ใช้ `read -s` → input ไม่โชว์ขณะพิมพ์
- Validate token ไม่ empty — ถ้า empty ถามซ้ำ 1 ครั้ง ก่อน skip
- เขียน `SNYK_TOKEN` ลง `~/.claude/settings.json` แบบ merge (ใช้ `jq` — ไม่ทับ keys อื่น)
- ถ้า `SNYK_TOKEN` มีอยู่แล้ว → แจ้ง "already configured, skip"
- **Patch `reviewer.md`**: เพิ่ม Snyk workflow step ถ้ายังไม่มี

#### Snyk workflow ที่ inject เข้า reviewer.md
```markdown
2. **รัน Snyk scan ก่อน manual review เสมอ** (ถ้า working directory มี package.json/requirements.txt/etc.)
   ```bash
   snyk test --severity-threshold=high 2>&1 | head -60
   ```
   - ถ้าพบ **critical/high** → flag ทันที ก่อน review ต่อ
   - แนบ snyk output สรุปไว้ใน review report
```

#### patch reviewer.md logic
```bash
if grep -q "snyk test" .claude/agents/reviewer.md; then
  echo "→ reviewer.md already has Snyk workflow, skip"
else
  # inject after "## วิธีทำงาน" section header
  sed -i ... .claude/agents/reviewer.md
fi
```

### `verify()` — summary
แสดง checklist ท้าย script:
```
────────────────────────────
 Setup Summary
────────────────────────────
✓ tmux 3.3a
✓ jq 1.7
✓ claude found
✓ projects.json ready
✓ scripts executable
○ snyk (skipped)
────────────────────────────
Ready! Run: ./start-team.sh
```
- `✓` = pass, `✗` = fail/missing, `○` = skipped

## Error Handling

- ไม่ใช้ `set -e` แบบ global — แต่ละ function return exit code และ main() ตัดสินใจ
- ทุก error message บอก: สิ่งที่พัง + วิธีแก้ด้วยตัวเอง
- Script ไม่ exit กลางคัน เว้นแต่ user กด Ctrl+C

## Files Modified

| File | Action |
|---|---|
| `projects.json` | สร้างจาก example (ถ้าไม่มี) |
| `start-team.sh` | chmod +x |
| `stop-team.sh` | chmod +x |
| `~/.claude/settings.json` | เพิ่ม SNYK_TOKEN (ถ้า opt-in) |
| `.claude/agents/reviewer.md` | inject Snyk workflow (ถ้า opt-in) |

## Non-Goals

- ไม่ install Snyk CLI เอง (user ต้อง `npm install -g snyk` เอง)
- ไม่ทำ interactive wizard สำหรับ projects.json (แค่ copy example)
- ไม่รองรับ Windows
