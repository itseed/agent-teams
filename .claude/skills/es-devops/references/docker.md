# Docker / docker-compose convention

## Dockerfile

- **Multi-stage build** เสมอสำหรับ compiled/bundled app (Node/Go/Java) — แยก build stage ออกจาก runtime เพื่อ image เล็ก + ไม่มี build tool หลุดไป prod
- **Pin base image** ด้วย tag เฉพาะ (เลี่ยง `latest`) — ดีกว่านั้นใช้ digest สำหรับ prod: `node:20.18-alpine@sha256:...`
- เรียง layer จาก **เปลี่ยนน้อย → เปลี่ยนบ่อย** เพื่อใช้ cache: copy manifest (`package.json`) + install ก่อน แล้วค่อย copy source
- **Non-root user** ใน runtime stage: สร้าง user แล้ว `USER node` / `USER app`
- `.dockerignore` ครบ — กัน `node_modules`, `.git`, `.env`, build artifact หลุดเข้า context
- ระบุ `HEALTHCHECK` ถ้า service มี endpoint ตรวจสุขภาพ
- `EXPOSE` เฉพาะ port ที่ใช้จริง; ใช้ `CMD ["node","dist/main"]` (exec form) ไม่ใช่ shell form

### โครงตัวอย่าง (Node)
```dockerfile
# ---- build ----
FROM node:20.18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---- runtime ----
FROM node:20.18-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "dist/main"]
```

## docker-compose

- ใช้สำหรับ **local dev / single-host** — ไม่ใช่ prod orchestration (นั่นคือ k8s/swarm)
- **named volumes** สำหรับ data ที่ต้อง persist (db, uploads) — ไม่ใช่ bind mount path ในเครื่อง
- `depends_on` + `healthcheck` ให้ service ที่พึ่ง db รอ db พร้อมจริง (depends_on อย่างเดียวไม่รอ readiness)
- secret/config ผ่าน `env_file: .env` (ที่ไม่ commit) — ไม่ hardcode ใน yml
- ตั้ง `restart: unless-stopped` สำหรับ service ที่ต้อง resilient
- pin image tag ทุกตัว (postgres, redis ฯลฯ)

```yaml
services:
  api:
    build: .
    env_file: .env
    ports: ["3000:3000"]
    depends_on:
      db: { condition: service_healthy }
    restart: unless-stopped
  db:
    image: postgres:16.4-alpine
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes: ["pgdata:/var/lib/postgresql/data"]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      retries: 5
volumes:
  pgdata:
```

## Verify
- `docker build -t test .` ต้องผ่าน
- `docker compose config` validate syntax
- ตรวจ image size (`docker images`) — ถ้าใหญ่ผิดปกติ แปลว่า build tool/source หลุดเข้า runtime
