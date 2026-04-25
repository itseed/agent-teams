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

# ──────────────────────────────────────────────────────────────
# Parse args
# ──────────────────────────────────────────────────────────────
case "${1:-}" in
  -h|--help)
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Kill tmux session "$SESSION" (all panes).

Options:
  -f, --force    kill ทันที ไม่ถาม confirm
  -h, --help     แสดง help นี้

Note: conversation history ใน claude ทุก pane จะหายทั้งหมด
      งานที่ commit/save ไว้ใน git จะไม่ได้รับผลกระทบ
EOF
    exit 0
    ;;
  -f|--force)
    FORCE=1
    ;;
  "")
    ;;
  *)
    echo "Unknown option: $1" >&2
    echo "Run with --help for usage" >&2
    exit 1
    ;;
esac

# ──────────────────────────────────────────────────────────────
# Check session exists
# ──────────────────────────────────────────────────────────────
command -v tmux >/dev/null || { echo "Error: tmux not found" >&2; exit 1; }

if ! tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "Session '$SESSION' ไม่มีอยู่ — ไม่มีอะไรต้องทำ"
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
