---
name: es-loop-engineering
description: ใช้เมื่อ Lead รับงานชิ้นใหญ่ที่ทำรวดเดียวไม่จบ — แตกงานเป็น iteration (vertical slice) แล้ววนลูป dev→verify→QA→Reviewer→checkpoint ทีละรอบ, จัดการ FAIL แบบ bounded feedback loop (เกินโควตา = escalate ผู้ใช้ ไม่วนฟรี), เก็บสถานะข้าม iteration/auto-compact ใน loop state file, ปิดงานด้วย integration loop จน "dry" ใช้เมื่องานแตกได้เกิน ~5 tasks, ใช้ dev ≥2 role ที่มี dependency ข้ามกัน, แตะหลาย module, หรือประเมินว่ากิน context เกินหนึ่งรอบ
---

# Loop Engineering — คุมงานชิ้นใหญ่ด้วยวงจร ไม่ใช่ความจำ

งานใหญ่ไม่ได้พังเพราะ agent เขียนโค้ดไม่เก่ง แต่พังเพราะ **loop ไม่ถูก engineer**:
verify ถูกกองไว้ท้ายงาน (error สะสมทับกัน 20 ไฟล์), context หมดกลางทางแล้วสถานะหาย,
QA FAIL แล้ววนแก้ไม่รู้จบ, requirement เบี่ยงไปทีละนิดจนงานรวมไม่เข้ากัน —
skill นี้แก้ทั้งหมดด้วยการทำให้งานใหญ่เป็น **ลูปสั้นๆ ที่ปิดได้ทีละรอบ** แทน marathon รวดเดียว

## เมื่อไหร่ต้องเข้าโหมด loop (เข้าข้อใดข้อหนึ่ง = ใช้)

- แตกงานได้เกิน **~5 tasks** หรือประเมินว่าแตะเกิน **~15 ไฟล์ / หลาย module**
- ต้องใช้ **dev ≥2 role ที่มี dependency ข้ามกัน** (เช่น backend + frontend + mobile บน feature เดียว)
- ผู้ใช้สั่งงานระดับระบบ: "ทำทั้ง flow", "migrate", "refactor ใหญ่", "สร้าง module ใหม่ทั้งชุด"
- ประเมินแล้วงานยาวพอที่ context ของ Lead/agent จะโดน auto-compact กลางทาง

ไม่เข้าเกณฑ์ → ทำแบบปกติ (delegate เดี่ยว + QA→Reviewer ตาม pipeline เดิม) — อย่า over-engineer งานเล็ก

## โครงของ loop (ภาพรวม)

```
Milestone plan ──► iteration 1 ──► iteration 2 ──► … ──► integration loop ──► สรุปผู้ใช้
                   │                                      (วนจน dry)
                   ▼
        ┌─ dev ──► Gate A: dev verify ─► Gate B: Lead verify ─► Gate C: QA ─► Gate D: Reviewer ─► checkpoint ─┐
        │                                                                                                     │
        └───────────────◄── FAIL: feedback loop (แนบ evidence, นับรอบ, เกิน 3 = escalate) ◄───────────────────┘
```

1. **Milestone plan** — แตกงานเป็น iteration แบบ **vertical slice**: แต่ละ iteration ต้องเป็นชิ้นที่
   **รันได้จริง demo ได้จริง** ครบทั้งเส้น (เช่น "login flow ทั้ง API+UI" ไม่ใช่ "backend ทั้งหมดก่อน แล้วค่อย frontend ทั้งหมด")
   — slice แนวนอนคือสาเหตุอันดับหนึ่งที่งานรวมไม่เข้ากันตอนท้าย
2. **สร้าง loop state file** ที่ `docs/plan/<feature>-loop.md` ใน repo ของ project
   (copy จาก `templates/loop-state-template.md`) — เป็น source of truth ของ loop
   **อัปเดตทุก transition ห้ามพึ่งความจำ/context** เพราะ auto-compact ลบความจำได้แต่ลบไฟล์ไม่ได้
