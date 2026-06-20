# Theming — light / dark / brand

## หลักการ

Theme เปลี่ยนได้โดย **ไม่แตะ component** — เพราะ component อ้าง **semantic token** เท่านั้น
สลับ theme = สลับ mapping ของ semantic → primitive ชั้นเดียว

```
component → semantic token → primitive token (สลับตาม theme)
```

## Light / Dark

- นิยาม semantic token ชุดเดียว แล้วให้ค่าต่างกันต่อ theme:
```css
:root {                      /* light */
  --color-surface: #ffffff;
  --color-text-primary: #111827;
  --color-text-muted: #6b7280;
  --color-border: #e5e7eb;
}
[data-theme="dark"] {        /* dark */
  --color-surface: #0f172a;
  --color-text-primary: #f1f5f9;
  --color-text-muted: #94a3b8;
  --color-border: #1e293b;
}
```
- **dark ≠ invert** — ปรับ contrast/elevation ให้เหมาะ (dark ใช้ surface สว่างขึ้นแทน shadow เพื่อสื่อ elevation)
- ทดสอบ contrast ทั้งสอง theme (ดู a11y.md) — สีที่ผ่านใน light อาจไม่ผ่านใน dark
- เคารพ `prefers-color-scheme` เป็นค่าเริ่มต้น + ให้ผู้ใช้ override ได้

## Brand / multi-tenant
- ถ้าหลาย brand: แยก **brand token** (primary color, logo, radius) ออกจาก structural token (spacing, type scale ที่ใช้ร่วม)
- โหลด brand override เป็น CSS var set ต่อ tenant — component ไม่รู้เรื่อง brand

## Stack notes
- **Tailwind** — `darkMode: 'class'` หรือ `[data-theme]`; semantic color ชี้ไป CSS var เพื่อสลับได้
- **Flutter** — `ThemeData.light()` / `.dark()` + `ThemeExtension` สำหรับ semantic token นอก ColorScheme
- **React Native** — context theme provider จ่าย token object; `useColorScheme()` อ่าน system preference

## Checklist
- [ ] component ไม่อ้างสีดิบ/primitive — อ้าง semantic เท่านั้น
- [ ] ทุก semantic token มีค่าครบทั้ง light + dark (ถ้ารองรับ dark)
- [ ] contrast ผ่านทั้งสอง theme
- [ ] เคารพ system preference + override ได้
