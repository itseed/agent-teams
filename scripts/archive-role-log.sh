#!/usr/bin/env bash
# archive-role-log.sh <role> — archive-then-truncate one v2 role's log before a new task
#
# คู่กับ /clear ของ v1 (ดู "เคลียร์ context ก่อนเริ่มงานใหม่" ใน CLAUDE.md) — เรียกก่อนทุกครั้งที่
# Lead จะ spawn task ใหม่ให้ role นี้ใน v2 mode กัน /tmp/agent-logs/<role>.log โตไม่มีที่สิ้นสุด
#
# TRUNCATE ไม่ลบไฟล์ — pane ของ role นั้น tail -F ไฟล์นี้อยู่แบบ real-time (scripts/log-pane.sh)
# การ truncate-in-place (เขียนทับให้ว่างโดยไม่เปลี่ยน inode) ทำให้ tail -F follow ต่อได้โดยไม่ต้อง
# restart pane — ถ้าลบไฟล์แล้วสร้างใหม่ tail -F จะตามไม่ทันจนกว่าจะ retry cycle ถัดไป
#
# Usage:
#   ./scripts/archive-role-log.sh <role>
#
#   role   หนึ่งใน: frontend backend mobile devops designer architect qa reviewer

set -euo pipefail

ALL_ROLES=(frontend backend mobile devops designer architect qa reviewer)
LOG_DIR="/tmp/agent-logs"
ARCHIVE_DIR="/tmp/agent-logs-archive"

ROLE="${1:-}"
[[ -n "$ROLE" ]] || { echo "Usage: $(basename "$0") <role>" >&2; exit 1; }
if [[ " ${ALL_ROLES[*]} " != *" $ROLE "* ]]; then
  echo "Error: unknown role '$ROLE' (valid: ${ALL_ROLES[*]})" >&2
  exit 1
fi

LOG_FILE="$LOG_DIR/${ROLE}.log"
ARCHIVE_FILE="$ARCHIVE_DIR/${ROLE}.log"

# ไฟล์ไม่มีอยู่ หรือว่างอยู่แล้ว — ไม่มีอะไรต้อง archive, เงียบไว้ (ไม่สร้าง archive ไฟล์เปล่า)
[[ -s "$LOG_FILE" ]] || exit 0

mkdir -p "$ARCHIVE_DIR"
LINE_COUNT=$(wc -l < "$LOG_FILE" | tr -d ' ')
TS=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

{
  echo "===== $ROLE rotated at $TS ====="
  cat "$LOG_FILE"
} >> "$ARCHIVE_FILE"

# truncate-in-place (ไม่ rm) — เก็บ inode เดิมไว้ให้ tail -F ที่ pane follow อยู่ทำงานต่อได้
: > "$LOG_FILE"

echo "✓ archived $LINE_COUNT lines, truncated $LOG_FILE"
