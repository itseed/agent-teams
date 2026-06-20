# Design Tokens — scales + output format

## โครงสร้าง 2 ชั้น

1. **Primitive tokens** — ค่าดิบ ไม่มีความหมายเชิงใช้งาน: `blue-500`, `gray-100`, `space-4`, `text-lg`
2. **Semantic tokens** — ความหมายเชิงใช้งาน อ้าง primitive อีกที: `color-primary`, `color-surface`, `color-text-primary`, `color-text-muted`, `color-border`, `color-danger`

> **component อ้าง semantic เท่านั้น** — เปลี่ยน theme/brand = แก้ที่ semantic mapping ชั้นเดียว ไม่ต้องแตะ component

## Scales (ใช้ step ไม่ใช่ค่าสุ่ม)

| Token | Scale แนะนำ |
|-------|-------------|
| **Spacing** | 0, 2, 4, 8, 12, 16, 20, 24, 32, 40, 48, 64 (px) — base 4 |
| **Type size** | xs 12 / sm 14 / base 16 / lg 18 / xl 20 / 2xl 24 / 3xl 30 / 4xl 36 |
| **Font weight** | regular 400 / medium 500 / semibold 600 / bold 700 |
| **Line height** | tight 1.2 / normal 1.5 / relaxed 1.7 |
| **Radius** | sm 4 / md 8 / lg 12 / xl 16 / 2xl 24 / full 9999 |
| **Shadow** | sm / md / lg / xl (เพิ่ม elevation เป็นชุด ไม่สุ่มค่า) |
| **Motion** | fast 120ms / base 200ms / slow 320ms + easing มาตรฐาน |
| **Color** | แต่ละสีมี scale 50–950 (primitive) แล้ว map เป็น semantic |

## Naming convention

เลือก **แบบเดียว** แล้วยึดทั้งระบบ:
- CSS var: `--color-text-primary`, `--space-4`, `--radius-md`
- JS/TS object: `color.text.primary`, `space[4]`, `radius.md`

ห้ามปนสไตล์ (บางที่ camelCase บางที่ kebab) — สับสนตอน implement

## Output format ตาม stack

### CSS variables (web ทั่วไป)
```css
:root {
  /* primitive */
  --blue-500: #3b82f6;
  --gray-100: #f3f4f6;
  --space-4: 1rem;
  --radius-md: 0.5rem;
  /* semantic */
  --color-primary: var(--blue-500);
  --color-surface: #ffffff;
  --color-text-primary: #111827;
  --color-text-muted: #6b7280;
  --color-border: var(--gray-100);
}
```

### Tailwind (extend theme — map เข้า semantic)
```js
// tailwind.config.js
theme: {
  extend: {
    colors: {
      primary: 'var(--color-primary)',
      surface: 'var(--color-surface)',
      'text-muted': 'var(--color-text-muted)',
    },
    borderRadius: { md: 'var(--radius-md)' },
  },
}
```

### Flutter (ThemeData + extension)
```dart
// ใช้ ThemeExtension สำหรับ semantic token ที่ไม่อยู่ใน ColorScheme มาตรฐาน
final colorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF3B82F6));
// spacing/radius เป็น const ในคลาส AppSpacing / AppRadius
```

### React Native
- token เป็น TS object กลาง (`theme.ts`) import ใช้ทุกที่ — ไม่ hardcode style ใน component
- ใช้ `StyleSheet.create` อ้าง token; ระวัง platform diff (shadow iOS vs elevation Android)

## W3C DTCG (ถ้าต้อง interop กับ Figma/Style Dictionary)
รองรับ format มาตรฐาน `{ "$type": "color", "$value": "#3b82f6" }` เมื่อโปรเจกต์ใช้ Style Dictionary / Tokens Studio — ช่วย sync Figma ↔ code

## กฎ
- ทุกค่าใน UI ต้องมาจาก token — เจอ magic number (`margin: 13px`, `#4a4a4a`) = แก้ให้อ้าง token
- เพิ่ม token ใหม่เฉพาะเมื่อจำเป็น — ก่อนเพิ่ม เช็กว่ามี token ใกล้เคียงใช้แทนได้ไหม (กัน token บวม)
