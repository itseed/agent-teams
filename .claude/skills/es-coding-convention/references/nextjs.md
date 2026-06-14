# Next.js / React Convention

## โครงสร้างโฟลเดอร์ `[ปรับตามทีม: App Router หรือ Pages Router]`

ตัวอย่างฝั่ง App Router:

```
src/
├── app/                      route (App Router)
│   └── <route>/
│       ├── page.tsx
│       ├── layout.tsx
│       └── loading.tsx
├── components/
│   ├── ui/                   primitive ใช้ซ้ำ (Button, Input, Modal)
│   └── <feature>/            component เฉพาะ feature
├── features/                 logic + hook + api ต่อ feature
│   └── <feature>/
│       ├── api.ts
│       ├── hooks.ts
│       └── types.ts
├── lib/                      util, client, helper กลาง
├── hooks/                    hook ใช้ร่วมทั้งแอป
└── styles/
```

## Naming
- ไฟล์ component: `kebab-case.tsx` แต่ชื่อ component ข้างใน `PascalCase`
  (เช่น ไฟล์ `order-card.tsx` → `export function OrderCard()`)  `[ปรับตามทีม: บางทีมใช้ PascalCase.tsx]`
- hook ขึ้นต้น `use` เสมอ → `useOrderList`
- 1 component หลักต่อ 1 ไฟล์

## Component
- function component + hooks เท่านั้น ไม่ใช้ class component
- แยก presentational (รับ props, แสดงผล) ออกจาก container (จัดการ data/state) เมื่อเริ่มซับซ้อน
- props มี type ชัดเจน ไม่ใช้ `any`
- component ใหญ่เกินไปให้แตกย่อย ไม่ยัดทุกอย่างในไฟล์เดียว

## State & data
- state ที่ derive ได้ คำนวณตอน render อย่าเก็บซ้ำใน `useState`
- server state ใช้ data-fetching library (React Query / SWR) ไม่ปั้น loading/cache เองด้วย `useEffect` `[ปรับตามทีม]`
- ทุก data fetch จัดการครบ 3 สถานะ: loading / error / empty ไม่ใช่แค่ success
- `useEffect` dependency array ครบ มี cleanup เมื่อจำเป็น

## Environment / security
- ตัวแปรที่ขึ้นต้น `NEXT_PUBLIC_*` = public ทั้งหมด ห้ามใส่ secret
- เรียก external API ที่ต้องใช้ secret ผ่าน route handler / server action ฝั่ง server เท่านั้น

## Styling `[ปรับตามทีม: Tailwind / CSS Modules / styled-components]`
- เลือกแนวเดียวทั้งโปรเจกต์ ไม่ปนหลายแนว
- ถ้ามี design token (สี/spacing/typography) อ้างจาก token กลาง ไม่ hardcode ค่าซ้ำ

## Scaffold หน้า/feature ใหม่ — checklist
1. สร้าง route ใน `app/<route>/page.tsx`
2. logic เฉพาะ feature อยู่ใน `features/<feature>/` (api, hooks, types)
3. component ที่ใช้ซ้ำได้ → `components/ui/`, เฉพาะ feature → `components/<feature>/`
4. type ของ data shape นิยามไว้ที่เดียว (`types.ts`)
5. จัดการ loading/error/empty state ครบ