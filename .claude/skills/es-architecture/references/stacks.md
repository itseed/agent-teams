# Architecture Checklist เฉพาะ stack

โหลดเฉพาะ section ของ stack ที่เกี่ยวกับ feature ที่กำลังออกแบบ

## NestJS (backend)
- แบ่ง module ตาม domain ไม่ใช่ตาม technical layer; dependency direction ชัด ไม่มี circular
- Data ownership: ใคร write entity ไหน — เลี่ยงหลาย service เขียนตารางเดียวกันตรง ๆ
- Transaction boundary: operation ข้าม aggregate ต้องคิด consistency (transaction เดียว vs eventual)
- Auth/authorization เป็น cross-cutting (guard/interceptor) ไม่กระจายใน business logic
- Migration strategy: schema change แบบ backward-compatible (expand → migrate → contract)

## Next.js (frontend)
- แยก server vs client boundary ชัด (RSC / client component); secret อยู่ฝั่ง server เท่านั้น
- Data fetching strategy: SSR / ISR / client fetch — เลือกตาม freshness + SEO need
- State ownership: server state (react-query ฯลฯ) แยกจาก UI state; source of truth เดียว

## Flutter / React Native (mobile)
- Layered: presentation / domain / data แยกชัด, dependency ชี้เข้าหา domain
- Offline / sync strategy ถ้าต้อง; local store (cache) เป็นเจ้าของ state ตอน offline
- React Native: ยึด **bare/pure RN เท่านั้น ห้าม `expo-*`** (ตาม es-coding-convention)

## LINE LIFF
- Token verification ฝั่ง backend เสมอ — ไม่ trust profile จาก client
- แยก LIFF ID / channel ต่อ environment; กำหนด endpoint ที่ต้อง verify ID token

## PostgreSQL (data)
- Normalize ก่อน แล้ว denormalize เมื่อมีเหตุ performance จริง (วัดก่อน)
- Index ตาม query pattern ที่ออกแบบไว้; ระบุ unique/foreign key constraint ใน design
- Soft delete / audit / multi-tenancy isolation ถ้า project ต้องการ — กำหนดตั้งแต่ design
