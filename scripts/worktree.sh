#!/usr/bin/env bash
# worktree.sh — สร้าง/ลบ/เก็บกวาด git worktree ของทีมจากที่เดียว (agent ห้ามสร้าง/ลบ worktree เอง)
#
# Usage:
#   worktree.sh create <repo-path> <branch> [--base <ref>] [--copy-env]
#   worktree.sh remove <worktree-path> [--force]
#   worktree.sh prune  [project|repo-path] [--dry-run] [--quiet]
#   worktree.sh list   [project|repo-path]
#
# ตำแหน่งมาตรฐาน: <parent ของ repo>/<ชื่อ repo>-worktrees/<branch โดยแทน / ด้วย ->
#   เช่น ~/project/myapp/myapp-api-worktrees/feat-login
#   เฉพาะ worktree ใต้ตำแหน่งนี้ที่ script ถือว่าเป็น "ของทีม" (managed) — ที่อื่นแค่รายงาน ไม่แตะ
#
# create  fetch origin ก่อน แล้วสร้างจาก branch เดิม (ถ้ามี) หรือแตก branch ใหม่จาก --base
#         (default origin/develop > develop > origin/main > main) — พิมพ์ path ที่ได้บรรทัดสุดท้าย
#         --copy-env  copy ไฟล์ .env* ที่ไม่ได้ track จาก checkout หลัก (ต้องใช้รันเทส/dev server)
#         node_modules ไม่ copy — agent รัน install เองใน worktree
# remove  ลบ worktree (ปฏิเสธถ้ามีไฟล์ค้างที่ยังไม่ commit — --force เพื่อทิ้ง) + git worktree prune
#         + ลบ local branch ถ้า merge แล้ว (git branch -d — ไม่ force)
# prune   ลบอัตโนมัติเฉพาะ managed worktree ที่ครบทุกข้อ:
#           (1) ไม่มีไฟล์ค้าง (รวม untracked)  (2) งานอยู่ใน base แล้ว (merge/squash แล้ว)
#           (3) ไม่มีไฟล์ถูกแก้ใน 60 นาทีล่าสุด  (4) ไม่มี process ที่ cwd อยู่ข้างใน
#         ที่เหลือรายงานอย่างเดียว · ไม่ระบุ project = ทุก repo ใน projects.json
# list    แสดง worktree ทั้งหมด + สถานะ (managed/unmanaged, dirty, merged)
#
# ไม่ fetch ตอน prune/list (เร็ว + ไม่ใช้ network) — ใช้ ref ที่มีในเครื่อง

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECTS_JSON="${PROJECTS_JSON:-$SCRIPT_DIR/../projects.json}"
RECENT_MINUTES="${WORKTREE_RECENT_MINUTES:-60}"

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 1; }
die() { echo "worktree: $*" >&2; exit 1; }

# main checkout ของ repo ที่ path นี้อยู่ (แม้ path จะเป็น linked worktree หรือ subdir)
main_repo() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  dirname "$common"
}
managed_root() { local r; r=$(main_repo "$1") || return 1; echo "$(dirname "$r")/$(basename "$r")-worktrees"; }

default_base() {
  local repo="$1" ref
  for ref in origin/develop develop origin/main main origin/master master; do
    git -C "$repo" rev-parse -q --verify "$ref^{commit}" >/dev/null && { echo "$ref"; return 0; }
  done
  return 1
}

is_dirty() { [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]; }

# งานของ HEAD อยู่ใน base แล้วหรือยัง — ancestor (merge commit/ff) หรือ merge แล้วไม่มีอะไรเปลี่ยน (squash)
is_merged() {
  local wt="$1" base="$2" head tree
  head=$(git -C "$wt" rev-parse HEAD 2>/dev/null) || return 1
  git -C "$wt" merge-base --is-ancestor "$head" "$base" 2>/dev/null && return 0
  tree=$(git -C "$wt" merge-tree --write-tree "$base" "$head" 2>/dev/null | head -1) || return 1
  [[ -n "$tree" && "$tree" == "$(git -C "$wt" rev-parse "$base^{tree}")" ]]
}

recently_touched() {
  [[ -n "$(find "$1" -path "$1/node_modules" -prune -o -path "$1/.git" -prune -o \
    -type f -mmin "-${RECENT_MINUTES}" -print 2>/dev/null | head -1)" ]]
}

