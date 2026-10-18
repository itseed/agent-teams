#!/usr/bin/env bash
# heavy.sh — run ONE heavy job (test/e2e/build/tsc/docker build) at a time, machine-wide
#
# Usage:
#   ./scripts/heavy.sh [--timeout MIN] [--no-gate] [--] <command...>
#   ./scripts/heavy.sh status            # who holds the lock, since when, machine load/swap
#
# Examples:
#   heavy.sh npx jest src/km --maxWorkers=2
#   heavy.sh --timeout 40 npx playwright test e2e/km.spec.ts --workers=1
#   heavy.sh bash -c 'cd apps/api && npm run build'     # pipes/&&/cd → wrap in bash -c
#
# 1. lock   — /usr/bin/lockf on $HEAVY_LOCK; the kernel releases it when the process dies
#             (never mkdir-lock or delete the lock file). Nested heavy.sh calls run straight through.
# 2. gate   — wait until load avg (1 min) < HEAVY_MAX_LOAD and memory is not under pressure: macOS
#             kern.memorystatus_level (system-wide memory free %) >= HEAVY_MIN_MEM_FREE_PCT, **or** free swap
#             >= HEAVY_MIN_SWAP_FREE_PCT %. Swap alone is a stale signal — pages swapped out hours ago stay there
#             while RAM is free again, and the gate then waited the full max wait on every job (2026-10-15:
#             swap free 6% vs memory free 56%). At most HEAVY_GATE_MAX_WAIT s — then run anyway with a warning.
# 3. run    — `nice`, in its own process group; past the timeout → TERM the whole group, KILL after 10 s,
#             exit 124 (a hung jest/`wait` can no longer hold the lock for hours)
#
# Quiet mode (the owner is using the Mac): `heavy.sh quiet on|off`, or the file $HEAVY_LOCK→.quiet exists.
#   - gate max load drops to HEAVY_QUIET_MAX_LOAD (10 = core count)
#   - the job runs under `taskpolicy -b` (macOS background QoS: efficiency cores, throttled disk I/O)
#   - gate still busy after the max wait → do NOT run; exit 75 so the agent retries later (not a test failure)
#   - `HEAVY_QUIET=0 heavy.sh <cmd>` opts one job out (normal QoS, max load 16) — for timing-sensitive tests only
#
# The agent PreToolUse hook (scripts/heavy-guard.sh) blocks heavy commands that skip this wrapper.
#
# Env: HEAVY_LOCK (/tmp/agent-teams-heavy.lock) · HEAVY_TIMEOUT_MIN (20) · HEAVY_MAX_LOAD (16)
#      HEAVY_MIN_MEM_FREE_PCT (30) · HEAVY_MIN_SWAP_FREE_PCT (12) · HEAVY_GATE_MAX_WAIT (600) · HEAVY_GATE_POLL (15)
# Exit: the command's own code · 124 timeout · 75 quiet mode: machine still busy, not run · 2 usage

set -uo pipefail

LOCK="${HEAVY_LOCK:-/tmp/agent-teams-heavy.lock}"
HOLDER="${LOCK%.lock}.holder"
TIMEOUT_MIN="${HEAVY_TIMEOUT_MIN:-20}"
MAX_LOAD="${HEAVY_MAX_LOAD:-16}"
MIN_SWAP_FREE_PCT="${HEAVY_MIN_SWAP_FREE_PCT:-12}"
MIN_MEM_FREE_PCT="${HEAVY_MIN_MEM_FREE_PCT:-30}"
GATE_MAX_WAIT="${HEAVY_GATE_MAX_WAIT:-600}"
GATE_POLL="${HEAVY_GATE_POLL:-15}"
QUIET_FILE="${LOCK%.lock}.quiet"
QUIET=0
# HEAVY_QUIET=0 on one call: run that job at normal priority (e.g. a timing-sensitive test), gate unchanged
if [[ -f "$QUIET_FILE" && "${HEAVY_QUIET:-1}" != "0" ]]; then QUIET=1; MAX_LOAD="${HEAVY_QUIET_MAX_LOAD:-10}"; fi

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
log() { echo "heavy: $*" >&2; }

