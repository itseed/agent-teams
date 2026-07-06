---
name: es-code-review
description: ใช้เมื่อต้อง review โค้ดก่อน merge — ตรวจ diff/PR, ประเมินว่าโค้ดปลอดภัย/ดีพอจะ merge ไหม, หรือเมื่อ reviewer agent ได้รับงานตรวจโค้ด แม้ผู้ใช้พูดแค่ "ดู PR นี้ให้หน่อย" หรือ "โค้ดนี้ใช้ได้ยัง" ครอบคลุม stack NestJS / Next.js / Flutter / React Native / LINE LIFF / PostgreSQL
---

# Code Review

Review โค้ดอย่างเป็นระบบตามมาตรฐานทีม ผลลัพธ์คือรายการ finding ที่จัด severity ชัดเจน
พร้อม verdict สุดท้ายว่าควร merge หรือไม่ — ไม่ใช่แค่ "ดูดีแล้ว"

## เป้าหมาย

หา issue ที่ "สำคัญจริง" ไม่ใช่จับผิดทุกบรรทัด reviewer ที่ดีคือ filter ไม่ใช่ linter
ถ้า ESLint/Prettier จับได้อยู่แล้ว ไม่ต้องพูดถึง โฟกัสที่สิ่งที่เครื่องมือ auto จับไม่ได้:
ตรรกะผิด, ช่องโหว่ security, ปัญหา performance ที่จะโผล่ตอน production, และ pattern ที่ทีมตกลงกันไว้

## ขั้นตอน

1. **เข้าใจ context ก่อน** — อ่าน PR description / commit message ว่าตั้งใจแก้อะไร
   ดู diff ทั้งหมดก่อน แล้วค่อยลงรายละเอียดทีละไฟล์ อย่า review โดยไม่รู้ว่าโค้ดนี้ควรทำอะไร
2. **เลือก checklist ตาม stack** ของไฟล์ที่แก้ (ดูหัวข้อด้านล่าง)
3. **ไล่ตาม 5 มิติ** — security → correctness → performance → convention → tests
4. **จัด severity ทุก finding** แล้วสรุป verdict

## Severity levels

- **🔴 Blocker** — merge ไม่ได้: ช่องโหว่ security, data loss, ตรรกะผิดที่กระทบ business, secret หลุด
- **🟠 Major** — ควรแก้ก่อน merge: performance ที่จะพังตอน scale, error handling ขาด, edge case สำคัญ
- **🟡 Minor** — แก้ได้ใน PR ถัดไป: naming, โครงสร้างที่ปรับให้ดีขึ้นได้, missing test ที่ไม่ critical
- **⚪ Nit** — ความเห็นส่วนตัว ไม่บังคับ

## มิติที่ต้องตรวจ (ทุก stack)

**Security** — สำหรับ diff ที่แตะ auth / data access / input / upload / external call ให้ **โหลด `references/security.md` แล้วไล่ OWASP Top 10 ให้ครบ** (ไฟล์นี้คือ quick check; รายละเอียด IDOR, XSS, mass assignment, SSRF, JWT, password hashing ฯลฯ อยู่ในนั้น)
- Input ที่มาจาก user ถูก validate/sanitize ก่อนใช้ไหม (โดยเฉพาะที่ลง DB หรือขึ้นจอ)
- มี secret / API key / token hardcode ในโค้ดหรือ commit ไหม → ต้องอยู่ใน env เท่านั้น
- Endpoint ที่ควรมี auth guard มีครบไหม ระดับ permission ถูกต้องไหม + **ตรวจ object-level (IDOR)**: resource เป็นของ user ที่ login จริงไหม
- ข้อมูล sensitive โดน log ออกมาโดยไม่ตั้งใจไหม
- finding ด้าน security ที่ยังไม่แก้ = 🔴 Blocker เสมอ

**Correctness**
- Error handling: throw/catch ครบ, ไม่ swallow error เงียบ ๆ, return ค่าถูกตอน fail
- Null / undefined / empty array ถูกจัดการไหม
- Async: await ครบทุก promise, ไม่มี race condition, ไม่ floating promise
- Edge case ที่ PR นี้ "ควร" รองรับตาม description ครบไหม

**Performance**
- Query ใน loop (N+1) — รวมเป็น query เดียว / ใช้ join / eager load แทน
- มี pagination สำหรับ list ที่อาจโตเรื่อย ๆ ไหม
- คำนวณซ้ำที่ cache ได้, หรือ work หนักที่ควรย้ายไป background job

