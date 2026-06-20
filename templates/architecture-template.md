# Architecture: <feature name>

> architect เขียนไฟล์นี้ **ก่อน** dev เริ่ม implement แล้วสั่ง dev "อ่าน docs/architecture/<feature>.md ให้ครบก่อนเริ่ม"
> วางไว้ที่ `docs/architecture/<feature>.md` ใน repo ของ project — เป็น source of truth ของ design ที่ทุก dev ยึดตาม
> โหลด skill `es-architecture` ก่อนกรอก

## Context & Constraints
<requirement สรุป (อ้าง docs/plan/<feature>.md), non-functional ที่สำคัญ (scale/latency/security), สิ่งที่ fix ไว้แล้วเปลี่ยนไม่ได้>

## Options considered
| Approach | Complexity | Scalability | Maintainability | Cost/Time | Fit | สรุป |
|----------|-----------|-------------|-----------------|-----------|-----|------|
| A. <...> | | | | | | |
| B. <...> | | | | | | |

## Decisions (ADR)

### ADR-1: <หัวข้อ>
- **Context:** <constraint ที่บังคับให้ตัดสินใจ>
- **Decision:** <เลือกอะไร>
- **Rationale:** <ทำไมชนะ — อ้าง tradeoff>
- **Rejected:** <ทางที่ไม่เลือก + เหตุผล>
- **Consequences:** <ผลที่ตามมา + สิ่งที่ต้องระวังตอน implement>

## Boundaries
<module/service/layer + ใครเป็นเจ้าของ data ไหน + dependency direction (ห้าม cycle)>

```mermaid
flowchart LR
  %% container/component diagram
```

## Integration points
| จุดเชื่อม | ข้าม boundary ไหน | contract ที่ต้องมี |
|-----------|-------------------|---------------------|
| <METHOD /path> | web → api | `docs/contracts/<api>.md` (backend นิยาม) |

## Tasks → dev roles
| ส่วน | role | acceptance (ระดับ design) |
|------|------|---------------------------|
| <...> | backend | <ตรง boundary X + contract Y> |
| <...> | frontend | <consume contract Y, state owner ชัด> |

## Risks & non-functional
- **Failure mode:** <จะพังยังไง + mitigation>
- **Migration / rollout:** <expand→migrate→contract? feature flag?>
- **Observability:** <log/metric/trace ที่ต้องมี>
- **Security boundary:** <trust boundary, data exposure, authz>

## Open questions (ถ้ามี — ส่งกลับ Lead)
- [ ] <สิ่งที่ตัดสินใจไม่ได้เพราะข้อมูลขาด>