load1() { sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}'; }
# free swap % (macOS grows swap on demand; no swap file yet → 100)
swap_free_pct() {
  sysctl -n vm.swapusage 2>/dev/null | awk '{
    for (i = 1; i <= NF; i++) { if ($i == "total") t = $(i+2); if ($i == "free") f = $(i+2) }
    gsub(/M/, "", t); gsub(/M/, "", f)
    if (t + 0 == 0) print 100; else printf "%d\n", f * 100 / t }'
}
# system-wide memory free % as macOS's memory-pressure logic sees it (unknown → 0, i.e. fall back to swap)
mem_free_pct() { local v; v=$(sysctl -n kern.memorystatus_level 2>/dev/null); [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0; }
machine() { echo "load $(load1) (max $MAX_LOAD) · mem free $(mem_free_pct)% (min $MIN_MEM_FREE_PCT%) · swap free $(swap_free_pct)% (min $MIN_SWAP_FREE_PCT%)"; }
gate_ok() {
  awk -v l="$(load1)" -v m="$MAX_LOAD" 'BEGIN { exit !(l + 0 < m + 0) }' && \
    { [[ "$(mem_free_pct)" -ge "$MIN_MEM_FREE_PCT" ]] || [[ "$(swap_free_pct)" -ge "$MIN_SWAP_FREE_PCT" ]]; }
}

if [[ "${1:-}" == "quiet" ]]; then
  case "${2:-}" in
    on)  date '+%F %T' > "$QUIET_FILE"; echo "quiet mode: ON (max load ${HEAVY_QUIET_MAX_LOAD:-10}, background QoS, busy → exit 75)" ;;
    off) rm -f "$QUIET_FILE"; echo "quiet mode: OFF" ;;
    *)   [[ $QUIET -eq 1 ]] && echo "quiet mode: ON since $(cat "$QUIET_FILE")" || echo "quiet mode: OFF" ;;
  esac
  exit 0
fi

if [[ "${1:-}" == "status" ]]; then
  if /usr/bin/lockf -ks -t 0 "$LOCK" true 2>/dev/null; then
    echo "lock: free"
  else
    echo "lock: HELD"
    [[ -f "$HOLDER" ]] && {
      read -r _ start _ < "$HOLDER"
      echo "  held for $(( ($(date +%s) - start) / 60 )) min — $(cat "$HOLDER")"
    }
  fi
  echo "machine: $(machine)"
  [[ $QUIET -eq 1 ]] && echo "quiet mode: ON since $(cat "$QUIET_FILE")"
  exit 0
fi

GATE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout) [[ "${2:-}" =~ ^[0-9]+$ ]] || usage; TIMEOUT_MIN="$2"; shift 2 ;;
    --no-gate) GATE=0; shift ;;
    --) shift; break ;;
    -h|--help) usage ;;
    -*) log "unknown option $1"; usage ;;
    *) break ;;
  esac
