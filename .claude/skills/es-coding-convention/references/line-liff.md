# LINE LIFF Convention

อ่านคู่กับ `nextjs.md` (LIFF app ส่วนใหญ่เป็น Next.js/React) เน้นเฉพาะส่วนที่ต่างจาก web ปกติ

## Initialization
- `liff.init()` ครั้งเดียวตอน app เริ่ม — ทำใน provider/context ระดับบนสุด ไม่เรียกซ้ำในหลาย component
- รอ init เสร็จก่อน render ส่วนที่ต้องใช้ LIFF API (กัน race ตอนเรียก API ก่อน ready)
- จัดการกรณี init fail (เปิดนอก LINE, network error) ให้มี fallback ชัดเจน

## Login flow — จุดที่พังบ่อย
- เช็ก `liff.isLoggedIn()` ก่อนเรียก `liff.login()` เสมอ
- **อย่าเรียก `liff.login()` ใน flow ที่ login อยู่แล้ว** → ต้นเหตุ login loop คลาสสิก
- หลัง `liff.login()` LIFF จะ redirect เอง อย่าผูก logic ต่อท้ายแบบคาดว่าโค้ดบรรทัดถัดไปจะรัน
- ระวัง `useEffect` ที่มี dependency ทำให้ login ถูก trigger ซ้ำทุก re-render

## Environment — แยกให้เด็ดขาด
- LIFF ID **คนละตัว** ต่อ environment (dev / uat / prod) เก็บใน env แยก ไม่ hardcode
- endpoint URL ที่ตั้งใน LINE Developers Console ต้องตรงกับ env ที่ deploy จริง
- เวลา debug ปัญหาเฉพาะ env (เช่น login loop ที่เกิดเฉพาะ UAT) เช็กก่อนว่า LIFF ID / endpoint URL ของ env นั้นตั้งถูกไหม

## Token & security
- ID token / access token จาก client **ต้อง verify ฝั่ง backend** ก่อนเชื่อถือ — ห้าม trust profile ดิบจาก client
- ส่ง ID token ไป verify ที่ backend แทนการส่ง userId ตรง ๆ (กันปลอม)
- token หมดอายุได้ — จัดการ refresh / re-login อย่างนุ่มนวล ไม่เด้ง error ใส่ผู้ใช้

## Scaffold LIFF app/feature — checklist
1. LIFF provider ระดับบน: init + จัดการ ready/error state
2. แยก LIFF ID per env ใน config
3. guard ส่วนที่ต้อง login: เช็ก `isLoggedIn` → ถ้ายังให้ login (ครั้งเดียว ไม่วน)
4. ทุก API ที่ใช้ตัวตนผู้ใช้ verify token ฝั่ง backend
5. ทดสอบ flow ทั้งใน LINE app จริงและ external browser