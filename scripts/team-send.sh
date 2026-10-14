#!/usr/bin/env bash
# team-send.sh — paste a message into a tmux pane and submit it reliably.
#
# Usage:
#   team-send.sh <pane> "message"          # message as argument
#   echo "message" | team-send.sh <pane>   # message on stdin (multiline/quote-safe)
#
# Why: tmux paste-buffer is fire-and-forget. This wraps the paste + the
# sleep-before-Enter race + the "prompt stuck in input box" footgun
# (retries Enter, then Esc+Enter) so Lead/agents don't have to hand-roll it.
#
# <pane> can be a stable pane id (%3) or a target (dev-team:0.0 for v1,
# dev-team-v2:0.0 for v2).

set -euo pipefail

# Byte-wise text handling. macOS awk's substr counts bytes, so FRAG can end in
# the middle of a multi-byte (e.g. Thai) character; grep in a UTF-8 locale then
# fails with "illegal byte sequence" (rc 2) and pending() reports a false
# "submitted". In the C locale awk and grep both work on bytes, which matches.
export LC_ALL=C

PANE="${1:?usage: team-send.sh <pane> [message]   (message on stdin if omitted)}"
shift || true

# Resolve message: prefer args, else stdin (must be piped, not a tty)
if [[ $# -gt 0 ]]; then
  MSG="$*"
elif [[ ! -t 0 ]]; then
  MSG="$(cat)"
else
  echo "team-send: no message (pass as arg or pipe via stdin)" >&2
  exit 1
fi
[[ -n "$MSG" ]] || { echo "team-send: empty message" >&2; exit 1; }

# Validate pane exists (capture-pane is strict about its target, unlike display-message)
tmux capture-pane -t "$PANE" -p >/dev/null 2>&1 \
  || { echo "team-send: pane '$PANE' not found" >&2; exit 1; }

# Strip ONE trailing newline (an extra Enter inside the paste would split/submit early)
MSG="${MSG%$'\n'}"
[[ -n "$MSG" ]] || { echo "team-send: empty message" >&2; exit 1; }

# A short piece of the first non-empty line, used to spot the message still
# sitting in the input box (long pastes collapse to "[Pasted text #N ...]")
FRAG="$(printf '%s\n' "$MSG" | awk 'NF{sub(/^[ \t]+/,""); print substr($0,1,20); exit}')"

capture() { tmux capture-pane -t "$PANE" -p 2>/dev/null || true; }

# Text of Claude Code's input box = lines between the last two ──── rules
input_box() {
  capture | awk '{ l[NR]=$0 } index($0,"────────")==1 { p=r; r=NR }
                 END { if (p && r) for (i=p+1; i<r; i++) print l[i] }'
}

# pending = our message (or its paste chip) is still unsubmitted in the input box
pending() {
  local box; box="$(input_box)"
  [[ -n "$box" ]] || return 1
  grep -qF -- "[Pasted text" <<<"$box" && return 0
  [[ -n "$FRAG" ]] && grep -qF -- "$FRAG" <<<"$box"
}

# busy = agent mid-turn; never send Esc then (it would interrupt the turn)
# shellcheck source=lib/pane.sh
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/lib/pane.sh"
busy()   { pane_busy "$PANE"; }
queued() { capture | tail -15 | grep -q "Press up to edit queued"; }

# Wait until the pane stops changing (paste ingested), max ~3s
settle() {
  local prev="" cur i=0
  while [[ $i -lt 15 ]]; do
    sleep 0.2
    cur="$(capture)"
    [[ $i -gt 0 && "$cur" == "$prev" ]] && return 0
    prev="$cur"; i=$((i + 1))
  done
}

# Bracketed paste (-p) from a private buffer (-d deletes it afterwards) so
# multi-line text lands as one paste instead of line-by-line keystrokes
BUF="team-send-$$"
printf '%s' "$MSG" | tmux load-buffer -b "$BUF" -
tmux paste-buffer -p -d -b "$BUF" -t "$PANE"

settle
tmux send-keys -t "$PANE" Enter

# Verify: input box no longer holds our text (or it was queued behind a busy
# turn, which Claude Code delivers itself). Retry Enter, then Esc+Enter.
for attempt in 1 2 3 4; do
  sleep 0.5
  if queued || ! pending; then exit 0; fi
  [[ $attempt -eq 4 ]] && break
  if [[ $attempt -eq 3 ]] && ! busy; then
    tmux send-keys -t "$PANE" Escape
    sleep 0.2
  fi
  tmux send-keys -t "$PANE" Enter
done

echo "team-send: warning — message still in the input box of '$PANE'; check the pane manually" >&2
exit 1