3. **ต่อ iteration**: เขียน `docs/plan/<feature>-i<N>.md` (plan template เดิม) → delegate ตาม discipline ปกติ
   → ผ่าน gate A→B→C→D ตามลำดับ (รายละเอียดแต่ละ gate + FAIL protocol: `references/gates.md`)
4. **Checkpoint ทุกครั้งที่ iteration ผ่านครบ gate** — commit โค้ดของ iteration นั้น + จด sha ลง loop state file
   แล้วค่อยเริ่ม iteration ถัดไป (พังรอบหน้า = ถอยกลับ checkpoint ได้ ไม่ใช่เริ่มใหม่ทั้งงาน)
5. **Integration loop ปิดท้าย** — ทุก iteration เสร็จแล้วยังไม่จบ: ส่ง QA เทส integration/e2e
   **ทั้ง feature ข้าม iteration** + Reviewer ดู diff รวม วนจนกว่าจะได้ **dry round**
   (1 รอบเต็มที่ไม่มี finding ใหม่) — เพราะ bug ที่แพงที่สุดคือ bug ระหว่างรอยต่อของ slice

## กฎเหล็กของ loop

- **1 iteration = 1 slice ที่ verify ได้จบในตัว** — ถ้านิยาม "done" ของ iteration ไม่ได้ = slice ยังหั่นไม่ถูก
- **ห้ามเปิด iteration ใหม่ทั้งที่ iteration เดิมยังไม่ผ่าน gate ครบ** — ยกเว้นงาน parallel ที่ contract
  ตกลงกันเป็นไฟล์แล้วเท่านั้น (contract-first ตาม CLAUDE.md)
- **Bounded ทุกลูป** — FAIL ที่ gate เดิมเกิน **3 รอบ** หรือ integration loop เกิน **3 รอบ** → หยุด escalate
  ผู้ใช้พร้อมสรุปสิ่งที่ลอง (ลูปที่ไม่มีเพดาน = เผา token ฟรีและซ่อนปัญหา design)
- **No-progress rule** — 2 รอบติดกันไม่มี acceptance criteria ผ่านเพิ่ม → หยุดวนแก้ปลายเหตุ
  ถอยมาหา root cause (มักเป็นปัญหา design → ส่ง architect ก่อนค่อย dev ต่อ)
- **ทุก fix จาก FAIL ต้องแนบ regression test** ที่ fail ก่อนแก้/pass หลังแก้ — กัน bug เดิมโผล่รอบหน้า
- **Scope ใหม่ระหว่างทาง = iteration ใหม่** — จดลง loop state file (backlog) ไม่ใช่ยัดเข้า iteration ปัจจุบัน
- **อัปเดต loop state file + `team-state.sh stage` ทุก transition** เช่น
  `./scripts/team-state.sh stage "loop <feature> i2/4 — qa gate (fail 1/3)"`

## Recovery หลัง auto-compact / เปิด session ใหม่

Todo ว่าง + จำอะไรไม่ได้ ไม่ใช่ปัญหา ถ้าทำตามนี้:

1. อ่าน `.team-state.md` — ถ้า stage ขึ้น `loop <feature> ...` แสดงว่ามี loop ค้าง
2. อ่าน `docs/plan/<feature>-loop.md` ทั้งไฟล์ — section **Current** บอกว่าอยู่ iteration ไหน gate ไหน fail ไปกี่รอบ
3. เช็ค `/tmp/agent-status/<role>.md` ของ role ที่ status = working ก่อนสั่งอะไรใหม่
4. ทำต่อจากจุดนั้น **ห้ามเริ่ม iteration ซ้ำ ห้ามข้าม gate** — checkpoint commit ล่าสุดใน loop state file
   คือเส้นแบ่งว่าอะไรเสร็จจริงแล้ว
