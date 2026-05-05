# install.sh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** สร้าง `install.sh` ที่ช่วย user ที่ clone repo ใหม่ setup ทุกอย่างได้ด้วยคำสั่งเดียว

**Architecture:** Single bash script แบบ modular functions — `check_os()` ตรวจ platform, `check_deps()` ตรวจ/ติดตั้ง tmux+jq, `setup_claude()` ตรวจ/ติดตั้ง Claude CLI, `setup_projects()` copy projects.json.example, `setup_snyk()` รับ token optional, `verify()` แสดง summary สุดท้าย ทุก function track status ผ่าน global booleans แล้ว main() เรียงลำดับ

**Tech Stack:** Bash, jq (dep), Python 3 (มีใน macOS/Ubuntu by default — ใช้ patch reviewer.md multiline)

---

## File Structure

```
install.sh          ← สร้างใหม่ (script หลัก)
```

Runtime modifications (ไม่ใช่ source files):
- `projects.json` — copy จาก example
- `~/.claude/settings.json` — merge SNYK_TOKEN
- `.claude/agents/reviewer.md` — inject Snyk workflow (ถ้ายังไม่มี)

---

## Task 1: Script skeleton + `check_os()`

**Files:**
- Create: `install.sh`

- [ ] **Step 1: สร้างไฟล์ skeleton พร้อม global state variables**

```bash
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
```

- [ ] **Step 2: เพิ่ม `check_os()`**

```bash
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
```

- [ ] **Step 3: เพิ่ม stub `main()` เพื่อทดสอบ**

```bash
main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  echo "  PKG_MANAGER=${PKG_MANAGER:-none}"
}

main "$@"
```

- [ ] **Step 4: chmod +x และทดสอบ**

```bash
chmod +x install.sh
./install.sh
```

Expected output (macOS with brew):
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   agent-teams installer
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PKG_MANAGER=brew
```

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat(install): add script skeleton and check_os()"
```

---

## Task 2: `check_deps()` — tmux, jq

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: เพิ่ม `check_deps()` ก่อน `main()`**

```bash
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
    echo "  ✓ jq $(jq --version)"
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
```

- [ ] **Step 2: เพิ่ม `check_deps` ใน `main()`**

แก้ main() จาก stub เป็น:
```bash
main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  check_deps
}

main "$@"
```

- [ ] **Step 3: ทดสอบ — deps ครบ**

```bash
./install.sh
```

Expected (ถ้า tmux+jq ติดตั้งแล้ว):
```
Checking dependencies...
  ✓ tmux 3.3a
  ✓ jq jq-1.7.1
```

- [ ] **Step 4: ทดสอบ — simulate missing dep**

```bash
# ทดสอบโดย mock PATH ชั่วคราว
PATH_BAK=$PATH
export PATH="/usr/bin"   # hide brew binaries
./install.sh
export PATH=$PATH_BAK
```

Expected: เห็น `✗ Missing: tmux jq` และถาม install

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat(install): add check_deps() for tmux and jq"
```

---

## Task 3: `setup_claude()`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: เพิ่ม `setup_claude()` ก่อน `main()`**

```bash
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
```

- [ ] **Step 2: เพิ่ม `setup_claude` ใน `main()`**

```bash
main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  check_deps
  setup_claude
}
```

- [ ] **Step 3: ทดสอบ — claude มีอยู่แล้ว**

```bash
./install.sh
```

Expected:
```
Checking Claude CLI...
  ✓ claude found
```

- [ ] **Step 4: Commit**

```bash
git add install.sh
git commit -m "feat(install): add setup_claude()"
```

---

## Task 4: `setup_projects()`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: เพิ่ม `setup_projects()` ก่อน `main()`**

```bash
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
```

- [ ] **Step 2: เพิ่ม `setup_projects` ใน `main()`**

```bash
main() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   agent-teams installer"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  check_os
  check_deps
  setup_claude
  setup_projects
}
```

- [ ] **Step 3: ทดสอบ — projects.json ไม่มี**

```bash
mv projects.json projects.json.bak 2>/dev/null || true
./install.sh
ls projects.json   # ต้องมีไฟล์นี้
mv projects.json.bak projects.json 2>/dev/null || true
```

Expected:
```
Setting up projects.json...
  ✓ Copied projects.json.example → projects.json
  → Edit it to add your project paths: ...
```

- [ ] **Step 4: ทดสอบ — projects.json มีอยู่แล้ว**

```bash
./install.sh
```

Expected:
```
Setting up projects.json...
  ✓ projects.json already exists, skipping
