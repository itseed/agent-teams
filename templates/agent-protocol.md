## Team protocol (v1 — interactive tmux panes)

> ส่วนนี้ถูกต่อท้ายให้อัตโนมัติโดย `start-team.sh` / `add-role.sh` (source: `templates/agent-protocol.md`)
> แก้ protocol ที่ไฟล์นั้นที่เดียว — ไม่ต้องแก้ role .md ทั้ง 8 ไฟล์

### ส่งข้อความ — ใช้ `team-send.sh` เท่านั้น

```bash
echo "<message>" | {{TEAM_SEND}} <pane>
```

script จัดการ paste + Enter + retry ให้ และ quote-safe (ข้อความมี `"` `$` หรือหลายบรรทัดได้)
— ห้าม hand-roll `tmux set-buffer`/`send-keys` เอง

- Lead = `dev-team:0.0` · role อื่น = stable `%ID` จากตาราง "Pane Addresses" ด้านล่าง (หรือ `.team-state.md`)
  ห้ามใช้ numeric index `0.N` (RTK pane ทำให้เลื่อน)
- คุยกับ agent อื่นตรงได้ แต่ **ต้อง CC Lead ทุกครั้ง** ด้วยรูปแบบ `[{{ROLE}} → <target>] <message>`:
  ```bash
  MSG="[{{ROLE}} → backend] ต้องการ response format ของ /auth/login"
  echo "$MSG" | {{TEAM_SEND}} <backend-pane>
  echo "$MSG" | {{TEAM_SEND}} dev-team:0.0
  ```

### 1. Ack ทันทีที่รับงาน (บังคับ)

```bash
echo "{{ROLE}} รับงานแล้ว: <สรุป task 1 บรรทัด>" | {{TEAM_SEND}} dev-team:0.0
```

scope ไม่ชัด/requirement หาย → ถามกลับก่อน อย่าเดาแล้วลงมือ

### 2. Status file (บังคับ — source of truth ของ Lead)

tmux paste เป็น fire-and-forget อาจหลุดได้ — เขียนสถานะลงไฟล์ควบคู่เสมอ และเขียน **ก่อน** ส่ง report ทาง tmux:

```bash
STATUS=/tmp/agent-status/{{ROLE}}.md; mkdir -p /tmp/agent-status
# รับงาน:
printf '%s\n' "status: working" "task: <task>" "updated: $(date '+%H:%M:%S')" > "$STATUS"
# เสร็จ:
printf '%s\n' "status: done" "task: <task>" "updated: $(date '+%H:%M:%S')" "" "## Verification evidence" "<output จริงของ typecheck/build/test/run>" > "$STATUS"
# ติดปัญหา:
printf '%s\n' "status: blocked" "task: <task>" "blocker: <ติดอะไร ต้องการอะไร>" "updated: $(date '+%H:%M:%S')" > "$STATUS"
```

### 3. Report กลับเมื่อเสร็จ (บังคับ — ห้ามละเว้น)

```bash
echo "{{ROLE}} เสร็จแล้ว" | {{TEAM_SEND}} dev-team:0.0
```

นี่คือวิธีเดียวที่ Lead จะรู้ว่างานเสร็จ — ถ้า blocked ก็ส่ง `"{{ROLE}} blocked: <สรุป>"` แบบเดียวกัน

### 4. ห้ามใช้ interactive prompt

ห้ามใช้ `AskUserQuestion` หรือรอ confirm แบบ menu — มันค้างอยู่ใน pane ของคุณโดย Lead ไม่เห็น
ถ้าต้องให้ Lead ตัดสินใจ → เขียน status `blocked` + ส่งคำถามเป็นข้อความผ่าน `team-send.sh` แล้วหยุดรอ
