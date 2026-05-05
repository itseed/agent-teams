#!/usr/bin/env bash
# install.sh — one-command setup for agent-teams
# Usage: ./install.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKG_MANAGER=""

# Status tracking (used by verify())
# shellcheck disable=SC2034  # forward-declared globals, used by functions added in later tasks
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
        echo "  ℹ No supported package manager found (brew/apt-get) — install deps manually if needed"
      fi
      ;;
    *)
      PKG_MANAGER=""
      echo "  ⚠ Unsupported OS: $os — install tmux and jq manually"
      ;;
  esac
}

check_deps() {
  echo ""
  echo "Checking dependencies..."
  local missing=()

  if command -v tmux >/dev/null 2>&1; then
    echo "  ✓ tmux $(tmux -V | awk '{print $2}')"
    TMUX_OK=true
  else
    missing+=("tmux")
  fi

  if command -v jq >/dev/null 2>&1; then
    echo "  ✓ jq $(jq --version | sed 's/^jq-//')"
    JQ_OK=true
  else
    missing+=("jq")
  fi

  [[ ${#missing[@]} -eq 0 ]] && return 0

  echo "  ✗ Missing: ${missing[*]}"

  if [[ -z "$PKG_MANAGER" ]]; then
    echo "  → Install manually: ${missing[*]}"
    return 0
  fi

  printf "  Install missing deps with %s? [y/N] " "$PKG_MANAGER"
  read -r ans
  if [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]]; then
    echo "  → Skipped. Install manually: ${missing[*]}"
    return 0
  fi

  for pkg in "${missing[@]}"; do
    echo "  → Installing $pkg..."
    if [[ "$PKG_MANAGER" == "brew" ]]; then
      brew install "$pkg"
    else
      sudo apt-get install -y "$pkg"
    fi
    if command -v "$pkg" >/dev/null 2>&1; then
      [[ "$pkg" == "tmux" ]] && TMUX_OK=true
      [[ "$pkg" == "jq" ]] && JQ_OK=true
      echo "  ✓ $pkg installed"
    else
      echo "  ✗ $pkg install failed — install manually"
    fi
  done
}

setup_claude() {
  echo ""
  echo "Checking Claude CLI..."

  if command -v claude >/dev/null 2>&1; then
    echo "  ✓ claude found"
    CLAUDE_OK=true
    return 0
  fi

  echo "  ✗ claude not found"
  printf "  Install it now? (npm install -g @anthropic-ai/claude-code) [y/N] "
  read -r ans

  if [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]]; then
    echo "  → Install manually: https://claude.ai/code"
    return 0
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "  ✗ npm not found — install Node.js first: https://nodejs.org"
    return 0
  fi

  npm install -g @anthropic-ai/claude-code

  if command -v claude >/dev/null 2>&1; then
    echo "  ✓ claude installed"
    CLAUDE_OK=true
  else
    echo "  ✗ Installation may have failed — check npm output above"
  fi
}

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  check_deps
  setup_claude
}

main "$@"
