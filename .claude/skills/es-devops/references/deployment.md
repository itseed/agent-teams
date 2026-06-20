# Deployment / rollback / health

## หลักการ

ทุก deploy ต้องตอบได้ 3 ข้อ:
1. **ขึ้นสำเร็จจริงไหม?** → health check ที่เชื่อถือได้
2. **ถ้าพังจะถอยยังไง?** → rollback plan ที่ทดสอบได้
3. **กระทบ user ตอน deploy ไหม?** → zero-downtime strategy ถ้าจำเป็น

## Health check

- มี endpoint `/health` (liveness) และถ้าจำเป็น `/ready` (readiness — เช็ค db/dependency พร้อม)
- liveness = process ยังอยู่; readiness = พร้อมรับ traffic จริง (db connected, migration done)
- container `HEALTHCHECK` + orchestrator probe ชี้มาที่ endpoint นี้
- health check **ห้ามหนัก** — ไม่ query ตารางใหญ่/เรียก external ทุกครั้ง

## Migration กับ deploy (สำคัญ)

ลำดับที่ปลอดภัยสำหรับ schema change = **expand → migrate → contract**:
1. **Expand** — เพิ่ม column/table ใหม่แบบ backward-compatible (โค้ดเก่ายังรันได้)
2. Deploy โค้ดใหม่ที่ใช้ทั้งของเก่า+ใหม่
3. **Migrate** — ย้าย/backfill ข้อมูล
4. **Contract** — ลบของเก่าหลังมั่นใจว่าไม่มีใครใช้แล้ว

อย่ารวม "ลบ column เก่า" กับ "deploy โค้ดที่เลิกใช้ column" ใน step เดียว — ถ้า rollback จะพัง

## Rollback

- เก็บ artifact/image ของ version เดิมไว้ (tag ด้วย git sha ไม่ใช่ `latest`)
- rollback = re-deploy image sha เดิม — ต้องทำได้เร็วและทดสอบแล้ว
- ระวัง migration ที่ irreversible — ถ้า migrate แบบลบข้อมูล ต้องมี backup ก่อน
- ระบุใน report เสมอว่า "ถอยยังไง" (image sha ก่อนหน้า / คำสั่ง)

## Zero-downtime (ถ้าต้องการ)
- rolling update / blue-green — ให้ instance เก่ารับ traffic จน instance ใหม่ pass readiness
- drain connection ก่อน kill instance เก่า (graceful shutdown — handle SIGTERM)
- app ต้อง stateless (session/state อยู่นอก process) ถึงจะ scale/rolling ได้

## Verify ก่อนรายงานเสร็จ
- health endpoint ตอบ 200 จริง (ทดสอบ local/staging)
- ลอง deploy ขึ้น staging ถ้ามี ก่อน prod
- เขียน rollback step ที่ชัดเจนใน report
- ตรวจว่า graceful shutdown ทำงาน (SIGTERM ไม่ตัด request กลางคัน)