in_use() {
  local wt="$1"
  [[ -n "${CWDS:-}" ]] || CWDS=$(lsof -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)
  printf '%s\n' "$CWDS" | awk -v w="$wt" '$0 == w || index($0, w "/") == 1 { f = 1 } END { exit !f }'
}

# worktree (ไม่รวม main checkout) ของ repo → "path<TAB>branch"
worktrees_of() {
  local repo="$1"
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v main="$repo" '
    /^worktree / { p = substr($0, 10); b = "(detached)" }
    /^branch /   { b = substr($0, 8); sub("^refs/heads/", "", b) }
    /^$/         { if (p != main) print p "\t" b; p = "" }
    END          { if (p != "" && p != main) print p "\t" b }'
}

# repo ทั้งหมดของ project (หรือของทุก project) จาก projects.json — dedupe ด้วย main checkout
repos_for() {
  local target="${1:-}" paths p
  if [[ -n "$target" && -d "$target" ]]; then
    main_repo "$target" || die "'$target' ไม่ใช่ git repo"
    return 0
  fi
  [[ -f "$PROJECTS_JSON" ]] || die "$PROJECTS_JSON not found"
  if [[ -n "$target" ]]; then
    jq -e --arg p "$target" '.projects[$p]' "$PROJECTS_JSON" >/dev/null || die "project '$target' not in projects.json"
    paths=$(jq -r --arg p "$target" '.projects[$p].paths[]?' "$PROJECTS_JSON")
  else
    paths=$(jq -r '.projects[].paths[]?' "$PROJECTS_JSON")
  fi
  while IFS= read -r p; do
    p="${p/#\~/$HOME}"
    [[ -d "$p" ]] && main_repo "$p" 2>/dev/null || true
  done <<<"$paths" | sort -u
}

cmd_create() {
  local repo="" branch="" base="" copy_env=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base) base="${2:?}"; shift ;;
      --copy-env) copy_env=1 ;;
      -*) die "unknown option $1" ;;
      *) if [[ -z "$repo" ]]; then repo="$1"; elif [[ -z "$branch" ]]; then branch="$1"; else usage; fi ;;
    esac
    shift
  done
  [[ -n "$repo" && -n "$branch" ]] || usage
  repo=$(main_repo "$repo") || die "'$repo' ไม่ใช่ git repo"
  local root path
  root=$(managed_root "$repo")
  path="$root/${branch//\//-}"
  [[ -e "$path" ]] && die "มีอยู่แล้ว: $path (ใช้ตัวเดิม หรือ remove ก่อน)"

  git -C "$repo" fetch -q origin 2>/dev/null || echo "worktree: warning — fetch origin ไม่สำเร็จ ใช้ ref ในเครื่อง" >&2
  mkdir -p "$root"
  if git -C "$repo" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
    git -C "$repo" worktree add -q "$path" "$branch"
  elif git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
    git -C "$repo" worktree add -q --track -b "$branch" "$path" "origin/$branch"
  else
    [[ -n "$base" ]] || base=$(default_base "$repo") || die "หา base branch ไม่เจอ — ระบุ --base"
    git -C "$repo" worktree add -q --no-track -b "$branch" "$path" "$base"
  fi

  if [[ $copy_env -eq 1 ]]; then
    local f rel
    while IFS= read -r f; do
      rel="${f#"$repo"/}"
      mkdir -p "$(dirname "$path/$rel")"
      cp "$f" "$path/$rel"
      echo "  copied $rel"
    done < <(git -C "$repo" ls-files --others --ignored --exclude-standard -- '.env*' '*/.env*' 2>/dev/null \
               | grep -v node_modules | sed "s|^|$repo/|")
  fi
  echo "✓ worktree $branch ($(git -C "$path" rev-parse --short HEAD))"
  echo "$path"
}

