#!/usr/bin/env bash
# dispatch.sh — ส่งงานให้ role ใน v1 พร้อมตัดสินใจ /clear จาก "task key" แทนการเดา
#
# Usage:
#   dispatch.sh <role> <key> [options] "<prompt>"
#   echo "<prompt>" | dispatch.sh <role> <key> [options]
#
#   <key>      ชื่องาน/feature ที่ใช้ตัดสินว่างานต่อเนื่องหรือไม่ — แนะนำ slug ของ feature
#              (เช่น km-business-scope ใช้ร่วมกันทุก phase) หรือเลข issue (เช่น issue-303)
#              key เดิมกับงานล่าสุดของ role → ไม่ clear (agent จำ context เดิม: รอบแก้หลัง QA/Reviewer FAIL,
#              re-review, phase ถัดไปของ feature เดียวกัน)  ·  key ต่าง → /clear ก่อนส่ง
#
# Options:
#   --fresh         บังคับ /clear แม้ key เดิม (เช่น context agent เพี้ยน/ใกล้เต็ม)
#   --keep          ไม่ clear แม้ key ต่าง (งานใหม่ที่ต้องใช้ความรู้จากงานก่อน)
#   --task TEXT     ข้อความ Current Task ใน .team-state.md (default: "[<key>] <บรรทัดแรกของ prompt>")
#   --no-wait       ไม่รอ ack (default: รอ status file ของ role เปลี่ยนเป็น working)
#   --ack-timeout S วินาทีที่รอ ack ต่อรอบ (default 90)
#
# Exit: 0 = ส่งแล้ว + ได้ ack (หรือ --no-wait) · 1 = usage/ส่งไม่ได้ · 2 = ส่งแล้วแต่ไม่มี ack (เช็ค pane)
#
# ทำอะไรให้บ้าง:
#   1. หา pane %ID ของ role จาก .team-state.md
#   2. ปฏิเสธถ้า agent กำลังทำงาน (ห้ามสั่งงานทับ)
#   3. key ต่าง/--fresh → ส่ง /clear แล้ว "รอให้ clear เสร็จจริง" ก่อนส่งงาน
#      (กันอาการ /clear กลืน task ที่ส่งตามติดๆ)
#   4. ส่ง prompt ผ่าน team-send.sh + จำ key ไว้ที่ /tmp/agent-status/<role>.key
#   5. team-state.sh set <role> working
#   6. รอ ack = /tmp/agent-status/<role>.md ถูกเขียนใหม่หลังส่ง; ไม่มา + pane ว่าง → ส่งซ้ำ 1 ครั้ง

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
AGENT_TEAMS_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
STATE_FILE="${TEAM_STATE_FILE:-$AGENT_TEAMS_DIR/.team-state.md}"
STATUS_DIR="${AGENT_STATUS_DIR:-/tmp/agent-status}"
TEAM_SEND="${TEAM_SEND:-$SCRIPT_DIR/team-send.sh}"
TEAM_STATE="${TEAM_STATE_CMD:-$SCRIPT_DIR/team-state.sh}"
ROLES=(frontend backend mobile devops designer architect qa reviewer)

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }

ROLE="${1:-}"; KEY="${2:-}"
[[ -n "$ROLE" && -n "$KEY" ]] || usage
[[ "$ROLE" == -* || "$KEY" == -* ]] && usage
shift 2
[[ " ${ROLES[*]} " == *" $ROLE "* ]] || { echo "dispatch: unknown role '$ROLE' (valid: ${ROLES[*]})" >&2; exit 1; }

MODE="auto"; TASK=""; WAIT=1; ACK_TIMEOUT=90; PROMPT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --fresh) MODE="fresh" ;;
    --keep) MODE="keep" ;;
    --task) TASK="${2:?--task ต้องมีข้อความ}"; shift ;;
    --no-wait) WAIT=0 ;;
    --ack-timeout) ACK_TIMEOUT="${2:?--ack-timeout ต้องมีตัวเลข}"; shift ;;
    -h|--help) usage ;;
    -*) echo "dispatch: unknown option $1" >&2; exit 1 ;;
    *) PROMPT="${PROMPT:+$PROMPT }$1" ;;
  esac
  shift
done
if [[ -z "$PROMPT" && ! -t 0 ]]; then PROMPT="$(cat)"; fi
[[ -n "${PROMPT//[[:space:]]/}" ]] || { echo "dispatch: empty prompt" >&2; exit 1; }

# ── 1. pane ของ role จาก .team-state.md ─────────────────────────
[[ -f "$STATE_FILE" ]] || { echo "dispatch: $STATE_FILE not found — run start-team.sh first" >&2; exit 1; }
PANE=$(awk -F'|' -v r="$ROLE" '$2 ~ "^ *"r" *$" { gsub(/ /, "", $3); print $3; exit }' "$STATE_FILE")
[[ "$PANE" == %* ]] || { echo "dispatch: no pane id for '$ROLE' in .team-state.md (add-role.sh $ROLE?)" >&2; exit 1; }

capture() { tmux capture-pane -t "$PANE" -p 2>/dev/null || true; }
# shellcheck source=lib/pane.sh
source "$SCRIPT_DIR/lib/pane.sh"
busy() { pane_busy "$PANE"; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

tmux capture-pane -t "$PANE" -p >/dev/null 2>&1 \
  || { echo "dispatch: pane $PANE ($ROLE) not found — team-state เก่า? ดู ./scripts/restore-pane-labels.sh" >&2; exit 1; }

# ── 2. ห้ามสั่งงานทับ ───────────────────────────────────────────
if busy; then
  echo "dispatch: $ROLE ($PANE) กำลังทำงานอยู่ — รอให้เสร็จก่อน (ห้ามสั่งงานทับ)" >&2
  exit 1
fi

# ── 3. ตัดสินใจ /clear ──────────────────────────────────────────
mkdir -p "$STATUS_DIR"
KEY_FILE="$STATUS_DIR/$ROLE.key"
PREV_KEY="$(cat "$KEY_FILE" 2>/dev/null || true)"
CLEAR=0
case "$MODE" in
  fresh) CLEAR=1 ;;
  keep)  CLEAR=0 ;;
  auto)  [[ -n "$PREV_KEY" && "$PREV_KEY" != "$KEY" ]] && CLEAR=1 ;;
