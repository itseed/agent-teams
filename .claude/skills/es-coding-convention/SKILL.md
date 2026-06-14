---
name: es-coding-convention
description: ใช้เมื่อเริ่มเขียนโค้ดใหม่, สร้าง module/component/screen ใหม่, scaffold โปรเจกต์, หรือสงสัยว่า "วางไฟล์ตรงไหน / ตั้งชื่อยังไง / โครงสร้างควรเป็นแบบไหน" แม้ผู้ใช้พูดแค่ "เขียน API ใหม่ให้หน่อย" หรือ "สร้างหน้าจอนี้" ก็ตาม ครอบคลุม naming, folder structure, error handling, git convention สำหรับ stack NestJS / Next.js / Flutter / React Native / LINE LIFF / PostgreSQL
---

# Coding Convention

มาตรฐานสำหรับเขียนโค้ด **ใหม่** ให้เข้ากับโค้ดเดิม และ scaffold โครงสร้างให้ถูกตั้งแต่แรก
เป้าหมาย: ไม่ว่า agent ตัวไหน (frontend/backend/mobile) เขียน โค้ดที่ออกมาต้องดูเหมือนคนคนเดียวเขียน

> **หมายเหตุ:** ถ้า repo มี `CLAUDE.md` หรือ convention ที่เขียนไว้แล้ว ให้ยึดอันนั้นก่อนเสมอ
> ไฟล์นี้คือ default เมื่อ repo ไม่ได้ระบุ และเป็นจุดที่ทีมควรปรับให้ตรงของจริง (ดู `[ปรับตามทีม]`)

## ขั้นตอนใช้งาน

1. ดูว่างานใหม่อยู่ stack ไหน แล้วอ่าน reference ที่ตรง:
   - **NestJS / backend / API** → `references/nestjs.md`
   - **Next.js / frontend / React** → `references/nextjs.md`
   - **Flutter / mobile** → `references/flutter.md`
   - **React Native / mobile** → `references/react-native.md` (อ่าน TypeScript ใน universal rules ด้วย)
   - **LINE LIFF** → `references/line-liff.md` (อ่านคู่กับ nextjs)
   - **PostgreSQL / DB schema / migration** → `references/postgresql.md` (อ่านคู่กับ nestjs)
2. ทำตาม universal rules ด้านล่าง + reference ของ stack นั้น
3. ก่อนสร้างไฟล์ใหม่ ดูโครงสร้างโฟลเดอร์เดิมในโปรเจกต์ก่อน แล้ววางให้สอดคล้อง

## Universal rules (ทุก stack)

### Naming
- **ไฟล์/โฟลเดอร์**: `kebab-case` (เช่น `user-profile.service.ts`, `order-list/`)
- **Class / Component / Type / Interface**: `PascalCase`
- **ตัวแปร / ฟังก์ชัน**: `camelCase`
- **ค่าคงที่ระดับ module**: `UPPER_SNAKE_CASE`
- **Boolean**: ขึ้นต้นด้วย `is` / `has` / `should` / `can` (เช่น `isLoading`, `hasPermission`)
- ตั้งชื่อให้สื่อความหมาย หลีกเลี่ยงตัวย่อกำกวม (`usr`, `tmp`, `data2`)

### โครงสร้างโค้ด
- ฟังก์ชันทำหน้าที่เดียว สั้นพอที่อ่านจบในจอเดียว ถ้ายาวเกินไปให้แตกย่อย
- ใช้ early return แทน nested if ลึก ๆ
- ไม่มี magic number / magic string — ดึงเป็นค่าคงที่ที่มีชื่อ
- ลบ dead code, `console.log`, commented-out code ก่อน commit
- Comment อธิบาย "ทำไม" ไม่ใช่ "ทำอะไร" (โค้ดบอกอยู่แล้วว่าทำอะไร) `[ปรับตามทีม: ภาษา comment]`

### TypeScript
- เปิด `strict` mode เลี่ยง `any` — ถ้าจำเป็นจริงใช้ `unknown` แล้ว narrow
- กำหนด return type ของ public function ชัดเจน
- ใช้ `type` สำหรับ union/utility, `interface` สำหรับ object shape ที่อาจ extend `[ปรับตามทีม]`

### Error handling
- ไม่ swallow error เงียบ ๆ — log หรือ throw ต่อเสมอ
- error message สื่อความหมาย ระบุ context พอให้ debug ได้
- แยก error ที่คาดไว้ (validation, not found) ออกจาก error ที่ไม่คาด (bug, infra)

### Git convention `[ปรับตามทีม]`
- **Commit**: Conventional Commits — `feat:`, `fix:`, `refactor:`, `chore:`, `test:`, `docs:`
  รูปแบบ `<type>(<scope>): <subject>` เช่น `feat(auth): add LINE login guard`
- **Branch**: `<type>/<short-desc>` เช่น `feat/order-export`, `fix/liff-login-loop`
- commit ย่อยพอที่ revert ทีละก้อนได้ ไม่รวมหลายเรื่องใน commit เดียว

### Config / secret
- ทุก secret อยู่ใน env ไม่ hardcode ไม่ commit `.env`
- มี `.env.example` ที่ list key ครบ (ค่าเป็น placeholder)
- แยก config ตาม environment (dev/uat/prod) ชัดเจน

---

รายละเอียดเฉพาะ stack + โครงสร้าง scaffold อยู่ในไฟล์ `references/` อ่านเฉพาะตัวที่ตรงกับงาน