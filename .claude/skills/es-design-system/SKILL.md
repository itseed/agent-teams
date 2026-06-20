---
name: es-design-system
description: ใช้เมื่อต้องวาง/ออกแบบ design system, design token, หรือ spec UI ที่ frontend/mobile จะ implement — กำหนด token taxonomy (color/spacing/typography/radius/shadow/motion), theming (light/dark), state ของ UI (empty/loading/error ให้ icon+ข้อความไปทิศทางเดียวกัน), และ a11y/contrast หรือเมื่อ designer agent ได้รับงานทำ spec แม้ผู้ใช้พูดแค่ "ทำ design token" หรือ "วาง design system" ครอบคลุม CSS variables / Tailwind / Flutter ThemeData / React Native
---

# Design System

ออกแบบ design system + token ที่ทำให้ทุกหน้าจอ **สม่ำเสมอ (consistent)** และ implement ได้ตรง —
output คือ **spec/token ที่ frontend/mobile หยิบไปใช้ได้ทันที** ไม่ใช่ค่าสุ่มต่อหน้าจอ

> ใช้คู่กับ skill `frontend-design` — `frontend-design` ทำให้ดีไซน์ **distinctive ไม่ generic**,
> ส่วน skill นี้ทำให้ token/state/spec **เป็นระบบเดียวกันทั้งแอป** (deterministic)

## เป้าหมาย

- **Token เป็น single source of truth** — สี/ระยะ/ตัวอักษรทุกค่า มาจาก token ไม่ใช่ magic number กระจาย
- **Consistency** — component เดียวกัน + state เดียวกัน (empty/loading/error) ต้องหน้าตา + โทนข้อความไปทิศทางเดียวกันทุกหน้า
- **Themeable** — เปลี่ยน light/dark หรือ brand ได้โดยไม่แก้ component
- **Accessible** — contrast ผ่าน WCAG, focus มองเห็น, แตะได้ (touch target ใหญ่พอ)

## ขั้นตอน

1. **อ่าน context ก่อน** — design ของเดิมในโปรเจกต์ (มี EmptyState component? token file? Tailwind config?), CLAUDE.md/DESIGN.md, Figma ที่ Lead ให้ — **match ของเดิมก่อนเสมอ** อย่าสร้าง system ใหม่ทับของที่มี
2. invoke skill **`frontend-design`** ก่อน เพื่อยึด design language ที่ distinctive (ไม่ใช่ default framework)
3. เลือก reference ตามงาน (progressive disclosure):
   - **token scales + output format** → `references/tokens.md`
   - **light/dark + semantic token** → `references/theming.md`
   - **UI states: empty / loading / error** → `references/states.md` (icon + ข้อความ convention)
   - **a11y / contrast / focus / touch target** → `references/a11y.md`
4. เขียน spec/token เป็นไฟล์ (เช่น `docs/design/<feature>-spec.md` หรือ token file ตาม stack) — ระบุ token ที่ใช้, state ทุกตัว, a11y requirement
5. **ตรวจ consistency + a11y** ก่อน mark complete (ดู checklist ล่าง)

## หลักการ token (สรุป — รายละเอียดใน references/tokens.md)

- ใช้ **scale ไม่ใช่ค่าสุ่ม**: spacing เป็น step (4/8/12/16/24/32…), type scale มีลำดับชัด, radius/shadow เป็นชุด
- **2 ชั้น**: primitive token (`blue-500`, `space-4`) → semantic token (`color-primary`, `surface`, `text-muted`) — component อ้าง semantic เท่านั้น
- naming สม่ำเสมอทั้งระบบ (เลือก convention เดียว: `--color-text-primary` หรือ `colorTextPrimary` แล้วยึด)

## UI States — บังคับทุกหน้าที่มี data (สำคัญ)

ทุก view ที่โหลด/แสดง data **ต้องออกแบบครบทุก state** ไม่ใช่แค่ตอนมีข้อมูล:

| State | ต้องมี |
|-------|--------|
| **Loading** | skeleton/spinner ที่ตรงกับ layout จริง ไม่ใช่จอขาว |
| **Empty** | **icon + heading สั้น + ข้อความแนะนำ 1 บรรทัด + (optional) ปุ่ม action** — โทน + โครงเดียวกันทุกหน้า |
| **Error** | icon + อธิบายว่าเกิดอะไร + ปุ่ม retry — ไม่โชว์ stack trace ดิบ |
| **Has data** | layout ปกติ |

**Empty state convention (ยึดทั้งแอป — ดู references/states.md ละเอียด):**
- มี **icon เสมอ** (อยู่ใน container ขนาดสม่ำเสมอ เช่นกล่อง rounded ขนาดเดียวกันทุกหน้า)
- มี **heading** สั้น บอก "ยังไม่มีอะไรที่นี่" และ **description 1 บรรทัด** บอก "ทำยังไงต่อ"
- **โทนข้อความไปทิศทางเดียวกัน** — เป็นมิตร + ชี้ทางออก (action-oriented) ไม่ใช่แค่ "No data" ห้วน ๆ; ใช้คำ/บุคลิกเดียวกันทุกหน้า
- ถ้ามี action ที่ผู้ใช้ทำได้ → ใส่ปุ่ม primary เดียว (เช่น "เพิ่มรายการแรก")
- ถ้าโปรเจกต์มี `EmptyState` component อยู่แล้ว → **ใช้ตัวนั้น** อย่าประดิษฐ์ inline ใหม่ที่หน้าตาเพี้ยน

## Consistency + a11y checklist (ก่อนถือว่าเสร็จ)

- [ ] ทุกค่าสี/ระยะ/ฟอนต์ อ้างจาก token ไม่มี hardcode magic number
- [ ] component อ้าง **semantic token** ไม่ใช่ primitive ตรง ๆ
- [ ] ทุก data view มีครบ loading / empty / error / has-data
- [ ] empty state ทุกหน้า: icon + heading + description + (action) โครง + โทนเดียวกัน
- [ ] contrast ผ่าน WCAG AA (text ปกติ ≥ 4.5:1, large text ≥ 3:1) — ดู `references/a11y.md`
- [ ] focus state มองเห็นได้ (keyboard), touch target ≥ 44×44px
- [ ] รองรับ dark mode ถ้าโปรเจกต์มี (semantic token สลับค่าได้)

## รูปแบบผลลัพธ์

spec เขียนเป็นไฟล์ให้ frontend/mobile อ่าน — ระบุชัด: token ที่ใช้ (อ้างชื่อ semantic), ทุก state พร้อมข้อความจริง, a11y requirement, และ reference component ที่มีอยู่ในโปรเจกต์

หลักการ: **token เดียวทั้งระบบ, ทุก state ออกแบบครบ, empty state ไปทิศทางเดียวกัน, contrast ผ่านเสมอ**
