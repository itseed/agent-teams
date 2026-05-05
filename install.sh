#!/usr/bin/env bash
# install.sh — one-command setup for agent-teams
# Usage: ./install.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_MANAGER=""

# Status tracking (used by verify())
TMUX_OK=false
JQ_OK=false
CLAUDE_OK=false
PROJECTS_OK=false
SCRIPTS_OK=false
SNYK_CONFIGURED=false

check_os() {
  local os
  os=$(uname -s)
  case "$os" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        PKG_MANAGER="brew"
      else
        PKG_MANAGER=""
        echo "  ℹ homebrew not found — install deps manually if needed"
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt-get"
      else
        PKG_MANAGER=""
        echo "  ℹ apt-get not found — install deps manually if needed"
      fi
      ;;
    *)
      PKG_MANAGER=""
      echo "  ⚠ Unsupported OS: $os — install tmux and jq manually"
      ;;
  esac
}

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  echo "  PKG_MANAGER=${PKG_MANAGER:-none}"
}

main "$@"
