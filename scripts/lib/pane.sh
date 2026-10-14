# shellcheck shell=bash
# scripts/lib/pane.sh — read a Claude Code pane's screen (sourced by team-send.sh / dispatch.sh)
#
# Single source of the "is Claude mid-turn?" screen pattern. dashboard/state.py keeps a copy of
# PANE_BUSY_RE and dashboard/test_state.py fails if the two differ — update both together.
#
# Claude Code shows "esc to interrupt" only in the footer, which narrow panes cut to
# "esc to interru…", so also match the spinner's elapsed time: "✶ Grooving… (1m 58s · …".
# A finished turn reads "✻ Sautéed for 20s" (no "… (") and does not match.
PANE_BUSY_RE='esc to interr|… \(([0-9]+m )?[0-9]+s'

# pane_busy <pane> — 0 if Claude is mid-turn (last 15 lines of the screen)
# (screen captured into a variable first: with pipefail, `| grep -q` exiting early could SIGPIPE tail)
pane_busy() {
  local screen
  screen=$(tmux capture-pane -t "$1" -p 2>/dev/null | tail -15) || true
  grep -qiE "$PANE_BUSY_RE" <<<"$screen"
}
