# CI/CD — GitHub Actions convention

## โครงสร้าง pipeline

ลำดับ stage มาตรฐาน (fail fast — หยุดทันทีที่ stage แรกพัง):
```
install → lint → typecheck → test → build → (deploy เฉพาะ branch ที่กำหนด)
```

- แยก **job ที่ขนานกันได้** (lint / typecheck / test) ออกจากกันเพื่อเร็วขึ้น แล้วให้ `build`/`deploy` `needs:` job เหล่านั้น
- **deploy เป็น job แยก** ที่ `needs` ผ่านทั้งหมด + จำกัด `if: github.ref == 'refs/heads/main'` (หรือ environment protection rule)

## กฎสำคัญ

- **Pin action version** ด้วย tag เต็ม (`actions/checkout@v4`) — ห้าม `@main`/`@master`
- **Cache dependency** (`actions/setup-node` with `cache: npm`) — ลดเวลา + เสถียร
- **Least-privilege `permissions:`** — ตั้งระดับ workflow เป็น `contents: read` แล้วเพิ่มเฉพาะ job ที่ต้องการ (เช่น `packages: write`)
- **Secret ผ่าน `${{ secrets.X }}`** เท่านั้น — ไม่ echo ออก log; ถ้าต้อง log ค่าที่ sensitive ใช้ `::add-mask::`
- **Concurrency** — ยกเลิก run เก่าของ branch เดียวกัน: `concurrency: { group: ${{ github.ref }}, cancel-in-progress: true }`
- pin runner image (`ubuntu-24.04` ไม่ใช่ `ubuntu-latest` ถ้าต้องการ reproducibility สูง)

## โครงตัวอย่าง
```yaml
name: CI
on:
  push: { branches: [main] }
  pull_request:
permissions:
  contents: read
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  verify:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20', cache: 'npm' }
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm test
      - run: npm run build
  deploy:
    needs: verify
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-24.04
    environment: production
    steps:
      - uses: actions/checkout@v4
      # ... deploy steps using secrets
```

## Verify
- ใช้ `actionlint` ถ้ามีติดตั้ง
- ตรวจ `needs:` graph ว่า deploy ไม่รันก่อน verify ผ่าน
- ตรวจว่า secret ทุกตัวที่อ้างใน yml มีตั้งไว้จริงใน repo/environment settings (แจ้ง Lead ถ้าต้องให้ user เพิ่ม)
