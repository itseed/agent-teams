# Environment & Secret management

## หลักการ

- **Config ผ่าน env** (12-factor) — ไม่ hardcode ค่าต่าง environment ลงโค้ด
- **Secret ไม่เคยเข้า git** — ค่าจริงอยู่ใน secret manager (CI secret, cloud secret manager, .env ที่ gitignore)
- **`.env.example` เป็น source of truth ของ "ชื่อ" env var** — commit เฉพาะ key + placeholder ไม่ commit ค่าจริง
- **ชื่อ env var ต้องตรงเป๊ะทุกฝั่ง** — bug คลาสสิกคือ backend อ่าน `DATABASE_URL` แต่ devops ตั้ง `DB_URL`

## Workflow ที่ถูกต้อง

1. **grep หา env var ที่ app ใช้จริง** ก่อนเขียน config:
   ```bash
   grep -rEo "process\.env\.[A-Z_]+|ConfigService.*get\(['\"][A-Z_]+|import\.meta\.env\.[A-Z_]+" src/ | sort -u
   ```
2. เทียบรายการนั้นกับ `.env.example` — ต้องครบทุกตัว ไม่ขาดไม่เกิน
3. จัด `.env.example` ให้อ่านง่าย (group ตาม domain) + คอมเมนต์ว่าแต่ละตัวคืออะไร
4. ตรวจ `.gitignore` ครอบ `.env`, `.env.local`, `.env.*.local`, `*.pem`, `*.key`

## .env.example ตัวอย่าง
```bash
# --- Database ---
DATABASE_URL=postgresql://user:pass@localhost:5432/dbname   # connection string เต็ม

# --- Auth ---
JWT_SECRET=change-me-min-32-chars        # ใช้ sign access token
JWT_EXPIRES_IN=15m

# --- External ---
STRIPE_SECRET_KEY=sk_test_xxx            # อย่าใช้ live key ใน non-prod
```

## ตามแต่ละ runtime
- **NestJS** — อ่านผ่าน `ConfigService` + validate ด้วย Joi/zod schema ตอน boot (fail fast ถ้า env ขาด); ไม่อ่าน `process.env` กระจัดกระจาย
- **Next.js** — `NEXT_PUBLIC_*` = public ทั้งหมด (ฝังใน bundle ฝั่ง client) → **ห้ามใส่ secret**; secret ฝั่ง server อ่านได้ตรงจาก `process.env` ใน server component/route handler
- **Vite** — `VITE_*` = public เช่นกัน; secret ห้ามขึ้นต้น `VITE_`

## Red flags (ต้อง block)
- secret จริง commit ลง `.env` / Dockerfile / yml / โค้ด
- secret ใส่ใน `NEXT_PUBLIC_*` / `VITE_*`
- env var name ใน config ไม่ตรงกับที่ code อ้าง
- ไม่มี validation → app boot ผ่านแต่พังตอน runtime เพราะ env ขาด