cmd_remove() {
  local wt="" force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1 ;;
      -*) die "unknown option $1" ;;
      *) wt="$1" ;;
    esac
    shift
  done
  [[ -n "$wt" ]] || usage
  [[ -d "$wt" ]] || die "ไม่พบ $wt"
  wt=$(cd "$wt" && pwd -P)
  local repo branch base
  repo=$(main_repo "$wt") || die "'$wt' ไม่ใช่ git worktree"
  [[ "$(git -C "$wt" rev-parse --show-toplevel)" != "$repo" ]] || die "'$wt' คือ main checkout — ลบไม่ได้"
  if is_dirty "$wt" && [[ $force -eq 0 ]]; then
    git -C "$wt" status --short | head -10 >&2
    die "มีไฟล์ค้างใน $wt — commit ก่อน หรือ --force เพื่อทิ้ง"
  fi
  branch=$(git -C "$wt" symbolic-ref -q --short HEAD || true)
  if [[ $force -eq 1 ]]; then git -C "$repo" worktree remove --force "$wt"; else git -C "$repo" worktree remove "$wt"; fi
  git -C "$repo" worktree prune
  echo "✓ removed $wt"
  if [[ -n "$branch" ]] && base=$(default_base "$repo"); then
    if git -C "$repo" merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
      git -C "$repo" branch -q -d "$branch" 2>/dev/null && echo "✓ deleted local branch $branch (merged into $base)"
    fi
  fi
  rmdir "$(dirname "$wt")" 2>/dev/null || true   # ลบ <repo>-worktrees/ ถ้าว่าง
}

# describe <repo> <path> <branch> → "managed|unmanaged dirty|clean merged|unmerged|nobase"
describe() {
  local repo="$1" wt="$2" kind="unmanaged" st="clean" mg="unmerged" base
  [[ "$wt" == "$(managed_root "$repo")/"* ]] && kind="managed"
  if [[ ! -d "$wt" ]]; then echo "$kind missing -"; return; fi
  is_dirty "$wt" && st="dirty"
  if base=$(default_base "$repo"); then is_merged "$wt" "$base" && mg="merged"; else mg="nobase"; fi
  echo "$kind $st $mg"
}

cmd_list() {
  local repo wt branch d
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    local out
    out=$(worktrees_of "$repo")
    [[ -n "$out" ]] || continue
    echo "$repo"
    while IFS=$'\t' read -r wt branch; do
      d=$(describe "$repo" "$wt")
      printf '  %-40s %-24s %s\n' "${wt/#$HOME/~}" "$branch" "$d"
    done <<<"$out"
  done < <(repos_for "${1:-}")
}

cmd_prune() {
  local target="" dry=0 quiet=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry=1 ;;
      --quiet) quiet=1 ;;
      -*) die "unknown option $1" ;;
      *) target="$1" ;;
    esac
    shift
  done
  local repo wt branch kind st mg removed=0 kept=0 reason
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    git -C "$repo" worktree prune 2>/dev/null || true   # registration ของ dir ที่หายไปแล้ว
    while IFS=$'\t' read -r wt branch; do
      [[ -n "$wt" ]] || continue
      read -r kind st mg < <(describe "$repo" "$wt")
      [[ "$kind" == "managed" ]] || continue
      reason=""
      [[ "$st" == "dirty" ]] && reason="มีไฟล์ค้าง"
      [[ -z "$reason" && "$mg" != "merged" ]] && reason="ยังไม่ merge"
      [[ -z "$reason" ]] && recently_touched "$wt" && reason="มีการแก้ใน ${RECENT_MINUTES} นาที"
      [[ -z "$reason" ]] && in_use "$wt" && reason="มี process ใช้อยู่"
      if [[ -n "$reason" ]]; then
        kept=$((kept + 1))
        [[ $quiet -eq 1 && "$reason" == "ยังไม่ merge" ]] && continue
        echo "  keep   ${wt/#$HOME/~} ($branch) — $reason"
        continue
      fi
      if [[ $dry -eq 1 ]]; then
        echo "  would remove ${wt/#$HOME/~} ($branch)"
      else
        cmd_remove "$wt" >/dev/null && echo "  removed ${wt/#$HOME/~} ($branch)"
      fi
      removed=$((removed + 1))
    done < <(worktrees_of "$repo")
  done < <(repos_for "$target")
  if [[ $quiet -eq 0 || $removed -gt 0 ]]; then
    echo "worktree prune: $([[ $dry -eq 1 ]] && echo 'would remove' || echo 'removed') $removed, kept $kept"
  fi
}

CMD="${1:-}"; shift || true
case "$CMD" in
  create) cmd_create "$@" ;;
  remove) cmd_remove "$@" ;;
  prune)  cmd_prune "$@" ;;
  list)   cmd_list "$@" ;;
  *) usage ;;
esac
