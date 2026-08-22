#!/usr/bin/env bash
# cleanup-dev-on-close.sh — UserPromptSubmit hook.
#
# Trigger: user's prompt contains a "closing/wrapping up" phrase (Thai or English).
# Action: kill dev-server processes whose cwd sits under the Active Project's paths
# (from projects.json), then clear known JS/TS cache dirs (.next, .turbo, .cache,
# node_modules/.cache) under those same paths. Prints a JSON systemMessage so the
# user sees what happened (silent side effects are worse than no hook at all).
#
# Scope/safety: only touches processes whose OWN cwd resolves under a path listed
# for the *currently active* project in projects.json — never a blind kill-by-port.
# Uses SIGTERM, not -9. If nothing matches, prints {} and exits 0 fast.
#
# Limitation (documented, not silently hidden): keyword match is a fixed regex,
# not true semantic understanding — it will miss unlisted phrasings and can
# false-positive on a sentence that happens to contain a matched substring
# (e.g. an issue title). Extend KEYWORDS below as new phrasings show up.

set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
PROJECTS_JSON="$SCRIPT_DIR/projects.json"

KEYWORDS='จบงาน|จบแล้ว|เสร็จงาน(แล้ว)?|ปิดงาน(แล้ว)?|หยุดได้(แล้ว)?|พอแค่นี้|ปิดจบ|เลิกงาน|end of work|wrap(ping)? up|call it a day|done for (today|now)|that.?s all for (today|now)'

PROMPT="$(jq -r '.prompt // empty' 2>/dev/null || true)"

if [[ -z "$PROMPT" ]] || ! echo "$PROMPT" | grep -qiE "$KEYWORDS"; then
  echo '{}'
  exit 0
fi

[[ -f "$PROJECTS_JSON" ]] || { echo '{}'; exit 0; }

ACTIVE=$(jq -r '.active // empty' "$PROJECTS_JSON")
[[ -n "$ACTIVE" ]] || { echo '{}'; exit 0; }

PATHS=()
while IFS= read -r p; do
  [[ -n "$p" ]] && PATHS+=("$p")
done < <(jq -r --arg p "$ACTIVE" '.projects[$p].paths // {} | to_entries[] | .value' "$PROJECTS_JSON" | sort -u)

KILLED=()
CLEARED=()
CACHE_DIRS=(".next" ".turbo" ".cache" "node_modules/.cache")

for path in "${PATHS[@]:-}"; do
  [[ -n "$path" && -d "$path" ]] || continue

  # every PID currently LISTENing on a TCP port, deduped
  while read -r pid; do
    [[ -z "$pid" ]] && continue
    cwd=$(lsof -p "$pid" -a -d cwd -Fn 2>/dev/null | awk '/^n/{sub(/^n/,""); print; exit}')
    [[ "$cwd" == "$path"* ]] || continue
    if kill -TERM "$pid" 2>/dev/null; then
      KILLED+=("$pid:$path")
    fi
  done < <(lsof -nP -iTCP -sTCP:LISTEN -t 2>/dev/null | sort -u)
done

# Give killed processes a moment to actually exit and release file handles
# before touching their cache dirs — rm -rf can hit "Directory not empty"
# transiently if it races a process still flushing a webpack/turbo cache.
if [[ ${#KILLED[@]} -gt 0 ]]; then
  sleep 1.5
fi

for path in "${PATHS[@]:-}"; do
  [[ -n "$path" && -d "$path" ]] || continue
  for cache in "${CACHE_DIRS[@]}"; do
    d="$path/$cache"
    [[ -d "$d" ]] || continue
    # retry once — a slow-to-exit process can still be mid-flush after the sleep
    if ! rm -rf "$d" 2>/dev/null; then
      sleep 1
      rm -rf "$d" 2>/dev/null || true
    fi
    [[ -d "$d" ]] || CLEARED+=("$d")
  done
done

if [[ ${#KILLED[@]} -eq 0 && ${#CLEARED[@]} -eq 0 ]]; then
  echo '{}'
  exit 0
fi

MSG="🧹 จบงาน — cleanup: "
[[ ${#KILLED[@]} -gt 0 ]] && MSG+="killed ${#KILLED[@]} dev process(es) (${KILLED[*]}); "
[[ ${#CLEARED[@]} -gt 0 ]] && MSG+="cleared cache: ${CLEARED[*]}"

jq -n --arg m "$MSG" '{systemMessage: $m}'
