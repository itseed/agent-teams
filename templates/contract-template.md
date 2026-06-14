# API Contract: <name>

> backend นิยามไฟล์นี้ **ก่อน** frontend/mobile เริ่มทำ แล้วแจ้ง agent ที่เกี่ยวข้อง
> วางไว้ที่ `docs/contracts/<api>.md` ใน repo ของ project — code ทุกฝั่งยึดตามไฟล์นี้ ห้ามเดา shape

## Endpoint
`<METHOD> /path/to/resource`

## Auth
<required? token type? role/permission ที่ต้องมี>

## Request
```jsonc
// headers / query / body
{
  "field": "type — คำอธิบาย"
}
```

## Response — success (`<status>`)
```jsonc
{
  "field": "type — คำอธิบาย"
}
```

## Response — errors
| Status | When | Body shape |
|--------|------|------------|
| 400 | validation fail | `{ "error": "...", "details": [...] }` |
| 401 | unauthenticated | `{ "error": "..." }` |
| 404 | not found | `{ "error": "..." }` |

## Env vars ที่เกี่ยวข้อง
| ชื่อ (ต้องตรงทุกฝั่ง) | ใช้ทำอะไร |
|----------------------|-----------|
| `<EXACT_ENV_NAME>` | <...> |

## Notes
<pagination, rate limit, idempotency, ฯลฯ>
