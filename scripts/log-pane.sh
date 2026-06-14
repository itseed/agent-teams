#!/usr/bin/env bash
# log-pane.sh <role> [logdir]
#
# Robust log viewer for one role's pane in v2 mode.
#
# Why this exists: agent panes used to run `tail -f /tmp/agent-logs/<role>.log`
# on an EXACT filename. But a spawned sub-agent (general-purpose, ไม่อ่าน role .md)
# อาจเขียน log ลงไฟล์ชื่อเพี้ยน เช่น `frontend-pms.log` — pane ที่ tail `frontend.log`
# จึงเห็นว่างเปล่า (อาการ "ชื่อ sub agent ไม่ตรง เลยไม่เห็น log").
#
# This helper follows ALL files matching "<role>*.log" — รวมไฟล์ที่เพิ่งสร้าง
# หลัง pane เปิดแล้ว (rescan ทุก 2s) — และใช้ `tail -F` ให้รอด truncate/recreate.
# ถ้าไฟล์ชื่อเพี้ยนจาก canonical จะ prefix ชื่อไฟล์ให้เห็นว่า drift.
#
# Portable: bash 3.2 (macOS default) + Linux. ไม่ใช้ inotify / associative array.
set -u

role="${1:?usage: log-pane.sh <role> [logdir]}"
logdir="${2:-/tmp/agent-logs}"

cd "$logdir" 2>/dev/null || { echo "(log dir not found: $logdir)"; sleep 5; exit 1; }

printf '\033[2m▼ watching %s/%s*.log\033[0m\n' "$logdir" "$role"
printf '\033[2m  log ของ agent ที่ขึ้นต้นด้วย "%s" จะโผล่ที่นี่ แม้ชื่อไฟล์เพี้ยน\033[0m\n' "$role"

# space-delimited list of files already being tailed (bash 3.2: no assoc array)
seen=" "
while true; do
  for f in "$role"*.log; do
    [ -e "$f" ] || continue                 # nullglob off: skip literal non-match
    case "$seen" in
      *" $f "*) ;;                           # already tailing this file
      *)
        seen="$seen$f "
        if [ "$f" = "$role.log" ]; then
          # canonical file — show raw (clean)
          tail -n 200 -F "$f" 2>/dev/null &
        else
          # drifted filename — label each line so the mismatch is visible
          tail -n 200 -F "$f" 2>/dev/null | awk -v p="[$f] " '{ print p $0; fflush() }' &
        fi
        ;;
    esac
  done
  sleep 2
done
