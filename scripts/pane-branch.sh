#!/usr/bin/env bash
# pane-branch.sh — echo git branch ของ repo ที่ agent pane ทำงานอยู่ (ใช้ใน tmux pane-border-format)
#
# Usage: pane-branch.sh [-l] <workdir> <fallback_path>
#   <workdir>        ค่า pane option @workdir (ว่างได้)
#   <fallback_path>  #{pane_current_path} — ใช้เมื่อ workdir ว่าง/ไม่ใช่ repo (เช่น Lead pane)
#   -l               ออกเป็น label พร้อมใช้ใน border: "  ⎇ <branch>" (ว่างเปล่าถ้าไม่ใช่ repo)
#
# detached HEAD -> short sha; ไม่ใช่ repo -> ไม่ echo อะไร; ไม่เขียน stderr; exit 0 เสมอ
# (tmux #() รันซ้ำทุก status-interval ต่อ pane — ต้องเร็วและเงียบ)

label=0
if [[ "${1:-}" == "-l" ]]; then label=1; shift; fi

branch=""
for dir in "${1:-}" "${2:-}"; do
  [[ -n "$dir" && -d "$dir" ]] || continue
  branch=$(git -C "$dir" branch --show-current 2>/dev/null) || branch=""
  if [[ -z "$branch" ]]; then
    branch=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null) || branch=""
  fi
  [[ -n "$branch" ]] && break
done

if [[ -n "$branch" ]]; then
  if [[ $label -eq 1 ]]; then printf '  ⎇ %s' "$branch"; else printf '%s\n' "$branch"; fi
fi
exit 0
