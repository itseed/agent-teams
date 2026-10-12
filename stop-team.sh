#!/usr/bin/env bash
# stop-team.sh — kill dev-team tmux session (v1 "dev-team" หรือ v2 "dev-team-v2")
#
# Usage:
#   ./stop-team.sh                  # auto-detect session (v1/v2) แล้วถาม confirm ก่อน kill
#   ./stop-team.sh -f               # kill ทันทีไม่ถาม
#   ./stop-team.sh --session dev-team-v2   # ระบุ session ตรงๆ (ข้าม picker/auto-detect ทั้งหมด)
#   ./stop-team.sh --help
#
# ถ้ารันอยู่พร้อมกันทั้ง v1 และ v2 และไม่ได้ระบุ --session:
#   - terminal แบบ interactive (ไม่ใช่ -f, stdin เป็น TTY) → แสดง numbered list ให้เลือกว่าจะ kill ตัวไหน
#   - ไม่ใช่ interactive (piped/no TTY) หรือใส่ -f โดยไม่ระบุ --session → error ทันที ไม่เดา

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=scripts/lib/common.sh
source "$SCRIPT_DIR/scripts/lib/common.sh"   # stop_dashboard
STATE_FILE="$SCRIPT_DIR/.team-state.md"
SESSION_OVERRIDE=""
FORCE=0
KEEP_LOGS=0
LOG_DIR="/tmp/agent-logs"
ROLES=(frontend backend mobile devops designer architect qa reviewer)

# ──────────────────────────────────────────────────────────────
# Parse args
# ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Kill tmux session dev-team (v1) หรือ dev-team-v2 (v2) — auto-detect ว่าตัวไหนรันอยู่จริง
แล้วเก็บกวาด /tmp runtime files

ถ้ารันอยู่พร้อมกันทั้งคู่และไม่ได้ระบุ --session:
  - interactive terminal (ไม่ใช่ -f, stdin เป็น TTY) → แสดง numbered list ให้เลือก
    (1) dev-team (v1)  2) dev-team-v2 (v2)) — กรอกผิดได้ 1 ครั้ง ถามซ้ำอีกรอบ ผิดอีกจะ error
  - non-interactive (piped/no TTY) หรือใส่ -f โดยไม่ระบุ --session → error ทันที ไม่เดา

Options:
  -f, --force        kill ทันที ไม่ถาม confirm (และไม่ถาม picker แม้รันพร้อมกันทั้งคู่)
  -k, --keep-logs    ไม่ลบ /tmp runtime files (เก็บ logs ไว้ debug)
  --session NAME     ระบุ session name ตรงๆ (dev-team หรือ dev-team-v2) — ข้าม auto-detect/picker ทั้งหมด
  -h, --help         แสดง help นี้

เมื่อ stop จะเก็บกวาดเฉพาะ /tmp path ที่เป็นของ session ที่ stop เท่านั้น (เว้นแต่ใส่ --keep-logs)
— ไม่แตะ path ของอีก mode ที่อาจรันคู่กันอยู่:
  - stop dev-team-v2 → archive logs ไป /tmp/agent-logs-archive/ แล้วลบ /tmp/agent-logs/
  - stop dev-team     → ลบ /tmp/agent-<role>/ + /tmp/agent-status/

Note: conversation history ใน claude ทุก pane จะหายทั้งหมด
      งานที่ commit/save ไว้ใน git จะไม่ได้รับผลกระทบ
EOF
      exit 0
      ;;
    -f|--force)
      FORCE=1
      ;;
    -k|--keep-logs)
      KEEP_LOGS=1
      ;;
    --session)
      SESSION_OVERRIDE="${2:-}"
      [[ -n "$SESSION_OVERRIDE" ]] || { echo "Error: --session ต้องระบุชื่อ session" >&2; exit 1; }
      shift
      ;;
    --session=*)
      SESSION_OVERRIDE="${1#--session=}"
      ;;
    "")
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Run with --help for usage" >&2
      exit 1
      ;;
  esac
  shift
done

# ──────────────────────────────────────────────────────────────
# Resolve session name: --session > tmux reality (v1/v2) > .team-state.md Mode (last-resort guess)
# ──────────────────────────────────────────────────────────────
resolve_session() {
  if [[ -n "$SESSION_OVERRIDE" ]]; then
    echo "$SESSION_OVERRIDE"
    return 0
  fi

  local v1_up=0 v2_up=0
  tmux has-session -t dev-team    2>/dev/null && v1_up=1
  tmux has-session -t dev-team-v2 2>/dev/null && v2_up=1

  if [[ "$v1_up" -eq 1 && "$v2_up" -eq 1 ]]; then
    # Interactive terminal + ไม่ได้ -f → ถามเลือกแทนที่จะ error ทันที (safe: ยังต้อง
    # ตัดสินใจโดย user เสมอ ไม่เดาเอง) — non-interactive/piped หรือ -f ไม่มี --session
    # ยังคง hard-error เดิม เพราะไม่มีทางถาม/รอ read ได้อย่างปลอดภัย
    if [[ "$FORCE" -ne 1 && -t 0 ]]; then
      echo "ทั้ง 'dev-team' (v1) และ 'dev-team-v2' (v2) กำลังรันอยู่พร้อมกัน:" >&2
      echo "  1) dev-team (v1)" >&2
      echo "  2) dev-team-v2 (v2)" >&2
      local pick tries=0
      while [[ "$tries" -lt 2 ]]; do
        tries=$((tries + 1))
        printf "Kill which session? [1/2] " >&2
        read -r pick || pick=""
        case "$pick" in
          1) echo "dev-team"; return 0 ;;
          2) echo "dev-team-v2"; return 0 ;;
          *) echo "Invalid input: '$pick' — กรอก 1 หรือ 2" >&2 ;;
        esac
      done
      echo "" >&2
    fi
    echo "Error: ทั้ง 'dev-team' (v1) และ 'dev-team-v2' (v2) กำลังรันอยู่พร้อมกัน — ระบุ session ที่ต้องการด้วย --session dev-team หรือ --session dev-team-v2 (ป้องกัน kill session ผิดตัวโดยไม่ตั้งใจ)" >&2
    exit 1
  elif [[ "$v1_up" -eq 1 ]]; then
    echo "dev-team"; return 0
  elif [[ "$v2_up" -eq 1 ]]; then
    echo "dev-team-v2"; return 0
  fi

  # ไม่มี session ไหนรันอยู่เลย (เช่นรัน stop-team.sh ซ้ำ) — เดาจาก .team-state.md เป็น fallback สุดท้าย
  if [[ -f "$STATE_FILE" ]] && grep -q "_Mode: v2" "$STATE_FILE"; then
    echo "dev-team-v2"
  else
    echo "dev-team"
  fi
}

