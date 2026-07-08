# Loop State: <feature name>

> Lead copy จาก `templates/loop-state-template.md` ไปวางที่ `docs/plan/<feature>-loop.md` ใน repo ของ project
> **ไฟล์นี้คือ source of truth ของ loop** — อัปเดตทุก transition (เริ่ม/ผ่าน/FAIL gate, checkpoint)
> ห้ามพึ่งความจำ/context: auto-compact ลบความจำได้ แต่ลบไฟล์ไม่ได้ (protocol เต็ม: skill `es-loop-engineering`)

## Goal & scope

<หนึ่งย่อหน้า: งานใหญ่ชิ้นนี้ทำอะไร — เสร็จแล้วโลกต่างจากเดิมยังไง>

**Non-goals:** <กัน scope creep — ของที่ตัดออกจากลูปนี้>

## Iterations (vertical slices — แต่ละอันต้อง demo ได้จบในตัว)

| # | Slice | Roles | Plan file | Status | Checkpoint sha |
|---|-------|-------|-----------|--------|----------------|
| i1 | <เช่น login flow (API+UI)> | backend, frontend | `docs/plan/<feature>-i1.md` | ✅ done | `<sha>` |
| i2 | <slice ถัดไป> | <roles> | `docs/plan/<feature>-i2.md` | 🔄 in progress | — |
| i3 | <slice ถัดไป> | <roles> | `docs/plan/<feature>-i3.md` | ⏳ pending | — |

Status: ⏳ pending / 🔄 in progress / ✅ done / ⛔ blocked

## Current (จุดที่ loop อยู่ตอนนี้ — recovery อ่านตรงนี้ก่อน)

- **Iteration:** i2
- **Gate:** <dev / lead-verify / qa / reviewer / integration>
- **FAIL rounds ที่ gate นี้:** 0/3
- **Last checkpoint:** `<sha>` (i1)
- **รออะไรอยู่:** <เช่น "qa กำลังเทส — ดู /tmp/agent-status/qa.md">

## Log (append-only — จดทุก transition พร้อมเวลา)

- `<YYYY-MM-DD HH:MM>` เริ่มลูป — แตกงานเป็น 3 iterations
- `<YYYY-MM-DD HH:MM>` i1 ผ่าน Gate D → checkpoint `<sha>`
- `<YYYY-MM-DD HH:MM>` i2 FAIL Gate C รอบ 1 — <สรุปสั้น + ชี้ evidence ใน plan file>

## Backlog / carry-over (scope ใหม่ที่เจอระหว่างทาง — ห้ามยัดเข้า iteration ที่วิ่งอยู่)

- [ ] <ของที่เจอระหว่างทาง — รอผู้ใช้ตัดสินใจ หรือเป็น iteration ใหม่ท้ายคิว>

## Integration loop (เริ่มเมื่อทุก iteration ✅)

| Round | QA verdict | Reviewer findings | ผล |
|-------|-----------|-------------------|-----|
| 1 | — | — | — |

จบเมื่อได้ **dry round** (QA PASS + Reviewer ไม่มี finding ใหม่ 1 รอบเต็ม) — เพดาน 3 rounds
