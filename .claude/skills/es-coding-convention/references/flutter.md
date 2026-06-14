# Flutter Convention

## โครงสร้างโฟลเดอร์ (feature-first)

```
lib/
├── main.dart
├── core/                     ของกลางทั้งแอป
│   ├── theme/
│   ├── network/              dio/http client, interceptor
│   ├── router/
│   └── utils/
├── features/
│   └── <feature>/
│       ├── data/             model, repository, data source
│       ├── domain/           entity, usecase  [ปรับตามทีม: ถ้าใช้ clean architecture]
│       └── presentation/
│           ├── pages/
│           ├── widgets/
│           └── <feature>_<state>.dart   (provider/bloc/controller)
└── shared/                   widget ใช้ซ้ำข้าม feature
```

## Naming
- ไฟล์: `snake_case.dart` → `order_list_page.dart`
- class: `PascalCase` → `OrderListPage`
- ตัวแปร/ฟังก์ชัน: `camelCase`
- private ขึ้นต้น `_`

## State management `[ปรับตามทีม: Provider / Riverpod / Bloc / GetX]`
- เลือกตัวเดียวทั้งโปรเจกต์ ไม่ปน
- แยก business logic ออกจาก widget — widget ควรบางและเน้นแสดงผล
- ทุก async state ครอบ loading / data / error ให้ครบ

## Widget
- แตก widget ย่อยเมื่อ build method ยาวเกินไป อย่ายัด tree ลึกในไฟล์เดียว
- ใช้ `const` constructor ทุกที่ที่ทำได้ (ลด rebuild)
- แยก widget ที่ใช้ซ้ำเป็น component ใน `shared/` หรือ `widgets/`

## Lifecycle & ความปลอดภัย
- `dispose()` ทุก controller / `StreamSubscription` / `AnimationController` กัน memory leak
- เช็ก `if (!mounted) return;` ก่อน `setState` หลัง await
- async ใน UI ใช้ `FutureBuilder` / `StreamBuilder` ไม่ block main thread

## Network / model
- model มี `fromJson` / `toJson` ชัดเจน `[ปรับตามทีม: เขียนเอง หรือ json_serializable / freezed]`
- error จาก network แปลงเป็น error type ของแอป ไม่โยน exception ดิบขึ้น UI
- base URL / API key อ่านจาก config ตาม environment ไม่ hardcode

## Scaffold feature ใหม่ — checklist
1. สร้าง `features/<feature>/` ตามชั้น data/presentation (+domain ถ้าใช้)
2. model + repository ในชั้น data
3. state holder (provider/bloc/controller) แยกจาก widget
4. page + widgets ในชั้น presentation จัดการ loading/error/empty ครบ
5. `dispose` ทรัพยากรครบ