**Convention** — สอดคล้องกับโค้ดเดิมในโปรเจกต์ (อ้าง CLAUDE.md ของ repo ถ้ามี)

**Tests**
- Logic ใหม่ที่ไม่ trivial มี test ครอบคลุมไหม โดยเฉพาะ branch ของ error/edge case
- ไม่ใช่แค่ test happy path

## Checklist เฉพาะ stack

### NestJS (backend)
- DTO มี class-validator decorator ครบ และเปิด `ValidationPipe` แล้ว
- Query ผ่าน ORM ระวัง N+1 — relation ที่ใช้บ่อยควร eager load หรือใช้ query builder รวบให้
- Transaction: operation ที่แก้หลายตารางพร้อมกันต้องอยู่ใน transaction เดียว
- ใช้ raw query เมื่อใด ต้อง parameterized เสมอ (กัน SQL injection)
- Exception ใช้ NestJS built-in (`BadRequestException` ฯลฯ) ไม่ throw string ดิบ
- Config/secret อ่านผ่าน `ConfigService` ไม่ใช่ `process.env` ตรง ๆ กระจัดกระจาย

### Next.js / TypeScript (frontend)
- ไม่มี secret ฝั่ง client — ตัวแปร `NEXT_PUBLIC_*` ถือว่า public ทั้งหมด
- `useEffect` มี dependency array ครบ, มี cleanup ถ้าจำเป็น, ไม่ยิง fetch ซ้ำไม่จบ
- State ที่ derive ได้ อย่าเก็บซ้ำใน state แยก (source of truth เดียว)
- จัดการ loading / error / empty state ของทุก data fetch ไม่ใช่แค่ success
- `any` ที่หลีกเลี่ยงได้ควรเลี่ยง — type ให้ตรง
- key ของ list ใช้ค่า stable ไม่ใช่ index

### Flutter (mobile)
- `dispose()` controller / stream / animation ครบ กัน memory leak
- `setState` ไม่ถูกเรียกหลัง widget unmount (`if (!mounted) return`)
- async ใน build tree จัดการด้วย `FutureBuilder`/`StreamBuilder` ไม่ block UI thread
- รองรับ loading/error state บนจอจริง ไม่ใช่ค้างหน้าขาว

### React Native (mobile — bare/pure RN เท่านั้น)
- ไม่มี `expo-*` ใน dependency ใหม่ — ทีมยึด bare RN + community packages เท่านั้น (finding = 🔴 Blocker)
- List ยาวใช้ `FlatList`/`SectionList` (ไม่ map ใน `ScrollView`), item มี stable `keyExtractor`
- Secret/token เก็บใน Keychain/Keystore (เช่น react-native-keychain) ไม่ใช่ AsyncStorage; ไม่มี secret ฝัง JS bundle
- Effect/subscription/listener (AppState, Linking, event emitter) มี cleanup ครบ กัน leak หลัง unmount
- Handler ที่ส่งเข้า list item ระวัง re-render ทั้ง list — ใช้ `useCallback`/`memo` เมื่อ list ใหญ่จริง
- จัดการ loading/error/empty state ครบ และ error จาก native module ไม่ swallow เงียบ

### LINE LIFF
- เช็ก `liff.isLoggedIn()` ก่อนเรียก API ที่ต้องใช้ profile
- ID token / access token ต้อง verify ฝั่ง backend ก่อนเชื่อถือ ไม่ trust ค่าจาก client
- ระวัง redirect / login loop — อย่าเรียก `liff.login()` ซ้ำใน flow ที่ login อยู่แล้ว
- แยก LIFF ID ของแต่ละ environment (dev/uat/prod) ชัดเจน ไม่ปนกัน

## รูปแบบผลลัพธ์

```
## Code Review: <PR title / scope>

**Verdict:** ✅ Approve | 🔄 Request changes | ⛔ Block

### 🔴 Blockers
- `path/to/file.ts:42` — <ปัญหา> → <วิธีแก้ที่เสนอ>

### 🟠 Major
- `path/to/file.ts:88` — ...

### 🟡 Minor / ⚪ Nits
- ...

### ✅ จุดที่ทำได้ดี
- <ชมเฉพาะที่ควรชมจริง ๆ — สั้น ๆ>
```

หลักการเขียน finding: ระบุ **ไฟล์:บรรทัด → ปัญหาคืออะไร → ทำไมถึงเป็นปัญหา → แก้ยังไง**
ถ้าไม่มี Blocker/Major เลย ให้ Approve ตรง ๆ ไม่ต้องเค้นหา Minor มาเติมให้ดูขยัน
