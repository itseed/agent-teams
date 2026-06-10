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
# <pane> can be a stable pane id (%3) or a target (dev-team:0.0).

set -euo pipefail

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

# Load into a tmux buffer (multiline/quote-safe) and paste
printf '%s' "$MSG" | tmux load-buffer -
tmux paste-buffer -t "$PANE"

# Let Claude Code ingest the pasted input before submitting
sleep 0.5
tmux send-keys -t "$PANE" Enter

# Confirm it submitted; nudge if the prompt is stuck holding queued input
i=0
while [[ $i -lt 3 ]]; do
  sleep 0.5
  if ! tmux capture-pane -t "$PANE" -p 2>/dev/null | tail -6 \
       | grep -q "Press up to edit queued"; then
    exit 0   # input box is clear → submitted
  fi
  if [[ $i -eq 1 ]]; then tmux send-keys -t "$PANE" Escape; fi
  tmux send-keys -t "$PANE" Enter
  i=$((i + 1))
done

echo "team-send: warning — could not confirm submit on '$PANE'; check the pane manually" >&2
exit 0
