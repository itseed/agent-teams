# UI States — empty / loading / error (consistent ทั้งแอป)

ทุก view ที่โหลดหรือแสดง data **ต้องออกแบบครบทุก state** — จอขาว/ค้าง = bug ทาง UX
state เดียวกันต้องหน้าตา + โทนข้อความ **ไปทิศทางเดียวกันทุกหน้า**

## 1. Empty state (สำคัญ — ยึด convention นี้ทั้งแอป)

แสดงเมื่อ query สำเร็จแต่ไม่มีข้อมูล (≠ error, ≠ loading)

**โครงบังคับ — ทุก empty state ต้องมีครบ:**

1. **Icon** — สื่อถึง entity ที่ว่าง (เช่นกล่องเปล่า, เอกสาร, รายการ) อยู่ใน **container ขนาดสม่ำเสมอทุกหน้า** (เช่นกล่อง rounded ขนาดเดียว สีพื้น muted)
2. **Heading** — สั้น 1 บรรทัด บอกสถานะ เช่น "ยังไม่มีรายการ" / "ยังไม่มีคอร์ส"
3. **Description** — 1 บรรทัด บอก **ทำยังไงต่อ** (action-oriented) ไม่ใช่แค่บอกว่าว่าง
4. **Action (ถ้ามี)** — ปุ่ม primary เดียวที่พาไปสร้าง/เพิ่มรายการแรก

**โทนข้อความ (ไปทิศทางเดียวกัน):**
- เป็นมิตร + ชี้ทางออก ไม่ใช่ห้วน/เชิงลบ
- ❌ "No data" / "ไม่พบข้อมูล" (ห้วน, ตัน)
- ✅ "ยังไม่มีคอร์ส — เริ่มสร้างคอร์สแรกของคุณได้เลย" (+ ปุ่ม "สร้างคอร์ส")
- ใช้ voice/persona + คำเรียก entity เดียวกันทุกหน้า (ถ้าเรียก "รายการ" ก็เรียกแบบนี้ทั้งแอป)

**Implementation:**
- ถ้าโปรเจกต์มี `EmptyState` component → **ใช้ตัวนั้นเสมอ** (อย่า inline ใหม่ที่หน้าตาเพี้ยน)
- ถ้ายังไม่มี → สร้าง shared `EmptyState({ icon, title, description, action? })` ตัวเดียว แล้วใช้ซ้ำทุกหน้า
- icon container, spacing, สี ต้องมาจาก token เดียวกัน — empty state สองหน้าต้องวางเหมือนกันเป๊ะ

**โครง markup (web):**
```tsx
<EmptyState
  icon={<BoxIcon />}                       // ใน container ขนาดคงที่ (เช่น 56×56 rounded-2xl, พื้น muted)
  title="ยังไม่มีคอร์ส"
  description="เริ่มสร้างคอร์สแรกเพื่อจัดการเนื้อหาการเรียน"
  action={<Button>สร้างคอร์ส</Button>}     // optional
/>
```
ค่า spec แนะนำ: icon container ขนาดเดียวทั้งแอป (เช่น `56×56`, radius `lg/2xl`, พื้น `color-surface-muted`), title = `text-base/lg` `font-medium` `color-text-primary`, description = `text-sm` `color-text-muted`, จัดกึ่งกลางแนวตั้ง มี spacing จาก token

> หมายเหตุ: บางโปรเจกต์มี pattern เฉพาะอยู่แล้ว (เช่นกล่องไอคอน `w-14 h-14 rounded-2xl` + ข้อความ `text-sm font-medium`) — **ยึดของโปรเจกต์นั้น** ความสม่ำเสมอภายในแอปสำคัญกว่าค่ากลางในเอกสารนี้

## 2. Loading state

- ใช้ **skeleton ที่ตรงกับ layout จริง** (รูปทรงเดียวกับ content ที่จะมา) ดีกว่า spinner กลางจอ
- spinner ใช้กับ action สั้น ๆ (ปุ่ม submit) ไม่ใช่โหลดทั้งหน้า
- อย่าให้ layout กระโดด (CLS) ตอน content มาแทน skeleton — จองพื้นที่ให้เท่ากัน

## 3. Error state

- **icon + อธิบายว่าเกิดอะไร (ภาษาคน)** + ปุ่ม **retry**
- ห้ามโชว์ stack trace / error object ดิบให้ผู้ใช้
- แยก error ระดับ field (inline ใต้ input) ออกจาก error ระดับหน้า (full-page)
- โทนเดียวกับ empty state — สุภาพ + ชี้ทางแก้ ("ลองใหม่อีกครั้ง")

## Checklist
- [ ] ทุก data view มีครบ 4 state: loading / empty / error / has-data
- [ ] empty state ทุกหน้าใช้ component/โครงเดียวกัน (icon + title + description + action?)
- [ ] โทนข้อความ empty/error ไปทิศทางเดียวกัน (เป็นมิตร + action-oriented)
- [ ] ข้อความเป็นข้อความจริง ไม่ใช่ placeholder "lorem"
- [ ] icon + spacing + สี มาจาก token เดียวกันทุก state
