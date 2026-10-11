---
name: es-agent-excellence
description: Base workflow สำหรับทุก task ที่ agent รับจาก Lead ไม่ว่า role ไหน — อ่าน spec ให้จบก่อนลงมือ, ยึด plan/contract เป็น source of truth, verify ด้วยหลักฐานจริง, self-review, รายงานแบบ outcome-first พร้อม evidence และวิธีถาม Lead โดยไม่ค้าง interactive prompt ใช้เมื่อเริ่มรับ task, ก่อนรายงาน "เสร็จแล้ว", หรือเมื่อติดขัดระหว่างงาน
---

# Agent Excellence — workflow มาตรฐานของทีม

ทำตามลำดับนี้ทุก task (งานที่ดูง่ายคืองานที่เดาผิดบ่อยที่สุด)

## 1. เข้าใจงาน

- อ่าน plan/spec ที่ Lead ระบุ **จบทั้งไฟล์** ก่อนแตะอะไร แล้วตอบให้ได้: ผลลัพธ์ที่ต้องการ, acceptance criteria ("done = อะไรผ่าน"), อะไรอยู่นอก scope
- ข้อเท็จจริงที่หาเองได้ → ไปหาในโค้ด; การตัดสินใจที่ spec ตีความได้หลายทาง → ถาม Lead **ก่อนลงมือ** (ดู "ถาม Lead" ด้านล่าง)

## 2. สำรวจ + วางแผน

- `docs/contracts/`, `docs/architecture/`, `docs/design/` และ CLAUDE.md ของ repo คือ source of truth —
  ห้าม implement ขัดเงียบๆ ถ้าคิดว่ามันผิด → แจ้ง Lead
- ยึด pattern ของโค้ดที่คล้ายที่สุดใน repo (โค้ดใหม่: โหลด `es-coding-convention` ประกอบ)
- แผนต้องแตะเกิน ~5 ไฟล์ หรือเปลี่ยน design ที่ตกลงไว้ → ส่งแผนให้ Lead ดูก่อน
- เจอ bug นอก scope → จดไว้รายงาน Lead ไม่แก้แถม

## 3. Verify ด้วยหลักฐานจริง

"โค้ดที่ยังไม่ได้รัน = ยังไม่เสร็จ" — รายละเอียดต่อ stack + รูปแบบ evidence: `references/verification.md`

1. รัน typecheck / lint / build / unit tests เท่าที่ project มี — ต้องผ่านจริง
2. **Exercise ของจริงอย่างน้อย 1 ครั้ง** — endpoint → start server แล้ว curl; UI → เปิด render; script → รันกับ input จริง
3. เทียบ acceptance criteria + contract ทีละข้อ (response shape, env var names, error format)
4. ติดปัญหาเดิมเกิน 3 รอบ → หยุด ทบทวนสมมติฐาน ถ้ายังตันให้รายงาน Lead พร้อมสิ่งที่ลองแล้ว — ห้ามเงียบหาย

ห้ามทำให้ "ผ่าน" ด้วยการลบ test, `any`/`@ts-ignore`, catch กลบ error, หรือ comment โค้ดทิ้ง

## 4. Self-review + รายงาน

- อ่าน `git diff` ทั้งหมดแบบ reviewer ที่อยากหาเรื่อง reject (checklist: `references/self-review.md`)
- เขียน status + evidence ลง `/tmp/agent-status/<role>.md` **ก่อน** report กลับ Lead
- รายงาน **outcome-first**: บรรทัดแรก = ได้อะไร → evidence (output จริง) → ไฟล์ที่แตะ → ความเสี่ยง/สิ่งที่ข้าม
- ซื่อสัตย์: test fail บอก fail พร้อม output, ข้าม step ไหนบอกเหตุผล — ห้ามส่งงานที่รู้ว่ายังพังพร้อม "เกือบเสร็จแล้ว"

## ถาม Lead — ห้ามใช้ interactive confirmation

`AskUserQuestion` / permission menu / CLI confirm แบบ interactive **บล็อก turn ทั้งหมดรออยู่ใน pane ของคุณเอง**
โดย Lead ไม่เห็นเลย (บทเรียนจริง: งานหยุดเงียบจน Lead บังเอิญ capture-pane เจอ)

1. เลือกทาง safe/conservative เองได้โดยไม่กระทบข้อมูลจริง (เช่น local dev DB) → ตัดสินใจเอง แล้วรายงานสิ่งที่ทำ+เหตุผล
2. ตัดสินใจเองไม่ได้ (destructive ต่อข้อมูลจริง / เดิมพันสูง / scope ไม่ชัด) → เขียน status `blocked`
   + ส่งคำถามเป็นข้อความธรรมดาหา Lead (v1: `team-send.sh`, v2: จบด้วย return value) แล้วหยุดรอ ไม่เดาทำต่อ
