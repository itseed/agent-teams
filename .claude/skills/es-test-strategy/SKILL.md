---
name: es-test-strategy
description: ใช้เมื่อต้องวางแผนหรือประเมิน test ของ feature ก่อนเข้า review — ตัดสินใจว่าควรเขียน test ระดับไหน (unit/integration/e2e), หา test ที่ขาด, ตรวจว่า coverage พอ "ปล่อยได้" ไหม, หรือเมื่อ qa agent ได้รับงานทดสอบ แม้ผู้ใช้พูดแค่ "เทสครอบหรือยัง" หรือ "feature นี้ปล่อยได้ยัง" ครอบคลุม stack NestJS / Next.js / Flutter / React Native / LINE LIFF
---

# Test Strategy

วาง test ให้ "คุ้มค่าต่อความมั่นใจ" ไม่ใช่ไล่ปั๊ม coverage ให้ตัวเลขสวย
ผลลัพธ์คือ: รู้ว่าควรเทสระดับไหน, อะไรที่ "ต้องมี" test, และ verdict ว่า feature นี้ปล่อยได้หรือยัง

## เป้าหมาย

test ที่ดีคือ test ที่จะ **fail ตอนโค้ดพัง** และ **pass ตอนโค้ดถูก** — ไม่ใช่ test ที่เขียนเพื่อให้ coverage ขึ้น
โฟกัสที่ behavior และ business rule ไม่ใช่ implementation detail (test ที่ต้องแก้ทุกครั้งที่ refactor = test ที่ผูกกับ detail มากไป)

## เลือกระดับ test (Test Pyramid)

จากเร็ว/ถูก/เยอะ → ช้า/แพง/น้อย:

- **Unit** — logic ล้วน ๆ ที่แยกออกมาได้: คำนวณ, validation, transform, business rule ที่มี branch เยอะ
  → เขียนเยอะที่สุด ครอบ edge case/branch ตรงนี้
- **Integration** — หลาย unit ทำงานร่วมกัน + I/O จริงบางส่วน: service + DB, API endpoint + validation pipe, repository + query
  → ครอบ "ต่อกันแล้วยังถูกไหม" และ contract ระหว่างชั้น
- **E2E** — flow ของ user จริงทั้งเส้น: login → ทำงาน → เห็นผล
  → เขียนเฉพาะ **critical path** (เส้นที่พังแล้วเจ็บที่สุด) ไม่ต้องครอบทุก permutation

**กฎ**: edge case ดันลงไปเทสที่ระดับต่ำสุดที่ทำได้ — อย่าเทส 10 branch ผ่าน e2e ที่ช้าและเปราะ

## "ต้องมี" test เมื่อไหร่

- Logic ที่มี branch / เงื่อนไข (if/else, switch, guard) → unit ครอบทุก branch รวม error path
- Business rule ที่ผิดแล้วกระทบเงิน/สิทธิ์/ข้อมูล → integration หรือ unit ที่ชัดเจน
- Bug ที่เพิ่งแก้ → เขียน regression test ที่ **fail ก่อนแก้ / pass หลังแก้** เสมอ
- Critical user flow (auth, ชำระเงิน, submit form หลัก) → e2e อย่างน้อย 1 happy + 1 fail
- ❌ ไม่ต้องเทส: getter/setter เปล่า, config object, code ที่ framework การันตีให้แล้ว

## ประเมิน gap (severity)

- **🔴 Blocker** — critical path ไม่มี test เลย / business rule ที่กระทบเงิน-สิทธิ์ ไม่ถูกครอบ / regression ของ bug ที่เพิ่งแก้หายไป
- **🟠 Major** — error & edge branch สำคัญไม่ถูกเทส (เทสแต่ happy path), integration ระหว่างชั้นหลักขาด
- **🟡 Minor** — branch ปลายแถวที่โอกาสเกิดน้อยยังไม่ครอบ, test ชื่อไม่สื่อ
- **⚪ Nit** — จัดระเบียบ/ตั้งชื่อ test ให้อ่านง่ายขึ้น

อย่าดูแค่ % coverage — โค้ด 90% ที่เทสแต่ happy path แย่กว่า 60% ที่ครอบ error path ครบ

## Checklist เฉพาะ stack

### NestJS (backend) — Jest
- Service: mock repository/dependency, เทส business logic + error path (throw exception ถูกชนิดไหม)
- Controller/e2e: ใช้ `supertest` ยิง endpoint จริง — เช็ก status code, response shape, auth guard ทำงาน
- Validation: ส่ง payload ผิด → ต้องได้ 400 ไม่ใช่หลุดเข้า logic
- DB integration: ใช้ test database/transaction rollback อย่า mock จน query จริงไม่เคยรัน
- Async/transaction: เทสว่า rollback จริงเมื่อ step กลางพัง

