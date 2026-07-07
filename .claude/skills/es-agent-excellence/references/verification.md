# Verification Evidence — พิสูจน์ว่างานเสร็จจริง

หลักการ: evidence คือ **output จริงจากการรันคำสั่งจริง** ไม่ใช่คำบรรยายว่า "ทดสอบแล้ว"
Lead/QA ต้องอ่านแล้ว reproduce ตามได้

## ลำดับการ verify (ทำเท่าที่โปรเจกต์มี — ดูจาก package.json scripts / Makefile / README)

1. **Static** — typecheck + lint: `tsc --noEmit`, `npm run lint`, `flutter analyze`
2. **Build** — `npm run build`, `flutter build` (โหมดที่เบาที่สุดพอพิสูจน์ว่า compile ผ่าน)
3. **Unit tests** — รันชุดที่เกี่ยวกับงาน + ชุดเดิมทั้งหมดถ้าเร็วพอ (กัน regression)
4. **Exercise จริง** — สำคัญที่สุดและถูกข้ามบ่อยที่สุด (ดูต่อ stack ด้านล่าง)

## Exercise จริงต่อ stack

### Backend (NestJS / REST / GraphQL)
```bash
# start server (background) แล้วยิงของจริง
npm run start:dev &   # หรือ docker compose up -d
curl -s -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"test@example.com","password":"secret"}' | head -50
```
- ยิงทั้ง happy path **และ** error path อย่างน้อย 1 เคส (input ผิด → ได้ 400 ตาม error format ใน contract ไหม)
- endpoint ที่มี auth guard → ยิงแบบไม่มี token ต้องได้ 401 จริง
- มี migration → รัน migration จริงบน dev DB แล้วดูว่า schema ตรง

### Frontend (Next.js / React)
- `npm run dev` แล้วเปิดหน้าที่แก้ — ดู render จริง ไม่ใช่แค่ build ผ่าน
- เช็คครบ 4 states ของ data view: loading / empty / error / has-data (mock หรือปิด API เพื่อดู error state)
- ดู console ใน browser — ต้องไม่มี error/warning ใหม่ที่งานนี้สร้าง

### Mobile (React Native / Flutter)
- อย่างน้อย: build ผ่าน + test ผ่าน; ถ้ารัน simulator ได้ให้เปิดจอที่แก้จริง
- Flutter: `flutter analyze` + `flutter test` ต้องเขียว
- RN: ห้ามมี `expo-*` เพิ่มใน diff (เช็ค package.json ก่อนรายงาน)

### DevOps
- Dockerfile → `docker build` ผ่านจริง + `docker run` แล้ว health check ตอบ
- CI workflow → validate syntax (`actionlint` ถ้ามี) + อธิบายว่า trigger เมื่อไหร่ ทดสอบ step ที่รัน local ได้
- env/secret → ยืนยันว่าไม่มีค่า secret จริงหลุดลง commit (`git diff` หา pattern key/token)

### Designer / Architect / QA (งานที่ output เป็นไฟล์ .md)
- Evidence = ไฟล์ output อยู่ที่ path ที่ตกลง + ครบทุก section ตาม template + อ้าง requirement ทีละข้อว่า cover ตรงไหน
- Architect: ADR ระบุ options ที่ตัดทิ้งพร้อมเหตุผล ไม่ใช่มีแต่ทางที่เลือก
- QA: verdict ต้องอ้าง test ที่รันจริงพร้อม output ไม่ใช่ความเห็น

## รูปแบบ evidence ในรายงาน + status file

```markdown
## Verification
- typecheck: ✅ ผ่าน (tsc --noEmit — 0 errors)
- unit tests: ✅ 14/14 passed (แนบ tail ของ output)
- smoke: ✅ POST /auth/login → 200 {"accessToken":"..."} / password ผิด → 401 ตาม contract
- acceptance criteria: ข้อ 1 ✅ ข้อ 2 ✅ ข้อ 3 ⚠️ (rate limit ยังไม่ทำ — นอก scope ตาม plan)
```

- ทุกบรรทัดต้องมาจากการรันจริงใน session นี้ — ห้าม copy ผลรอบก่อนมาแปะ
- มีข้อไหน fail/ข้าม → เขียนตรง ๆ พร้อมเหตุผล ห้ามตัดบรรทัดนั้นทิ้ง