SESSION="$(resolve_session)"

# ──────────────────────────────────────────────────────────────
# Cleanup /tmp runtime files — SCOPED ตาม $SESSION ที่กำลัง stop เท่านั้น
#
# v1 (dev-team) และ v2 (dev-team-v2) รันพร้อมกันได้ (คนละ tmux session) — ห้าม
# cleanup กวาดของอีกฝั่งทิ้งเวลา stop แค่ฝั่งเดียว:
#   - dev-team-v2 ใช้ /tmp/agent-logs/<role>.log เท่านั้น (v1 ไม่แตะ path นี้)
#   - dev-team ใช้ /tmp/agent-<role>/ (per-role CLAUDE.md dirs) + /tmp/agent-status/
#     (v2 ไม่ได้สร้าง per-role dir และไม่นับเป็นเจ้าของ path พวกนี้)
# ──────────────────────────────────────────────────────────────
cleanup_tmp() {
  if [[ "$KEEP_LOGS" -eq 1 ]]; then
    echo "→ --keep-logs: ข้ามการเก็บกวาด /tmp runtime files"
    return 0
  fi

  local r has_content=0 removed=0 stamp archive

  if [[ "$SESSION" == "dev-team-v2" ]]; then
    # Archive non-empty v2 logs before removing
    if [[ -d "$LOG_DIR" ]]; then
      for r in "${ROLES[@]}"; do
        [[ -s "$LOG_DIR/$r.log" ]] && has_content=1
      done
      if [[ "$has_content" -eq 1 ]]; then
        stamp=$(date '+%Y%m%d-%H%M%S')
        archive="/tmp/agent-logs-archive/${stamp}.log"
        mkdir -p /tmp/agent-logs-archive
        {
          for r in "${ROLES[@]}"; do
            [[ -s "$LOG_DIR/$r.log" ]] || continue
            echo "===== $r ====="
            cat "$LOG_DIR/$r.log"
            echo ""
          done
        } > "$archive"
        echo "  ✓ archived logs → $archive"
      fi
      rm -rf "$LOG_DIR"
      echo "  ✓ removed $LOG_DIR"
    fi
  fi

  if [[ "$SESSION" == "dev-team" ]]; then
    # Remove v1 per-role dirs
    for r in "${ROLES[@]}"; do
      if [[ -d "/tmp/agent-$r" ]]; then
        rm -rf "/tmp/agent-$r"
        removed=$((removed + 1))
      fi
    done
    [[ "$removed" -gt 0 ]] && echo "  ✓ removed $removed /tmp/agent-<role> dir(s)"

    # Remove agent status files
    if [[ -d /tmp/agent-status ]]; then
      rm -rf /tmp/agent-status
      echo "  ✓ removed /tmp/agent-status"
    fi
  fi
}

# ──────────────────────────────────────────────────────────────
# Check session exists
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' ไม่มีอยู่ — เก็บกวาด /tmp runtime files ที่ค้างอยู่"
  [[ "$SESSION" == "dev-team" ]] && stop_dashboard
  cleanup_tmp
  exit 0
fi

# ──────────────────────────────────────────────────────────────
# Show current panes
# ──────────────────────────────────────────────────────────────
echo "Session '$SESSION' active panes:"
echo ""
tmux list-panes -t "$SESSION" -F '  #{pane_index}: #{@role} (#{pane_current_path})'
echo ""

# ──────────────────────────────────────────────────────────────
# Confirm
# ──────────────────────────────────────────────────────────────
if [[ "$FORCE" -ne 1 ]]; then
  printf "Kill session '%s'? [y/N] " "$SESSION"
  read -r ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || { echo "Aborted."; exit 0; }
fi

# ──────────────────────────────────────────────────────────────
# Kill
# ──────────────────────────────────────────────────────────────
tmux kill-session -t "$SESSION"
echo "✓ Session '$SESSION' killed."
[[ "$SESSION" == "dev-team" ]] && stop_dashboard

# ──────────────────────────────────────────────────────────────
# Cleanup /tmp runtime files
# ──────────────────────────────────────────────────────────────
cleanup_tmp
