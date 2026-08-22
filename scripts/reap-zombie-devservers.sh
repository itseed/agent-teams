#!/usr/bin/env bash
# reap-zombie-devservers.sh — SessionStart hook.
#
# Trigger: fires on every new session start (including the first prompt after
# an abnormal exit — iTerm force-quit, computer sleep interrupting an agent,
# a crashed pane). This is the crash-recovery counterpart to
# cleanup-dev-on-close.sh, which only fires on a graceful "จบงาน" close and
# therefore never runs when the terminal is killed out from under it.
#
# Root cause this guards against (observed 2026-08-22): each agent
# (backend/frontend/QA) starts its own dev server (`npm run dev`,
# `nest start --watch`, etc.) in the shared project working directory without
# checking whether one is already running. When a session ends abnormally,
# the dev server's parent shell dies but the dev server child does not — it
# gets reparented to launchd (ppid=1) and keeps running, sometimes for days,
# burning CPU/RAM. A single stale session left 15 such orphans running,
# several pinned above 50% CPU.
#
# Scope/safety: only touches TCP-LISTENing processes that are ALL THREE of:
# (a) orphaned — ppid == 1, the signal that their owning shell/agent is gone;
# (b) whose own cwd resolves under one of the *currently active* project's
#     paths (from projects.json) — never touches processes outside project
#     scope; (c) older than AGE_THRESHOLD_SECS. (b) alone is not enough: some
#     watch-mode tools (observed with `nest start --watch`) legitimately
#     reparent a freshly-(re)started, still-in-use process to ppid=1 within
#     seconds of a restart — killing on ppid=1 alone caught a live server
#     during this script's own pipe-test. The age gate is what actually
#     distinguishes "crash leftover from a past session" (the problem this
#     hook exists for; SessionStart fires before this session has done
#     anything, so anything already running is by definition NOT this
#     session's work) from "a watch-tool's normal restart quirk." A process
#     with a live parent is never touched regardless of age — it may be a
#     dev server someone is about to use. Uses SIGTERM, not -9. If nothing
#     matches, prints {} and exits 0 fast.
#
# Usage (also runnable by hand, e.g. from Lead when the user reports the
# machine feels slow — note manual runs mid-session can still hit the same
# watch-restart race the age gate is guarding against if run within
# AGE_THRESHOLD_SECS of a legitimate restart):
#   ./scripts/reap-zombie-devservers.sh

set -euo pipefail

AGE_THRESHOLD_SECS=600

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"

[[ -f "$PROJECTS_JSON" ]] || { echo '{}'; exit 0; }

ACTIVE=$(jq -r '.active // empty' "$PROJECTS_JSON")
[[ -n "$ACTIVE" ]] || { echo '{}'; exit 0; }

PATHS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && PATHS+=("$p")
done < <(jq -r --arg p "$ACTIVE" '.projects[$p].paths // {} | to_entries[] | .value' "$PROJECTS_JSON" | sort -u)

KILLED=()

for path in "${PATHS[@]:-}"; do
  [[ -n "$path" && -d "$path" ]] || continue

  while read -r pid; do
    [[ -z "$pid" ]] && continue
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ "$ppid" == "1" ]] || continue

    etimes=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [[ -n "$etimes" && "$etimes" -ge "$AGE_THRESHOLD_SECS" ]] || continue

    cwd=$(lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | awk '/^n/{sub(/^n/,""); print; exit}')
    [[ "$cwd" == "$path"* ]] || continue

    if kill -TERM "$pid" 2>/dev/null; then
      KILLED+=("$pid:$path")
    fi
  done < <(lsof -nP -iTCP -sTCP:LISTEN -t 2>/dev/null | sort -u)
done

if [[ ${#KILLED[@]} -eq 0 ]]; then
  echo '{}'
  exit 0
fi

MSG="🧟 พบ dev server ที่ค้าง (orphaned, ppid=1) จาก session ก่อนหน้า — kill แล้ว ${#KILLED[@]} ตัว: ${KILLED[*]}"
jq -n --arg m "$MSG" '{systemMessage: $m}'
