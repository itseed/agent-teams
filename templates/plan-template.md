# Plan: <feature name>

> Lead เขียนไฟล์นี้ก่อน delegate แล้วสั่ง agent "อ่าน docs/plan/<feature>.md ให้ครบก่อนเริ่ม"
> วางไว้ที่ `docs/plan/<feature>.md` ใน repo ของ project

## Goal
<หนึ่งย่อหน้า: feature นี้ทำอะไร แก้ปัญหาอะไรให้ใคร>

## Requirements
- [ ] <requirement ที่ verify ได้ ข้อ 1>
- [ ] <requirement ข้อ 2>
- [ ] <requirement ข้อ 3>

## Non-goals (สิ่งที่ "ไม่" ทำในรอบนี้)
- <กัน scope creep>

## Tasks (1 task = 1 deliverable)
| Task | Owner | ไฟล์ที่แตะ | Done = (acceptance criteria) |
|------|-------|-----------|------------------------------|
| <implement X> | frontend | <paths> | typecheck ผ่าน + <criteria ที่ตรวจได้> |
| <implement Y> | backend  | <paths> | unit test ผ่าน + endpoint ตอบตาม contract |

## Standing checklist (Lead กรอกทุกงาน — ลบข้อที่ไม่เกี่ยวพร้อมเหตุผลสั้นๆ)
> กลุ่มปัญหาที่ถูกส่งกลับซ้ำๆ จาก QA/Reviewer — dev ต้องเขียนเทสครอบข้อที่เกี่ยวตั้งแต่แรก
- [ ] **ข้อมูลส่วนตัว / ล้างข้อมูล:** ข้อมูลใหม่ที่เก็บ (คอลัมน์/log) ถูกล้างพร้อมข้อมูลเดิมตอนปิดการเก็บ/retention หรือไม่
- [ ] **แยก workspace (tenant):** ทุก query/สถานะ/presence จำกัดใน workspace เดียวกัน; มีเคส "อยู่คนละ workspace"
- [ ] **ด่านก่อนทำงาน (gate):** workspace ถูกระงับ / ฟีเจอร์ปิด / plan ไม่รองรับ → พฤติกรรมเดิมไม่ถูกข้าม
- [ ] **งบ query/ประสิทธิภาพ:** ระบุเพดานจำนวน query/call ต่อ request + เคสแย่สุด; regex/loop บน input ยาว
- [ ] **ถอยหลัง (regression):** เทสเดิมที่เกี่ยวข้อง (e2e เดิม, helper, fixture) ยังผ่าน; ฟีเจอร์ที่เพิ่งแก้ก่อนหน้าไม่พัง
- [ ] **race / ลำดับเวลา:** ข้อความ/งานเบื้องหลังซ้อนกัน, retry, ค้างจากเทสอื่น (isolation)

## Test cases (QA เขียนก่อน dev เริ่ม — เฉพาะงาน api ที่แตะสถานะ/ความเป็นส่วนตัว/tenant/migration/ประสิทธิภาพ; งาน UI ล้วน/test-only/docs ข้ามได้)
> dev เขียนเทสครอบทุกเคสในหัวข้อนี้ก่อนเขียนโค้ด; QA ตรวจว่ามีเทสครบ **และต้องลองเคสนอกรายการเพิ่มเสมอ**
- เคสขอบ: <...>
- เคสที่ต้องไม่เกิด: <...>
- ความเป็นส่วนตัว / tenant: <...>
- งบประสิทธิภาพ: <...>
- ถอยหลัง: <...>

## Contracts / integration points
- API contract: `docs/contracts/<api>.md` (backend นิยามก่อน frontend/mobile ใช้)
- env vars: <ชื่อที่ตกลงร่วมกัน — ต้องตรงทุกฝั่ง>

## Verification (ก่อนถือว่า feature เสร็จ)
- [ ] ทุก acceptance criteria ข้างบนผ่าน + มี evidence
- [ ] run dev ไม่มี error
- [ ] QA: integration/e2e ครอบคลุม happy path + edge cases → PASS
- [ ] Reviewer: security + quality → PASS