done
[[ $# -gt 0 ]] || usage

# Already inside a heavy.sh (e.g. a test script that calls heavy.sh again) → the outer holds the lock
if [[ -n "${HEAVY_HELD:-}" ]]; then exec "$@"; fi

# Re-exec under the lock: lockf waits for the lock, runs us, and the kernel frees it when we exit
if [[ -z "${HEAVY_LOCKED:-}" ]]; then
  if ! /usr/bin/lockf -ks -t 0 "$LOCK" true 2>/dev/null; then
    log "รอคิว — งานหนักอื่นกำลังรันอยู่: $(cat "$HOLDER" 2>/dev/null || echo '?')"
  fi
  opts=(--timeout "$TIMEOUT_MIN"); [[ $GATE -eq 0 ]] && opts+=(--no-gate)
  HEAVY_LOCKED=1 exec /usr/bin/lockf -k "$LOCK" "$0" "${opts[@]}" -- "$@"
fi

# --- holding the lock ---
rm -f "$HOLDER.timeout"
if [[ $GATE -eq 1 ]] && ! gate_ok; then
  log "เครื่องยังหนัก ($(machine)) — รอสูงสุด ${GATE_MAX_WAIT}s"
  waited=0
  while ! gate_ok && [[ $waited -lt $GATE_MAX_WAIT ]]; do sleep "$GATE_POLL"; waited=$((waited + GATE_POLL)); done
  if ! gate_ok; then
    if [[ $QUIET -eq 1 ]]; then
      log "QUIET MODE: รอครบ ${GATE_MAX_WAIT}s เครื่องยังหนัก ($(machine)) — ยังไม่รัน (exit 75)."
      log "นี่ไม่ใช่ test fail: รอสักครู่แล้วรันคำสั่งเดิมใหม่ — เจ้าของเครื่องกำลังใช้งาน"
      exit 75
    fi
    log "WARNING: รอครบ ${GATE_MAX_WAIT}s เครื่องยังหนัก ($(machine)) — รันต่อ"
  fi
fi

printf '%s %s %s cwd=%s cmd=%s\n' "$$" "$(date +%s)" "$(date '+%H:%M:%S')" "$PWD" "$*" > "$HOLDER"

# own process group (pid == pgid) so the timeout kills every child (servers, workers), not just the
# top one — perl setpgrp, since bash `set -m` can fail with "setpgid: Operation not permitted"
# shellcheck disable=SC2016  # $ARGV is perl, not shell
qos=(); [[ $QUIET -eq 1 ]] && qos=(/usr/sbin/taskpolicy -b)
HEAVY_HELD=1 nice -n 10 ${qos[@]+"${qos[@]}"} perl -e 'setpgrp(0, 0); exec { $ARGV[0] } @ARGV; print STDERR "heavy: $ARGV[0]: $!\n"; exit 127' -- "$@" &
pid=$!

# shellcheck disable=SC2329  # invoked via trap
cleanup() {
  [[ -n "${wd:-}" ]] && kill "$wd" 2>/dev/null   # its TERM trap also kills its sleep
  kill -TERM -"$pid" 2>/dev/null
  rm -f "$HOLDER"
}
trap 'cleanup; exit 130' INT TERM HUP

# watchdog: past the timeout → mark, TERM the whole group, KILL it 10 s later (ignored TERM)
# Its sleeps run in the background with fds on /dev/null and die with the watchdog (TERM trap): an orphaned
# sleep used to keep the caller's stdout pipe open, so `heavy.sh … | tail` hung for the whole timeout.
(
  s=""
  trap '[[ -n "$s" ]] && kill "$s" 2>/dev/null; exit 0' TERM
  nap() { sleep "$1" </dev/null >/dev/null 2>&1 & s=$!; wait "$s"; s=""; }
  nap "${HEAVY_TIMEOUT_SEC:-$((TIMEOUT_MIN * 60))}"   # HEAVY_TIMEOUT_SEC: tests only
  kill -0 "$pid" 2>/dev/null || exit 0
  touch "$HOLDER.timeout"
  log "TIMEOUT ${TIMEOUT_MIN} min — kill process group $pid: $*"
  kill -TERM -"$pid" 2>/dev/null; nap 10; kill -KILL -"$pid" 2>/dev/null
) &
wd=$!
disown "$wd"   # no "Terminated" job notice when we kill it

wait "$pid"; rc=$?
kill "$wd" 2>/dev/null   # its TERM trap also kills its sleep
if [[ -f "$HOLDER.timeout" ]]; then
  # top process died on TERM but group members may ignore it → KILL them after 10 s
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -g "$pid" >/dev/null || break; sleep 1; done
  kill -KILL -"$pid" 2>/dev/null
  rm -f "$HOLDER" "$HOLDER.timeout"
  exit 124
fi
rm -f "$HOLDER"
exit "$rc"
