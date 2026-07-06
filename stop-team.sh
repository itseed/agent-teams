#!/usr/bin/env bash
# stop-team.sh — kill dev-team tmux session
#
# Usage:
#   ./stop-team.sh        # ถาม confirm ก่อน kill
#   ./stop-team.sh -f     # kill ทันทีไม่ถาม
#   ./stop-team.sh --help

set -euo pipefail

SESSION="dev-team"
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

Kill tmux session "$SESSION" (all panes) แล้วเก็บกวาด /tmp runtime files.

Options:
  -f, --force      kill ทันที ไม่ถาม confirm
  -k, --keep-logs  ไม่ลบ /tmp runtime files (เก็บ logs ไว้ debug)
  -h, --help       แสดง help นี้

เมื่อ stop จะ archive logs ของ v2 ไป /tmp/agent-logs-archive/ แล้วลบ
/tmp/agent-logs/ + /tmp/agent-<role>/ (เว้นแต่ใส่ --keep-logs)

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
# Cleanup /tmp runtime files: archive v2 logs, then remove
# /tmp/agent-logs/ (v2) and /tmp/agent-<role>/ dirs (v1)
# ──────────────────────────────────────────────────────────────
cleanup_tmp() {
  if [[ "$KEEP_LOGS" -eq 1 ]]; then
    echo "→ --keep-logs: ข้ามการเก็บกวาด /tmp runtime files"
    return 0
  fi

  local r has_content=0 removed=0 stamp archive

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

  # Remove v1 per-role dirs
  for r in "${ROLES[@]}"; do
    if [[ -d "/tmp/agent-$r" ]]; then
      rm -rf "/tmp/agent-$r"
      removed=$((removed + 1))
    fi
  done
  [[ "$removed" -gt 0 ]] && echo "  ✓ removed $removed /tmp/agent-<role> dir(s)"
}

# ──────────────────────────────────────────────────────────────
# Check session exists
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' ไม่มีอยู่ — เก็บกวาด /tmp runtime files ที่ค้างอยู่"
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

# ──────────────────────────────────────────────────────────────
# Cleanup /tmp runtime files
# ──────────────────────────────────────────────────────────────
cleanup_tmp
