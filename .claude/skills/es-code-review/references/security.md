# Security Review Checklist (OWASP-aligned)

โหลดไฟล์นี้ตอนทำ pass **Security** ของ code review — ไล่ตาม OWASP Top 10 + ส่วน stack-specific ด้านล่าง
finding ด้าน security ที่ยังไม่แก้ = **🔴 Blocker** เสมอ (ตามกฎ "security ต้อง confirm ก่อน merge")

> ใช้คู่กับ Snyk scan (dependency vuln) ที่ reviewer รันก่อน manual review — ไฟล์นี้คือส่วน **code-level** ที่ Snyk จับไม่ได้

## A01 — Broken Access Control (เจอบ่อย/อันตรายสุด)
- **IDOR / object-level authz**: endpoint ที่รับ id จาก client (`/orders/:id`, `?userId=`) ต้องเช็คว่า resource นั้น**เป็นของ user ที่ login จริง** ไม่ใช่แค่ "login แล้ว" — ห้ามดึง id ของเหยื่อมาเปิดได้
- ดึง identity จาก **token/session ฝั่ง server** ไม่ใช่จาก query/body ที่ client ส่ง (`@Query('userId')` = ธงแดง)
- ตรวจ role/permission ที่ระดับ resource ไม่ใช่แค่ที่ route — admin endpoint มี guard ครบ
- default deny: ถ้าไม่ระบุสิทธิ์ = ห้าม ไม่ใช่อนุญาต

## A02 — Cryptographic Failures
- password เก็บด้วย **bcrypt / argon2 / scrypt** เท่านั้น — ห้าม md5/sha1/plain, ห้ามเขียน crypto เอง
- token/OTP/reset-key สุ่มด้วย CSPRNG (`crypto.randomBytes`) **ไม่ใช่ `Math.random()`**
- ข้อมูล sensitive (PII, บัตร, token) เข้ารหัสตอน transit (HTTPS) และ at-rest ตามจำเป็น
- ไม่มี secret/key/IV hardcode; ไม่ commit `.env`

## A03 — Injection
- **SQL**: parameterized / prepared statement เสมอ — ห้าม string concat/template ใส่ค่า user (`WHERE id = '${x}'` = ธงแดง)
- **NoSQL / ORM**: ระวัง operator injection (`$where`, object ที่มาจาก body ตรงๆ)
- **Command / path**: ห้ามต่อ input เข้า shell/`exec`; validate path กัน traversal (`../`)
- **XSS (output)**: encode ตาม context ตอน render — ระวัง `dangerouslySetInnerHTML`, `innerHTML`, `v-html`; ถ้าต้อง render HTML จาก user ต้อง sanitize (DOMPurify)

## A04 — Insecure Design
- มี rate limit / lockout บน endpoint ที่ถูก abuse ได้ (login, OTP, reset, ส่ง email/SMS)
- business logic ที่กระทบเงิน/สิทธิ์ คำนวณ + ตรวจฝั่ง server ไม่เชื่อค่าจาก client (เช่น ราคา, total, discount, quantity)
- workflow สำคัญกันการข้ามขั้น (เช่น จ่ายเงินก่อนยืนยัน)

## A05 — Security Misconfiguration
- **CORS** ไม่ตั้ง `origin: *` คู่กับ credentials; allowlist origin จริง
- error ไม่ leak stack trace / SQL / path ภายในถึง client (prod) — มี global exception filter
- security headers (HSTS, X-Content-Type-Options, CSP เท่าที่ทำได้) `[ปรับตามทีม]`
- ไม่เปิด debug/verbose/default credential บน prod; ปิด endpoint dev (swagger ที่ไม่ตั้งใจเปิด)

## A06 — Vulnerable & Outdated Components
- ครอบด้วย Snyk scan แล้ว — ถ้า manual เห็น lib เก่าที่มี CVE รู้จัก ให้ flag เพิ่ม

## A07 — Identification & Authentication Failures
- JWT: ตั้ง `expiresIn`, ระบุ/ตรวจ `algorithm` (กัน `alg: none` / RS↔HS confusion), verify secret ฝั่ง server
- ไม่คืน token/session โดยไม่ตรวจ credential จริง; เทียบ password แบบ constant-time (bcrypt.compare)
- session: หมุน id หลัง login, invalidate ตอน logout, ตั้ง cookie `HttpOnly` + `Secure` + `SameSite`
- มีกัน brute-force (rate limit / backoff) บน login

## A08 — Software & Data Integrity Failures
- **Mass assignment / over-posting**: bind เฉพาะ field ที่อนุญาต (DTO + `whitelist: true`) — กัน user ยัด `isAdmin`, `role`, `userId`
- file upload: ตรวจ type จริง (magic byte ไม่ใช่แค่ extension/MIME ที่ client ส่ง), จำกัดขนาด, เก็บนอก web root, ตั้งชื่อใหม่กัน path traversal
- ไม่ deserialize ข้อมูลที่ไม่เชื่อถือแบบ unsafe

## A09 — Logging & Monitoring Failures
- ไม่ log secret / password / token / PII / เลขบัตร (ทั้ง app log และ error)
- log event สำคัญด้าน security (login fail, access denied) พอให้ตรวจสอบย้อนได้ `[ปรับตามทีม]`

## A10 — SSRF
- ห้ามให้ user กำหนด URL ปลายทางที่ server จะไปยิงตรงๆ (webhook, fetch image by url, import-by-url)
- ถ้าจำเป็น: allowlist host/scheme, บล็อก internal IP / metadata endpoint (169.254.169.254)

---

## Stack-specific

**NestJS / backend**
- `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true })` กัน mass assignment
- response ผ่าน DTO/serializer ไม่คืน entity ดิบ (กัน `password`/`hash` หลุด)
- guard ครบทุก protected route; ดึง userId จาก `req.user` ไม่ใช่จาก param
- raw query parameterized; transaction ครอบ multi-write

**Next.js / frontend**
- secret ไม่อยู่ใน `NEXT_PUBLIC_*` / ไม่อยู่ใน bundle; external API ที่ใช้ secret เรียกผ่าน route handler/server action
- ระวัง `dangerouslySetInnerHTML`; server action / API ตรวจ auth + input เองทุกตัว (อย่าเชื่อว่า UI กันให้แล้ว)
- ไม่ส่ง data ของ user คนอื่นมาที่ client แล้วค่อยซ่อนด้วย CSS

**LINE LIFF**
- ID/access token จาก client **verify ฝั่ง backend** ก่อนเชื่อ — ส่ง ID token ไป verify ไม่ใช่ส่ง userId ดิบ
- ไม่ trust profile จาก client เป็น identity

**Mobile (RN / Flutter)**
- secret ไม่ฝังใน bundle (ถอดได้) — ของลับอยู่ฝั่ง backend
- token เก็บใน secure storage (Keychain/Keystore) ไม่ใช่ AsyncStorage/SharedPreferences ดิบ
- ปิด debug log ที่มี sensitive data บน release build
