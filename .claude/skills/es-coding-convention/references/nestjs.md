# NestJS Convention

## โครงสร้างโฟลเดอร์ (feature-based)

จัดตาม feature module ไม่ใช่ตาม type ของไฟล์

```
src/
├── modules/
│   └── <feature>/                 เช่น order/, user/, payment/
│       ├── <feature>.module.ts
│       ├── <feature>.controller.ts
│       ├── <feature>.service.ts
│       ├── dto/
│       │   ├── create-<feature>.dto.ts
│       │   └── update-<feature>.dto.ts
│       ├── entities/
│       │   └── <feature>.entity.ts
│       └── <feature>.service.spec.ts
├── common/                        guard, interceptor, filter, decorator ที่ใช้ร่วม
├── config/                        config module + validation
└── main.ts
```

## Naming ไฟล์
- ตามแบบ NestJS: `<name>.<type>.ts` → `order.service.ts`, `create-order.dto.ts`, `auth.guard.ts`
- ชื่อ class ตรงกับไฟล์: `OrderService`, `CreateOrderDto`, `AuthGuard`

## Layering — ห้ามข้าม
- **Controller** → รับ request, validate (ผ่าน DTO), เรียก service, return ไม่มี business logic
- **Service** → business logic ทั้งหมด อยู่ตรงนี้
- **Repository / ORM** → data access เท่านั้น
- Controller ห้ามแตะ DB ตรง ๆ, Service ห้ามรู้จัก `Request`/`Response` ของ HTTP

## DTO & Validation
- ทุก input มี DTO + class-validator decorator (`@IsString()`, `@IsNotEmpty()`, `@IsEmail()` ฯลฯ)
- เปิด global `ValidationPipe({ whitelist: true, transform: true })` ใน `main.ts`
- response ใช้ DTO/serializer แยก ไม่คืน entity ดิบ (กัน field ที่ไม่ตั้งใจหลุด เช่น password hash)

## Database / ORM `[ปรับตามทีม: TypeORM หรือ Prisma]`

**ถ้า TypeORM:**
- relation ที่ดึงบ่อยใช้ `relations: []` หรือ query builder กัน N+1
- operation หลายตารางครอบด้วย `dataSource.transaction()` หรือ `QueryRunner`
- migration ทุกครั้งที่ schema เปลี่ยน ไม่ใช้ `synchronize: true` บน prod

**ถ้า Prisma:**
- ใช้ `include`/`select` ให้พอดี ไม่ over-fetch
- หลายเขียนพร้อมกันใช้ `prisma.$transaction([])`
- `prisma migrate` ทุกครั้งที่ schema เปลี่ยน

## Error handling
- ใช้ NestJS exception: `BadRequestException`, `NotFoundException`, `UnauthorizedException` ฯลฯ
- มี global exception filter จัดรูป error response ให้ consistent `[ปรับตามทีม: error response shape]`
- ไม่ throw string ดิบ ไม่ปล่อย DB error ดิบขึ้นไปถึง client

## Config
- ใช้ `@nestjs/config` + validation schema (Joi / class-validator) ตอน startup
- อ่านค่าผ่าน `ConfigService` ไม่ใช่ `process.env` กระจายทั่วโค้ด

## API Contract (contract-first — บังคับเมื่อมี consumer อื่นรอ)

ถ้า endpoint ใหม่มี frontend/mobile รอใช้ (งาน parallel) ต้อง **เขียน `docs/contracts/<api>.md` ก่อนลงมือ implement** แล้วแจ้ง Lead — consumer จะ code ตาม contract นี้ ไม่ใช่เดา shape เอง:
- request/response shape จริง (field, type, nullability) + ตัวอย่าง JSON
- error format + status code ต่อ case
- env var names ที่ consumer ต้องตั้ง (เช่น base URL)
- template: `templates/contract-template.md` ของ repo agent-teams (ถ้า Lead copy มาไว้ใน project)
- implement เสร็จแล้ว shape เปลี่ยนจาก contract → ต้องอัปเดต contract + แจ้ง Lead ทันที

## Scaffold module ใหม่ — checklist
1. สร้างโฟลเดอร์ `modules/<feature>/` ตามโครงด้านบน
2. ถ้ามี consumer อื่นรอ endpoint นี้ → เขียน `docs/contracts/<api>.md` ก่อน (ดูหัวข้อ API Contract)
3. `<feature>.module.ts` declare controller + service + import ที่จำเป็น แล้ว register ใน `AppModule`
4. DTO พร้อม validation ครบทั้ง create/update
5. entity + migration
6. service เขียน business logic + `.spec.ts` คู่กัน
7. controller บาง ๆ map route → service