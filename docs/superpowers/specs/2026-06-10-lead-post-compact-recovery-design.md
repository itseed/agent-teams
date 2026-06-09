# Lead Post-Compact Recovery Design
_Date: 2026-06-10_

## Problem

หลัง auto-compact Lead สูญเสีย context และเกิดปัญหา 3 อย่าง:
1. **ลืมงานค้าง** — Todo ว่างเปล่า ไม่มี anchor ให้ยึด
2. **ทำงานเอง** — ลืมว่ามี agent รออยู่ใน panes แล้วแก้โค้ดโดยตรง
3. **ส่งงานผิด pane** — RTK เลื่อน pane index +1 Lead ใช้ค่า hardcode จาก CLAUDE.md ผิด

## Solution Overview

4 ชั้นป้องกันทำงานร่วมกัน:
1. **`.team-state.md`** — persistent state file ที่ Lead เขียนและอ่านตลอด session
2. **CLAUDE.md** — เพิ่ม session recovery protocol + เพิ่ม QA→Reviewer sequential rule
3. **`UserPromptSubmit` hook** — inject state file เข้า context อัตโนมัติทุก turn
4. **`start-team.sh`** — initialize state file พร้อม verified pane IDs ตั้งแต่ต้น

---

## 1. `.team-state.md` Format

ไฟล์อยู่ที่ `agent-teams/.team-state.md`  
Lead **replace ทั้งไฟล์** ทุกครั้งที่เขียน (ไม่ append) — ขนาดคงที่ ~25-35 บรรทัดตลอด session

```markdown
# Team State
_Updated: 2026-06-10 14:32_
_RTK: yes_

## Active Project
pms-web — /Users/kriangkrai/project/pms-web

## Agents in Panes
| Role     | Pane ID | Status  | Current Task         |
|----------|---------|---------|----------------------|
| frontend | %12     | working | implement login form |
| backend  | %13     | idle    | —                    |

## Pipeline Stage
qa → reviewer → merge
Current: qa (working)

## Recently Completed
- frontend: create AuthContext and useAuth hook
- backend: POST /auth/login endpoint

## Notes
(optional — max 2-3 lines)
```

> **Pane ID vs Index:** Lead ใช้ Pane ID (`%12`) เท่านั้นในการส่งงาน — ไม่ใช้ numeric index  
> เพราะ RTK เพิ่ม pane พิเศษทำให้ index เลื่อน +1 บนเครื่องที่ติดตั้ง RTK

### Lifecycle

| เหตุการณ์ | Lead ทำ |
|-----------|---------|
| Spawn agent เข้า pane | เพิ่มแถวใน Agents table |
| Assign task | Update `Current Task` + `Status → working` |
| รับ report-back | Update `Status → idle`, เพิ่มใน Recently Completed (cap 5) |
| เปลี่ยน active project | Update `Active Project` |
| ส่งงานให้ QA | Update `Pipeline Stage: Current → qa` |
| QA PASS → ส่ง Reviewer | Update `Pipeline Stage: Current → reviewer` |

### Size Control
- **Recently Completed** — เก็บแค่ 5 รายการล่าสุด รายการเก่าทิ้ง
- Lead replace ทั้งไฟล์ทุกครั้ง → ไม่มีการสะสม

---

## 2. CLAUDE.md Changes

### 2a. ก่อนตอบ message ทุกข้อ (แก้ existing section)

```
## ก่อนตอบ message ทุกข้อ (บังคับ)
1. TodoRead — ดูงานค้างอยู่
2. อ่าน `.team-state.md` — ดูสถานะ agents, pane IDs, และ pipeline stage
   (hook inject ให้อัตโนมัติ — ต้องอ่านให้เข้าใจก่อนตอบ)
```

### 2b. Session Recovery Protocol (section ใหม่)

```
## Session Recovery Protocol

ถ้า Todo ว่างและไม่แน่ใจสถานะงาน ให้ทำตามลำดับนี้ก่อนทุกอย่าง:
1. อ่าน `.team-state.md`
2. Capture pane ทุก active agent:
   tmux capture-pane -t <pane_id> -p | tail -20
3. ประเมินว่ามี agent กำลังทำงานอยู่ไหม
4. ถ้ามี → รอหรือถาม agent นั้นก่อน
5. ห้ามสรุปเองว่า "งานเสร็จแล้ว" โดยไม่ verify
```

