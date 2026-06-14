# React Native Convention

ใช้ TypeScript เป็นหลัก (อ่าน universal rules เรื่อง TS ประกอบ) เน้นส่วนที่ต่างจาก React web

> **มาตรฐานทีม: bare / pure React Native เท่านั้น — ห้ามใช้ `expo-*` ทุกกรณี** (โปรเจกต์รัน RN เวอร์ชันใหม่ที่ Expo ตามไม่ทัน) ใช้ community package แทนเสมอ

## โครงสร้างโฟลเดอร์ (feature-first)

```
src/
├── navigation/               navigator + route config
├── screens/
│   └── <feature>/
│       └── <feature>-screen.tsx
├── components/
│   ├── ui/                   primitive ใช้ซ้ำ (Button, Text, Card)
│   └── <feature>/
├── features/
│   └── <feature>/
│       ├── api.ts
│       ├── hooks.ts
│       └── types.ts
├── hooks/                    hook ใช้ร่วมทั้งแอป
├── lib/                      client, util, helper
├── theme/                    color, spacing, typography token
└── assets/
```

## Naming
- ไฟล์: `kebab-case.tsx` → `order-list-screen.tsx`, ชื่อ component `PascalCase`
- screen ลงท้าย `Screen` → `OrderListScreen`
- hook ขึ้นต้น `use` → `useOrderList`

## Component & UI
- function component + hooks เท่านั้น
- ใช้ `StyleSheet.create()` แทน inline style object (กัน rebuild + อ่านง่าย) `[ปรับตามทีม: หรือใช้ NativeWind/styled]`
- อ้าง token สี/spacing จาก `theme/` ไม่ hardcode ค่าซ้ำ
- ใช้ component จาก `components/ui/` ก่อนเขียน primitive ใหม่
- ใช้ `<FlatList>`/`<SectionList>` สำหรับ list ยาว ไม่ใช้ `.map()` ใน `<ScrollView>` (กัน performance พัง)

## State & data
- state ที่ derive ได้ คำนวณตอน render อย่าเก็บซ้ำใน `useState`
- server state ใช้ React Query / SWR ไม่ปั้น cache เองด้วย `useEffect` `[ปรับตามทีม]`
- global state `[ปรับตามทีม: Redux Toolkit / Zustand / Context]` — เลือกตัวเดียวทั้งโปรเจกต์
- ทุก data fetch จัดการครบ loading / error / empty ไม่ใช่แค่ success

## Navigation (React Navigation)
- ตั้ง type ของ route params ให้ครบ (typed navigation) ไม่ส่ง param แบบ untyped
- รวม navigator config ไว้ที่ `navigation/` ไม่กระจาย

## Lifecycle & performance
- cleanup ใน `useEffect` ทุก subscription / listener / timer
- เช็ก mounted ก่อน setState หลัง async (หรือใช้ AbortController / cleanup flag)
- `useCallback`/`useMemo` เฉพาะที่จำเป็นจริง (prop ของ memoized child, dependency ของ effect) ไม่ใส่พร่ำเพรื่อ
- รูป/asset ใหญ่ใช้ caching library ไม่โหลดซ้ำ

## Platform-specific
- โค้ดเฉพาะ OS ใช้ `Platform.select()` หรือไฟล์ `.ios.tsx` / `.android.tsx`
- เผื่อ safe area (notch/home indicator) ด้วย `SafeAreaView` / insets
- ทดสอบทั้ง iOS และ Android ก่อนถือว่าเสร็จ

## Environment / security
- secret ไม่ฝังใน bundle (bundle ถอดได้) — ของลับให้อยู่ฝั่ง backend
- base URL / key อ่านจาก config ตาม environment ด้วย `react-native-config` (ไม่ใช้ expo-constants)

## Scaffold screen/feature ใหม่ — checklist
1. สร้าง `screens/<feature>/<feature>-screen.tsx` + ลงทะเบียนใน `navigation/`
2. logic เฉพาะ feature อยู่ใน `features/<feature>/` (api, hooks, types)
3. component ใช้ซ้ำ → `components/ui/`, เฉพาะ feature → `components/<feature>/`
4. ใช้ `StyleSheet` + token จาก `theme/`
5. list ยาวใช้ `FlatList`, จัดการ loading/error/empty ครบ
6. cleanup async/subscription, ทดสอบทั้งสอง platform