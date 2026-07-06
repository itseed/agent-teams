# Test Checklist เฉพาะ stack

โหลดเฉพาะ section ของ stack ที่กำลังประเมิน

## NestJS (backend) — Jest
- Service: mock repository/dependency, เทส business logic + error path (throw exception ถูกชนิดไหม)
- Controller/e2e: ใช้ `supertest` ยิง endpoint จริง — เช็ก status code, response shape, auth guard ทำงาน
- Validation: ส่ง payload ผิด → ต้องได้ 400 ไม่ใช่หลุดเข้า logic
- DB integration: ใช้ test database/transaction rollback อย่า mock จน query จริงไม่เคยรัน
- Async/transaction: เทสว่า rollback จริงเมื่อ step กลางพัง

## Next.js / TypeScript (frontend) — Jest + React Testing Library / Playwright
- เทสจากมุม user: query ด้วย role/text ที่ผู้ใช้เห็น ไม่ใช่ class/test-id ภายใน
- Data fetch: เทสครบ loading / error / empty / success — ไม่ใช่แค่ success
- Form: validation error, submit สำเร็จ, disable ปุ่มตอน submitting
- E2E (Playwright): critical flow จริงบน browser — verify ผ่าน UI ที่ user เห็น
- อย่าเทส implementation (state ภายใน) — เทส output ที่ render ออกมา

## Flutter (mobile) — flutter_test
- Widget test: pump widget, หา element ด้วย finder, เช็ก state เปลี่ยนตาม interaction
- เทส loading/error/empty state บนจอ ไม่ใช่แค่ happy path
- Logic ล้วน (provider/bloc/cubit) แยกเทสเป็น unit ไม่ต้องผ่าน widget
- Golden test เฉพาะ component ที่ layout สำคัญจริง (ระวัง flaky ข้าม platform)

## React Native (mobile) — Jest + React Native Testing Library
- ใช้ `@testing-library/react-native` — query ด้วย `getByText`/`getByRole`/`getByTestId` (เทสจากมุม user ไม่ใช่ state ภายใน)
- Logic ล้วน (hook/store/reducer/util) แยกเทสเป็น unit ไม่ต้องผ่าน component
- Data fetch / async: เทสครบ loading / error / empty / success — ใช้ `waitFor`/`findBy*` รอ element แทน `setTimeout` (กัน flaky)
- Mock native module ที่ JS env ไม่มี (เช่น MMKV, Keychain, permissions, push) ใน `jest.setup.js` — อย่าให้ test แตะ native จริง
- Navigation (React Navigation): wrap ด้วย `NavigationContainer` ตอน render, เทสว่า navigate ไปจอถูกตาม action
- E2E flow จริงบน device/emulator ใช้ **Detox หรือ Maestro** เฉพาะ critical path (login, ชำระเงิน, submit หลัก) — ไม่ครอบทุก permutation
- ⚠️ ห้ามใช้ `expo-*` ถ้าโปรเจกต์เป็น pure RN — mock/util ต้องเป็น community package ให้ตรง runtime จริง

## LINE LIFF
- Mock `liff` object — เทส flow ตอน `isLoggedIn()` true/false
- เทสว่า token ถูกส่งไป verify ฝั่ง backend ไม่ใช่ trust ดิบ
- เทส redirect/login loop ไม่เกิดซ้ำ
