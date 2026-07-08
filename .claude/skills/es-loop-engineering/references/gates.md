# Gates ต่อ iteration + FAIL protocol

ทุก iteration ต้องผ่าน gate A→B→C→D **ตามลำดับ ห้ามข้าม ห้ามสลับ** — gate คือจุดที่ loop
"ปิดรอบ" ได้จริง ถ้าปล่อยผ่าน gate ด้วยความเชื่อ (ไม่ใช่หลักฐาน) ลูปถัดไปจะแพงขึ้นเสมอ

## Gate A — Dev verification (agent ที่ทำงานพิสูจน์เอง)

- เกิดใน task ของ dev agent เอง: typecheck / lint / build / unit test ผ่าน + exercise ของจริง
  (ตาม `es-agent-excellence` Phase 5 — Lead inject skill นี้ในทุก task prompt อยู่แล้ว)
- **ผ่าน = agent รายงาน done พร้อม verification evidence ใน `/tmp/agent-status/<role>.md`**
- ไม่มี evidence → ยังไม่ถึง Gate B — ส่งกลับให้ verify ห้าม mark complete (กฎเดิมของ CLAUDE.md)

## Gate B — Lead verify (กันงานเบี่ยงก่อนเข้า QA)

- Lead เทียบผลงานกับ acceptance criteria ใน `docs/plan/<feature>-i<N>.md` **ทีละข้อ**
- เช็คว่าตรง contract (`docs/contracts/`) และ architecture (`docs/architecture/`) — ไม่ใช่แค่ "มีโค้ดแล้ว"
- งาน parallel หลาย role: เช็ค integration point ว่าสอง role ใช้ shape/env var ตรงกันจริง
- ผ่าน → `team-state.sh stage "loop <feature> i<N> — qa gate"` แล้วส่ง QA

## Gate C — QA (integration/e2e ของ slice นี้)

- QA เทส slice นี้ **รวมกับ checkpoint ก่อนหน้า** (regression ของ iteration เก่าต้องยังผ่าน)
  ไม่ใช่เทสเฉพาะของใหม่แบบโดดๆ
- Task prompt ของ QA ต้องบอก: path plan ของ iteration, path loop state file, และ checkpoint sha ล่าสุด
- Verdict ตาม `es-test-strategy`: ✅ ปล่อยได้ / 🔄 ต้องเพิ่ม test / ⛔ Block

## Gate D — Reviewer (หลัง QA PASS เท่านั้น — sequential ตาม pipeline เดิม)

- Review diff ของ iteration นี้ (ตั้งแต่ checkpoint ก่อนหน้า) ตาม `es-code-review`
- PASS → checkpoint: commit + จด sha ลง loop state file + mark iteration เป็น done

## Checkpoint (ปิดรอบ)

1. commit เฉพาะไฟล์ของ iteration นี้ (`git add <specific files>` — กฎเดิม)
2. อัปเดต loop state file: iteration status = ✅, จด checkpoint sha, ย้าย Current ไป iteration ถัดไป
3. `team-state.sh stage "loop <feature> i<N+1>/… — dev"`
4. รายงานความคืบหน้าสั้นๆ ให้ผู้ใช้ (1-2 บรรทัด: iteration ไหนเสร็จ เหลืออะไร) — งานใหญ่ห้ามเงียบยาว

## FAIL protocol (feedback loop แบบมีเพดาน)

เมื่อ gate ไหน FAIL:

1. **แนบ evidence กลับไปเต็มๆ** — verdict ของ QA/Reviewer, error output, เคสที่พัง
   ลงเป็นไฟล์หรือ append ใน plan ของ iteration (`## Fix round <n>` section) แล้วชี้ agent ไปอ่าน
   — ห้ามย่อยเป็นคำสั่งลอยๆ ("แก้ bug ให้หน่อย" = เริ่ม requirement drift รอบใหม่)
2. **ส่งกลับ role ที่รับผิดชอบ** — fix ต้องมาพร้อม regression test (fail ก่อนแก้ / pass หลังแก้)
3. **นับรอบ FAIL ต่อ gate ต่อ iteration** ลง loop state file แล้วเข้า gate เดิมใหม่ **ตั้งแต่ Gate A**
   (fix ก็ต้อง verify — ไม่ใช่ fix แล้วกระโดดข้ามไป Reviewer เลย)
4. **เพดาน: 3 รอบต่อ gate** — แตะเพดานแล้วห้ามวนต่อ ให้ escalate ผู้ใช้พร้อม:
   - สิ่งที่ลองแล้วทั้ง 3 รอบ + ทำไมไม่ผ่าน
   - สมมติฐาน root cause (design ผิด? requirement ขัดกัน? dependency นอกเหนือการควบคุม?)
   - ทางเลือกที่เสนอ (เช่น ตัด scope, เปลี่ยน approach, ให้ architect ออกแบบใหม่)
5. **No-progress rule** — ถึงยังไม่แตะเพดาน แต่ 2 รอบติดกันไม่มี criteria ผ่านเพิ่มเลย →
   หยุดวนแก้ปลายเหตุ: มักแปลว่าปัญหาอยู่ที่ design ไม่ใช่โค้ด — ส่ง architect วิเคราะห์ก่อน
   (ผลอาจเป็นการแก้ architecture file แล้วค่อยกลับมา dev ต่อ) หรือ escalate ถ้าเป็นการตัดสินใจของผู้ใช้

## Integration loop ปิดท้าย (loop-until-dry)

เมื่อทุก iteration ผ่าน gate ครบ:

1. `team-state.sh stage "loop <feature> — integration loop round 1"`
2. QA รัน integration/e2e **ทั้ง feature ข้าม slice** (โฟกัสรอยต่อ: flow ที่วิ่งผ่านหลาย iteration,
   ข้อมูลที่ส่งต่อกันระหว่าง module) + Reviewer ดู **diff รวมทั้งงาน** จาก checkpoint แรกถึงล่าสุด
3. มี finding → เข้า FAIL protocol ปกติ (แก้ → regression test → verify) แล้ววน round ใหม่
4. **จบเมื่อได้ dry round**: 1 รอบเต็มที่ QA PASS และ Reviewer ไม่มี finding ใหม่
5. เพดาน 3 round — เกินแล้วยังไม่ dry = มีปัญหาเชิงโครงสร้าง → escalate ผู้ใช้ ไม่วนต่อ
6. Dry แล้ว → อัปเดต loop state file เป็น done ทั้งลูป, commit สุดท้าย, สรุปผลรวมทุก iteration ให้ผู้ใช้
   (อะไรเสร็จ, checkpoint ไหนบ้าง, ข้อจำกัด/backlog ที่จดไว้ระหว่างทาง)

## สิ่งที่ห้ามทำใน loop (สรุป)

- ❌ เปิดหลาย iteration พร้อมกันโดยไม่มี contract file ระหว่างกัน
- ❌ ข้าม gate เพราะ "รอบที่แล้วเพิ่งผ่าน" — ทุก fix กลับเข้า Gate A เสมอ
- ❌ วนแก้เกินเพดานโดยไม่ escalate — เพดานมีไว้บังคับให้เปลี่ยนวิธี ไม่ใช่ไว้ฝ่า
- ❌ อัปเดตสถานะ loop ไว้ในหัว/ใน chat อย่างเดียว — ทุก transition ต้องลง loop state file
- ❌ merge scope ใหม่เข้า iteration ที่กำลังวิ่ง — จดเป็น backlog ให้ผู้ใช้ตัดสินใจ
