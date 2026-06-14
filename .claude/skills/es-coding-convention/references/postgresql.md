# PostgreSQL Convention

ครอบคลุม schema/migration/query ระดับ DB — อ่านคู่กับ `nestjs.md` (ORM-level rule อยู่ที่นั่น) ตรงนี้เน้นฝั่ง database เอง

## Naming
- **ตาราง**: `snake_case` พหูพจน์ → `users`, `order_items`
- **คอลัมน์**: `snake_case` → `created_at`, `user_id`
- **Primary key**: `id` (uuid หรือ bigint identity) `[ปรับตามทีม: uuid vs bigserial]`
- **Foreign key**: `<ref_table_singular>_id` → `user_id`, `order_id`
- **Index**: `idx_<table>_<cols>` ; **unique**: `uq_<table>_<cols>` ; **fk**: `fk_<table>_<ref>`
- ห้ามใช้ reserved word เป็นชื่อ (`user`, `order` ต้อง quote — เลี่ยงไปเลย ใช้พหูพจน์)

## Schema design
- ทุกตารางมี `created_at` / `updated_at` (`timestamptz` ไม่ใช่ `timestamp`)
- เก็บเวลาเป็น `timestamptz` (UTC) เสมอ — แปลง timezone ที่ application layer
- เงิน/จำนวนที่ต้องแม่นใช้ `numeric(precision, scale)` ห้ามใช้ `float`/`double`
- `NOT NULL` เป็น default — เปิด nullable เฉพาะที่จำเป็นจริง ตั้ง default ให้ชัด
- enum ใช้ lookup table หรือ `CHECK` constraint `[ปรับตามทีม: native enum vs check]` — เลี่ยง native enum ถ้าค่าจะเปลี่ยนบ่อย (alter ยาก)
- soft delete ใช้ `deleted_at timestamptz NULL` `[ปรับตามทีม: soft vs hard delete]`

## Index & performance
- ตั้ง index ทุก foreign key ที่ใช้ join บ่อย (PG ไม่สร้าง auto ให้ FK)
- คอลัมน์ที่อยู่ใน `WHERE`/`ORDER BY` บ่อยและ cardinality สูง → พิจารณา index
- composite index เรียงคอลัมน์ตามลำดับการ filter (left-most prefix)
- ระวัง index เกินจำเป็น — เพิ่มต้นทุน write; วัดด้วย `EXPLAIN ANALYZE` ก่อนเพิ่ม
- query list ต้องมี `LIMIT`/pagination เสมอ ไม่ดึงทั้งตาราง

## Integrity & safety
- บังคับ relation ด้วย FK constraint จริงในระดับ DB ไม่พึ่ง application อย่างเดียว
- ตั้ง `ON DELETE` ให้ตรง business (`CASCADE` / `RESTRICT` / `SET NULL`) อย่าปล่อย default เงียบ ๆ
- unique constraint ที่ระดับ DB สำหรับ business key (เช่น email) ไม่เช็คแค่ app
- ทุก raw query ต้อง parameterized — ห้าม string concat (SQL injection)

## Migration
- ทุกการเปลี่ยน schema ผ่าน migration file ที่ commit ลง repo — ไม่แก้ DB ด้วยมือบน prod
- migration ต้อง reversible (มี down) หรืออธิบายชัดถ้า irreversible
- ห้าม `synchronize: true` / auto-migrate บน prod
- การเปลี่ยนที่ lock ตารางนาน (add column with default บนตารางใหญ่, add index) ทำแบบ non-blocking: `CREATE INDEX CONCURRENTLY`, เพิ่ม column nullable ก่อนแล้ว backfill
- แยก migration ที่เปลี่ยน schema ออกจาก data migration

## Transaction
- operation ที่แก้หลายตารางให้ atomic ต้องอยู่ใน transaction เดียว
- เปิด transaction ให้สั้นที่สุด อย่าครอบ I/O ภายนอก (HTTP call) ไว้ในนั้น
- ระวัง deadlock: lock ตารางตามลำดับเดียวกันทุก path
