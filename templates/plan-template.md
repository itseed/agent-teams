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

## Contracts / integration points
- API contract: `docs/contracts/<api>.md` (backend นิยามก่อน frontend/mobile ใช้)
- env vars: <ชื่อที่ตกลงร่วมกัน — ต้องตรงทุกฝั่ง>

## Verification (ก่อนถือว่า feature เสร็จ)
- [ ] ทุก acceptance criteria ข้างบนผ่าน + มี evidence
- [ ] run dev ไม่มี error
- [ ] QA: integration/e2e ครอบคลุม happy path + edge cases → PASS
- [ ] Reviewer: security + quality → PASS