### Next.js / TypeScript (frontend) — Jest + React Testing Library / Playwright
- เทสจากมุม user: query ด้วย role/text ที่ผู้ใช้เห็น ไม่ใช่ class/test-id ภายใน
- Data fetch: เทสครบ loading / error / empty / success — ไม่ใช่แค่ success
- Form: validation error, submit สำเร็จ, disable ปุ่มตอน submitting
- E2E (Playwright): critical flow จริงบน browser — verify ผ่าน UI ที่ user เห็น
- อย่าเทส implementation (state ภายใน) — เทส output ที่ render ออกมา

### Flutter (mobile) — flutter_test
- Widget test: pump widget, หา element ด้วย finder, เช็ก state เปลี่ยนตาม interaction
- เทส loading/error/empty state บนจอ ไม่ใช่แค่ happy path
- Logic ล้วน (provider/bloc/cubit) แยกเทสเป็น unit ไม่ต้องผ่าน widget
- Golden test เฉพาะ component ที่ layout สำคัญจริง (ระวัง flaky ข้าม platform)

### React Native (mobile) — Jest + React Native Testing Library
- ใช้ `@testing-library/react-native` — query ด้วย `getByText`/`getByRole`/`getByTestId` (เทสจากมุม user ไม่ใช่ state ภายใน)
- Logic ล้วน (hook/store/reducer/util) แยกเทสเป็น unit ไม่ต้องผ่าน component
- Data fetch / async: เทสครบ loading / error / empty / success — ใช้ `waitFor`/`findBy*` รอ element แทน `setTimeout` (กัน flaky)
- Mock native module ที่ JS env ไม่มี (เช่น MMKV, Keychain, permissions, push) ใน `jest.setup.js` — อย่าให้ test แตะ native จริง
- Navigation (React Navigation): wrap ด้วย `NavigationContainer` ตอน render, เทสว่า navigate ไปจอถูกตาม action
- E2E flow จริงบน device/emulator ใช้ **Detox หรือ Maestro** เฉพาะ critical path (login, ชำระเงิน, submit หลัก) — ไม่ครอบทุก permutation
- ⚠️ ห้ามใช้ `expo-*` ถ้าโปรเจกต์เป็น pure RN — mock/util ต้องเป็น community package ให้ตรง runtime จริง

### LINE LIFF
- Mock `liff` object — เทส flow ตอน `isLoggedIn()` true/false
- เทสว่า token ถูกส่งไป verify ฝั่ง backend ไม่ใช่ trust ดิบ
- เทส redirect/login loop ไม่เกิดซ้ำ

## Anti-pattern ที่ต้องจับ

- Test ไม่มี assertion จริง (รันผ่านแต่ไม่เช็กอะไร)
- Mock ทุกอย่างจน test ไม่เคยแตะโค้ดจริง
- Test ผูกกับเวลา/ลำดับ/network จริง → flaky (ใช้ condition-based waiting ไม่ใช่ `sleep`)
- เทสแต่ happy path แล้วเคลม "ครอบแล้ว"
- Snapshot ใหญ่ ๆ ที่ไม่มีใครอ่าน — เปลี่ยนนิดเดียวต้อง update ทั้งก้อน

## รูปแบบผลลัพธ์

```
## Test Strategy: <feature / PR scope>

**Verdict:** ✅ ปล่อยได้ | 🔄 ต้องเพิ่ม test ก่อน | ⛔ Block (critical path ไม่มี test)

### 🔴 Gap ที่ต้องปิดก่อน merge
- <ระดับ test> `path` — <ควรเทสอะไร> เพราะ <พังแล้วกระทบอะไร>

### 🟠 ควรเพิ่ม
- ...

### ✅ ที่ครอบแล้วดีอยู่
- <สั้น ๆ — happy path X, error path Y>

### สรุประดับที่แนะนำ
- Unit: ... | Integration: ... | E2E: ...
```

หลักการเขียน gap: ระบุ **ระดับ test → เคสที่ขาด → พังแล้วกระทบอะไร** เพื่อให้คนแก้รู้ว่าทำไมต้องเทส ไม่ใช่แค่ "coverage ต่ำ"
ถ้า critical path + error path ครบแล้ว ปล่อยได้เลย ไม่ต้องเค้น test ปลายแถวมาเติมให้ดูเยอะ
