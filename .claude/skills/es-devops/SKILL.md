---
name: es-devops
description: ใช้เมื่อต้องทำงาน infra/deployment — เขียน Dockerfile/compose, ตั้ง CI/CD pipeline, จัดการ env/secret, วาง deployment + rollback strategy, health check/observability หรือเมื่อ devops agent ได้รับงาน แม้ผู้ใช้พูดแค่ "ทำ docker ให้หน่อย" หรือ "ตั้ง CI" หรือ "deploy ขึ้น prod ยังไง" ครอบคลุม Docker / GitHub Actions / env-secret / deployment-rollback
---

# DevOps Playbook

ทำงาน infra อย่างเป็นระบบและ **ปลอดภัย** ผลลัพธ์คือ config ที่ reproducible, ปลอดภัย,
และ verify ได้จริง — ไม่ใช่ config ที่ "น่าจะรันได้"

## เป้าหมาย

infra ที่ดีคือ **reproducible + ปลอดภัย + กู้คืนได้**:
- build/deploy ซ้ำได้ผลเหมือนเดิม (pin version, lock dependency, ไม่พึ่ง state ในเครื่อง)
- secret ไม่เคยหลุดเข้า git / image / log — อ้างผ่าน secret manager หรือ env injection เสมอ
- ทุก deploy ต้องมีทางถอย (rollback) และ health check ที่บอกได้ว่า "ขึ้นสำเร็จจริงไหม"
- env var names **ตรงเป๊ะ** กับที่ app อ้างถึง (bug คลาสสิก: `SUPABASE_WEBHOOK_SECRET` vs `WEBHOOK_SECRET`)

## ขั้นตอน

1. **อ่าน context ก่อน** — `docs/plan/<feature>.md`, CLAUDE.md ของ repo, ไฟล์ config เดิม (Dockerfile/compose/CI ที่มีอยู่), และ **env var ที่ app อ้างถึงจริง** (grep `process.env` / `ConfigService` / `import.meta.env`)
2. เลือก reference ที่ตรงกับงาน (โหลดเฉพาะที่ใช้ — progressive disclosure):
   - **Docker / compose** → `references/docker.md`
   - **CI/CD (GitHub Actions)** → `references/ci-cd.md`
   - **env / secret management** → `references/env-secrets.md`
   - **deployment / rollback / health** → `references/deployment.md`
3. เขียน/แก้ config ตาม convention ใน reference
4. **Verify ก่อนรายงานเสร็จ** (ดูด้านล่าง) — แนบ evidence
5. เทียบ env var names + acceptance criteria กับที่ Lead/dev ระบุ ก่อน mark complete

## หลักการข้ามทุก reference

- **Pin version** — base image, action version (`@v4` ไม่ใช่ `@main`), runtime — กัน "ผ่านเมื่อวาน พังวันนี้"
- **Least privilege** — container run เป็น non-root, token/secret ให้ scope แคบสุด, อย่าใช้ `latest` ใน prod
- **Secret ห้าม commit** — ใช้ placeholder ใน `.env.example`, จริงอยู่ใน secret manager / CI secret; ตรวจว่า `.env` อยู่ใน `.gitignore`
- **Fail fast + observable** — health check, structured log, exit code ที่สื่อความหมาย
- **12-factor** — config ผ่าน env, stateless process, logs เป็น event stream

## Verification ก่อนรายงานเสร็จ (บังคับ)

พิสูจน์ว่า config รันได้จริง — **ห้ามรายงานเสร็จถ้ายังมี error**:

| งาน | คำสั่ง verify |
|-----|---------------|
| shell script | `bash -n <file>` |
| Dockerfile | `docker build -t test .` (ต้อง build ผ่านจริง) |
| docker-compose | `docker compose config` (validate) + `docker compose up` ถ้าทำได้ |
| GitHub Actions yml | `actionlint` ถ้ามี / ตรวจ syntax + ดู job dependency |
| env | grep env var names ใน code เทียบกับ `.env.example` — ต้องตรงทุกตัว |

แนบ output สรุป (ผ่าน/ไม่ผ่าน) ตอนรายงานกลับ — ห้ามโยน config ที่รู้ว่าพังไปให้ Lead/QA

## Security checklist (ก่อนถือว่าเสร็จ)

- [ ] ไม่มี secret/credential จริงใน Dockerfile, compose, yml, หรือ committed `.env`
- [ ] `.env` / `*.pem` / `*.key` อยู่ใน `.gitignore`
- [ ] base image pinned + มาจาก source ที่เชื่อถือได้ (official / digest)
- [ ] container ไม่ได้ run เป็น root โดยไม่จำเป็น
- [ ] CI ไม่ echo secret ออก log (`::add-mask::` ถ้าจำเป็น)
- [ ] port ที่ expose จำกัดเท่าที่ต้องใช้ ไม่เปิดกว้างเกิน

## รูปแบบผลลัพธ์

รายงานกลับ Lead ด้วยโครง:

```
## DevOps: <งานที่ทำ>

**ไฟล์ที่แตะ:** <paths>

**Verify:**
- docker build → ✅ ผ่าน (image 142MB)
- compose config → ✅ valid
- env var เทียบ code → ✅ ตรงทั้ง 6 ตัว

**Security:** <ผ่าน checklist / ข้อที่ต้องระวัง>

**Rollback:** <ถอยยังไงถ้า deploy พัง>
```

หลักการ: ทุก config มี **verify evidence**, secret **ไม่หลุด**, ทุก deploy **มีทางถอย**
