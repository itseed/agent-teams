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

setup_projects() {
  echo ""
  echo "Setting up projects.json..."

  local projects_file="$SCRIPT_DIR/projects.json"
  local example_file="$SCRIPT_DIR/projects.json.example"

  if [[ -f "$projects_file" ]]; then
    echo "  ✓ projects.json already exists, skipping"
    PROJECTS_OK=true
  elif [[ ! -f "$example_file" ]]; then
    echo "  ✗ projects.json.example not found — run from repo root?"
    return 1
  else
    cp "$example_file" "$projects_file"
    echo "  ✓ Copied projects.json.example → projects.json"
    echo "  → Edit it to add your project paths:"
    echo "    nano $projects_file"
    PROJECTS_OK=true
  fi

  echo ""
  echo "Making scripts executable..."
  local any_found=false
  for script in start-team.sh stop-team.sh; do
    if [[ -f "$SCRIPT_DIR/$script" ]]; then
      chmod +x "$SCRIPT_DIR/$script"
      echo "  ✓ $script"
      any_found=true
    fi
  done
  $any_found && SCRIPTS_OK=true
}

_patch_reviewer() {
  local reviewer="$SCRIPT_DIR/.claude/agents/reviewer.md"

  if [[ ! -f "$reviewer" ]]; then
    echo "  ✗ .claude/agents/reviewer.md not found — skipping patch"
    return 0
  fi

  if grep -q "snyk test" "$reviewer"; then
    echo "  → reviewer.md already has Snyk workflow"
    return 0
  fi

  python3 - "$reviewer" <<'PYEOF'
import sys, re

path = sys.argv[1]
snyk_block = (
    "2. **รัน Snyk scan ก่อน manual review เสมอ**"
    " (ถ้า working directory มี package.json/requirements.txt/etc.)\n"
    "   ```bash\n"
    "   snyk test --severity-threshold=high 2>&1 | head -60\n"
    "   ```\n"
    "   - ถ้าพบ **critical/high** → flag ทันที ก่อน review ต่อ\n"
    "   - แนบ snyk output สรุปไว้ใน review report\n"
)
content = open(path).read()
new_content = re.sub(
    r'(1\. อ่าน task จาก shared task list\n)',
    lambda m: m.group(0) + snyk_block + "\n",
    content, count=1
)
if new_content == content:
    sys.stderr.write("  ✗ Could not find insertion point in reviewer.md\n")
    sys.exit(1)
open(path, "w").write(new_content)
print("  ✓ Injected Snyk workflow into .claude/agents/reviewer.md")
PYEOF
}

setup_snyk() {
  echo ""
  printf "Set up Snyk for security scanning? [y/N] "
  read -r ans
  [[ "${ans:-N}" != "y" && "${ans:-N}" != "Y" ]] && return 0

  local settings="$HOME/.claude/settings.json"

  # Check if already configured
  if [[ -f "$settings" ]] && jq -e '.env.SNYK_TOKEN' "$settings" >/dev/null 2>&1; then
    echo "  → SNYK_TOKEN already configured in ~/.claude/settings.json"
    SNYK_CONFIGURED=true
    _patch_reviewer
    return 0
  fi

  echo ""
  echo "  Get your token from one of these:"
  echo "    1. Run:   snyk config get api"
  echo "    2. Visit: https://app.snyk.io/account → Auth Token"
  echo ""

  local token=""
  local attempts=0
  while [[ -z "$token" && $attempts -lt 2 ]]; do
    printf "  Paste token: "
    read -rs token
    echo ""
    (( attempts++ )) || true
    if [[ -z "$token" && $attempts -lt 2 ]]; then
      echo "  ✗ Token cannot be empty, try again"
    fi
  done

  if [[ -z "$token" ]]; then
    echo "  → Skipping Snyk setup"
    return 0
  fi

  # Merge token into ~/.claude/settings.json
  if [[ ! -f "$settings" ]]; then
    mkdir -p "$(dirname "$settings")"
    echo '{}' | jq --arg t "$token" '.env.SNYK_TOKEN = $t' > "$settings"
  else
    local tmp
    tmp=$(mktemp)
    jq --arg t "$token" '.env.SNYK_TOKEN = $t' "$settings" > "$tmp" && mv "$tmp" "$settings"
    rm -f "$tmp"
  fi
  echo "  ✓ SNYK_TOKEN saved to ~/.claude/settings.json"

  _patch_reviewer
  SNYK_CONFIGURED=true
}

main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  check_deps
  setup_claude
  setup_projects
  setup_snyk
}

main "$@"