esac
# PREV_KEY ว่าง = role ยังไม่เคยรับงานตั้งแต่ start ทีม (pane สด) → ไม่ต้อง clear

if [[ $CLEAR -eq 1 ]]; then
  if [[ "$MODE" == "fresh" ]]; then echo "→ $ROLE: --fresh — /clear ก่อนส่งงาน"
  else echo "→ $ROLE: key '$PREV_KEY' → '$KEY' (งานใหม่) — /clear ก่อนส่งงาน"; fi
  BEFORE="$(capture)"
  "$TEAM_SEND" "$PANE" "/clear" >/dev/null
  # รอจนหน้าจอเปลี่ยน (clear ทำงานแล้ว) และ agent ไม่ busy, max ~20s
  i=0
  while [[ $i -lt 40 ]]; do
    sleep 0.5
    if [[ "$(capture)" != "$BEFORE" ]] && ! busy; then break; fi
    i=$((i + 1))
  done
  [[ $i -lt 40 ]] || echo "dispatch: warning — ไม่เห็นหน้าจอเปลี่ยนหลัง /clear ภายใน 20s (ส่งงานต่อ)" >&2
  sleep 1.5   # ให้ Claude Code พร้อมรับ input ถัดไปจริงๆ
elif [[ -z "$PREV_KEY" ]]; then
  echo "→ $ROLE: งานแรกตั้งแต่ start ทีม (key '$KEY') — ไม่ต้อง clear"
elif [[ "$PREV_KEY" == "$KEY" ]]; then
  echo "→ $ROLE: key '$KEY' เดิม (งานต่อเนื่อง) — ส่งต่อโดยไม่ clear"
else
  echo "→ $ROLE: key '$PREV_KEY' → '$KEY' แต่ --keep — ส่งต่อโดยไม่ clear"
fi

# ── 4-5. ส่งงาน + บันทึก ────────────────────────────────────────
STATUS_FILE="$STATUS_DIR/$ROLE.md"
# snapshot status file ก่อนส่ง — ack = ไฟล์ถูกเขียนใหม่หลังจากนี้ (content หรือ mtime เปลี่ยน)
fingerprint() { [[ -f "$STATUS_FILE" ]] && { mtime "$STATUS_FILE"; cksum < "$STATUS_FILE"; } || echo none; }
snapshot() { BEFORE_ACK="$(fingerprint)"; }
send_prompt() { printf '%s\n' "$PROMPT" | "$TEAM_SEND" "$PANE"; }
snapshot

send_prompt || { echo "dispatch: team-send ส่งไม่สำเร็จ — เช็ค pane $PANE" >&2; exit 1; }
printf '%s\n' "$KEY" > "$KEY_FILE"

if [[ -z "$TASK" ]]; then
  TASK="[$KEY] $(printf '%s\n' "$PROMPT" | awk 'NF { print substr($0, 1, 80); exit }')"
fi
"$TEAM_STATE" set "$ROLE" working "$TASK" >/dev/null || echo "dispatch: warning — team-state.sh set ไม่สำเร็จ" >&2

[[ $WAIT -eq 1 ]] || { echo "✓ ส่งงานให้ $ROLE แล้ว ($PANE) — ไม่รอ ack"; exit 0; }

# ── 6. รอ ack ───────────────────────────────────────────────────
# protocol บังคับ agent เขียน status: working ลง status file ทันทีที่รับงาน → ใช้เป็น ack ที่เชื่อถือได้
acked() { [[ -f "$STATUS_FILE" && "$(fingerprint)" != "$BEFORE_ACK" ]]; }
wait_ack() {
  local t=0
  while [[ $t -lt $ACK_TIMEOUT ]]; do
    acked && return 0
    sleep 2; t=$((t + 2))
  done
  acked
}

if wait_ack; then
  echo "✓ $ROLE รับงานแล้ว ($PANE) — $(grep -m1 '^task:' "$STATUS_FILE" 2>/dev/null || echo 'status file updated')"
  exit 0
fi

if ! busy; then
  # pane ว่างและไม่มี ack = task ถูกกลืน (มักเกิดหลัง /clear) → ส่งซ้ำ 1 ครั้ง ไม่ clear อีก
  echo "→ $ROLE ไม่ ack ภายใน ${ACK_TIMEOUT}s และ pane ว่าง — ส่งงานซ้ำ 1 ครั้ง"
  snapshot
  send_prompt || true
  if wait_ack; then
    echo "✓ $ROLE รับงานแล้วหลังส่งซ้ำ ($PANE)"
    exit 0
  fi
fi

if busy; then
  echo "dispatch: ⚠️ $ROLE ($PANE) กำลังทำงานแต่ยังไม่เขียน status file (ข้าม protocol ack?) — ตรวจ: tmux capture-pane -t $PANE -p | tail -20" >&2
else
  echo "dispatch: ⚠️ $ROLE ($PANE) ยังไม่ ack แม้ส่งซ้ำแล้ว — ตรวจ: tmux capture-pane -t $PANE -p | tail -20" >&2
fi
exit 2