```

- [ ] **Step 5: Commit**

```bash
git add install.sh
git commit -m "feat(install): add setup_projects() and chmod scripts"
```

---

## Task 5: `setup_snyk()` + `_patch_reviewer()`

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: เพิ่ม `_patch_reviewer()` helper ก่อน `main()`**

```bash
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
```

- [ ] **Step 2: เพิ่ม `setup_snyk()` ก่อน `main()`**

```bash
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
```

- [ ] **Step 3: เพิ่ม `setup_snyk` ใน `main()`**

```bash
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
```

- [ ] **Step 4: ทดสอบ Snyk skip**

```bash
./install.sh
# เมื่อถาม "Set up Snyk?" → พิมพ์ N
```

Expected: ข้ามไปเลย ไม่มี error

- [ ] **Step 5: ทดสอบ _patch_reviewer — already patched**

```bash
grep -q "snyk test" .claude/agents/reviewer.md && echo "PASS: snyk already in reviewer.md"
```

Expected: `PASS: snyk already in reviewer.md`

- [ ] **Step 6: ทดสอบ jq merge ไม่ทับ key เดิม**

```bash
# ตรวจว่า CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS ยังอยู่หลัง merge
jq '.env' ~/.claude/settings.json
```

Expected: ยังเห็น `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` และ `SNYK_TOKEN` ด้วยกัน

- [ ] **Step 7: Commit**

```bash
git add install.sh
git commit -m "feat(install): add setup_snyk() with token input and reviewer patch"
```

---

## Task 6: `verify()` + wire up `main()` final

**Files:**
- Modify: `install.sh`

- [ ] **Step 1: เพิ่ม `verify()` ก่อน `main()`**

```bash
verify() {
  local _s
  _s() {
    local ok=$1 label=$2 detail=${3:-}
    if $ok; then
      echo "  ✓ $label${detail:+  ($detail)}"
    else
      echo "  ✗ $label"
    fi
  }

  echo ""
  echo "────────────────────────────────"
  echo " Setup Summary"
  echo "────────────────────────────────"
  _s "$TMUX_OK"    "tmux"               "$(command -v tmux >/dev/null 2>&1 && tmux -V | awk '{print $2}' || true)"
  _s "$JQ_OK"      "jq"                 "$(command -v jq >/dev/null 2>&1 && jq --version || true)"
  _s "$CLAUDE_OK"  "claude CLI"
  _s "$PROJECTS_OK" "projects.json"
  _s "$SCRIPTS_OK"  "scripts executable"

  if $SNYK_CONFIGURED; then
    echo "  ✓ snyk token configured"
  else
    echo "  ○ snyk (skipped)"
  fi

  echo "────────────────────────────────"

  if $TMUX_OK && $JQ_OK && $CLAUDE_OK && $PROJECTS_OK; then
    echo ""
    echo "  Ready! Run: ./start-team.sh"
  else
    echo ""
    echo "  ⚠ Some items need attention — see above"
  fi
  echo ""
}
```

- [ ] **Step 2: อัปเดต `main()` final**

```bash
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
  verify
}

main "$@"
```

- [ ] **Step 3: ทดสอบ full run (skip Snyk)**

```bash
./install.sh
# ตอบ N ทุก prompt
```

Expected output สุดท้าย:
```
────────────────────────────────
 Setup Summary
────────────────────────────────
  ✓ tmux  (3.3a)
  ✓ jq  (jq-1.7.1)
  ✓ claude CLI
  ✓ projects.json
  ✓ scripts executable
  ○ snyk (skipped)
────────────────────────────────

  Ready! Run: ./start-team.sh
```

- [ ] **Step 4: ตรวจว่า exit code สะอาด**

```bash
./install.sh <<< $'N\nN\nN'   # non-interactive: ตอบ N ทุก prompt
echo "Exit: $?"
```

Expected: `Exit: 0`

- [ ] **Step 5: Final commit**

```bash
git add install.sh
git commit -m "feat(install): add verify() and wire up complete install flow"
```

---

## Self-Review Checklist

Spec coverage:
- ✓ check_os() — Task 1
- ✓ check_deps() tmux+jq + offer install — Task 2
- ✓ setup_claude() + ask before install — Task 3
- ✓ setup_projects() copy example + chmod — Task 4
- ✓ setup_snyk() optional + read -s + empty check — Task 5
- ✓ SNYK_TOKEN merge into settings.json — Task 5
- ✓ _patch_reviewer() inject workflow — Task 5
- ✓ verify() summary with ✓/✗/○ — Task 6
- ✓ macOS brew + Linux apt-get — Task 1, 2
- ✓ ไม่ใช้ set -e global — skeleton Task 1