### 2c. Lead ห้ามทำงานเอง (เพิ่มใน existing section)

```
- แม้ Todo ว่าง แม้ context หาย แม้ดูเหมือนง่าย → ยังห้ามแก้ไฟล์เอง
- ใช้ Pane ID จาก .team-state.md เสมอ — ห้ามใช้ index จาก CLAUDE.md โดยตรง
```

### 2d. QA → Reviewer Pipeline (เพิ่ม rule ใหม่)

```
- QA และ Reviewer ทำงาน sequential เสมอ — ห้าม spawn Reviewer
  จนกว่า QA จะ report PASS กลับมา
```

---

## 3. Hook — `settings.json`

เพิ่มใน project `.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "if [ -f .team-state.md ]; then echo '=== TEAM STATE ===' && cat .team-state.md; else echo '[WARNING] .team-state.md ไม่มี — รัน start-team.sh ก่อน'; fi"
          }
        ]
      }
    ]
  }
}
```

**ผลลัพธ์:** Lead เห็น `.team-state.md` เป็น system reminder ใน context ทุก turn แม้หลัง compact

---

## 4. `start-team.sh` Changes

### 4a. ตรวจ RTK และ Initialize `.team-state.md`

หลัง set `@role` / `@role_color` ของทุก pane แล้ว ตรวจ RTK แล้วเขียน state file ด้วย Pane IDs จริง:

```bash
# ตรวจว่า RTK ติดตั้งอยู่หรือไม่
RTK_INSTALLED="no"
if command -v rtk &>/dev/null; then
  RTK_INSTALLED="yes"
fi

cat > "$AGENT_TEAMS_DIR/.team-state.md" << EOF
# Team State
_Session started: $(date '+%Y-%m-%d %H:%M')_
_RTK: $RTK_INSTALLED_

## Active Project
[Lead ต้อง set หลังอ่าน projects.json]

## Agents in Panes
| Role     | Pane ID         | Status | Current Task |
|----------|-----------------|--------|--------------|
| frontend | $PANE_FRONTEND  | idle   | —            |
| backend  | $PANE_BACKEND   | idle   | —            |
| mobile   | $PANE_MOBILE    | idle   | —            |
| devops   | $PANE_DEVOPS    | idle   | —            |
| designer | $PANE_DESIGNER  | idle   | —            |
| qa       | $PANE_QA        | idle   | —            |
| reviewer | $PANE_REVIEWER  | idle   | —            |

## Pipeline Stage
ยังไม่เริ่ม

## Recently Completed
(ยังไม่มี)

## Notes
Session เริ่มใหม่ — Lead ต้อง set Active Project ก่อนรับงาน
EOF
```

> **หมายเหตุ:** Pane IDs (`$PANE_FRONTEND` ฯลฯ) ถูก capture ด้วย `-P -F '#{pane_id}'` ตั้งแต่ตอน split  
> ค่าเหล่านี้ stable ไม่ขึ้นกับ RTK — Lead ส่งงานด้วย Pane ID เสมอ ไม่ใช้ numeric index

### 4b. Onboarding message บอก Lead

เพิ่มใน Lead onboarding prompt:

```
.team-state.md ถูกสร้างแล้ว — pane IDs จริงอยู่ในนั้น
ให้ set Active Project ใน .team-state.md ก่อนรับงาน
```

---

## Files Changed

| ไฟล์ | การเปลี่ยนแปลง |
|------|----------------|
| `agent-teams/.team-state.md` | สร้างใหม่ (template) |
| `agent-teams/CLAUDE.md` | เพิ่ม 4 sections |
| `agent-teams/.claude/settings.json` | เพิ่ม UserPromptSubmit hook |
| `agent-teams/start-team.sh` | เพิ่ม state file init + onboarding update |
| `agent-teams/.gitignore` | เพิ่ม `.team-state.md` (runtime file) |

---

## Success Criteria

- [ ] หลัง auto-compact Lead อ่าน `.team-state.md` และ capture panes ก่อนทำอะไร
- [ ] Lead ไม่แก้ไฟล์เองแม้หลัง compact
- [ ] Lead ส่งงานถูก pane (ใช้ Pane ID จาก state file)
- [ ] QA เสร็จก่อนเสมอ จึงส่งงาน Reviewer ต่อ
- [ ] `.team-state.md` ขนาดไม่เกิน 40 บรรทัดตลอด session
