# Self-Review Checklist — จับ bug ตัวเองก่อนคนอื่นเจอ

ใช้ก่อนรายงาน "เสร็จแล้ว" ทุกครั้ง — mindset คือ **reviewer ที่อยากหาเหตุผล reject งานนี้**
ไม่ใช่เจ้าของงานที่อยากปิด task ไล่จาก diff จริง (`git diff` + `git status`) ไม่ใช่จากความจำ

## 1. Diff hygiene — ของแถมที่ไม่ควรอยู่ใน diff

- [ ] `git status` — มีไฟล์แปลกปลอมที่ไม่เกี่ยวกับ task ไหม (ไฟล์ debug, .env, build artifact)
- [ ] ไม่มี `console.log` / `print` / `debugPrint` ที่ใช้ debug ค้างอยู่
- [ ] ไม่มี secret, API key, password, URL ภายใน hardcode — ต้องอ่านจาก env/config
- [ ] ไม่มี import / ตัวแปร / function ที่ประกาศแล้วไม่ได้ใช้
- [ ] ไม่มีโค้ด comment ทิ้งไว้ "เผื่อใช้" — ลบทิ้ง (git จำให้อยู่แล้ว)
- [ ] ไม่มีการแก้ formatting/refactor ไฟล์ที่ไม่เกี่ยวกับ task ปนมา

## 2. Correctness — ไล่ทีละ hunk ของ diff

- [ ] Null/undefined/empty: ทุกค่าที่มาจากภายนอก (API, DB, user input, params) ถูกเช็คก่อนใช้
- [ ] Error path: จุดที่ fail ได้ (network, DB, parse) มี handling ที่ทำอะไรสักอย่างจริง ๆ
      ไม่ใช่ catch แล้วเงียบ — และ error ที่ user เห็นต้องไม่ leak internal detail
- [ ] Async: ทุก promise ถูก await หรือ handle จริง, ไม่มี floating promise, cleanup ครบ
      (subscription, listener, timer, controller ต้องมีคู่ dispose/unsubscribe)
- [ ] Boundary: ค่าสุดขอบที่งานนี้เจอได้ — array ว่าง, หน้าแรก/หน้าสุดท้ายของ pagination,
      ค่า 0/ติดลบ, string ว่าง, timezone — เลือกเช็คอันที่เกี่ยวจริง
- [ ] เคสพร้อมกัน: ถ้ามี write ที่ชนกันได้ (double submit, 2 request พร้อมกัน) พังไหม

## 3. ตรง spec — เทียบกลับต้นฉบับ ไม่ใช่ความจำ

- [ ] เปิด plan/spec ไฟล์อีกรอบ ไล่ acceptance criteria ทีละข้อ → ครบทุกข้อ หรือระบุข้อที่ไม่ครบพร้อมเหตุผล
- [ ] เทียบ contract (`docs/contracts/`) — response shape, field names, error format, env var names
      ตรงเป๊ะ ไม่ใช่ "ประมาณนั้น" (case ของ field name ผิดตัวเดียว frontend ก็พัง)
- [ ] ไม่ได้ทำเกิน scope — feature แถมที่ไม่มีใครขอ = ภาระ review + ความเสี่ยงฟรี

## 4. Consistency — กลืนกับโค้ดเดิมไหม

- [ ] naming/โครงสร้างไฟล์ตาม pattern ของโปรเจกต์ (เทียบกับ module ที่คล้ายกันที่สุด)
- [ ] ใช้ util/helper เดิมที่มีอยู่แทนเขียนซ้ำ
- [ ] test ใหม่เขียน style เดียวกับ test เดิม

## 5. คำถามปิดท้าย (ตอบให้ได้ก่อนกดรายงาน)

1. "ถ้า reviewer ถามว่า *ทำไมถึงแก้แบบนี้* ทุกจุดใน diff — ตอบได้หมดไหม" จุดที่ตอบไม่ได้ = จุดที่ต้องกลับไปดู
2. "อะไรคือสิ่งที่**น่าจะพัง**ที่สุดในงานนี้" — แล้วเรา verify จุดนั้นไปหรือยัง ถ้ายัง → กลับไป verify
3. "มีอะไรที่เรา*หวังว่า*จะไม่มีใครสังเกต" — ถ้ามี แปลว่าต้องแก้หรือรายงานตรง ๆ ไม่ใช่ซ่อน
