#!/usr/bin/env python3
"""heavy-guard.py — PreToolUse(Bash) hook: block heavy commands that skip scripts/heavy.sh

Installed into every agent dir by provision_agent_dir (scripts/lib/common.sh) and into the repo's
.claude/settings.json (v2 subagents inherit it). Several roles running jest + Playwright + next build
at once has frozen the 16 GB Mac repeatedly — heavy.sh runs them one at a time with a timeout.

Blocks (exit 2 + reason on stderr, which Claude reads): jest/vitest/playwright/cypress/tsc,
npm|pnpm|yarn|bun test/e2e/build/typecheck scripts, next/vite/nest/turbo/nx build, docker build,
compose --build, flutter test/build, gradlew, xcodebuild, go test, cargo build/test.
Allows: anything run through heavy.sh, --help/--version, and every other command.
Fails open: unparsable input or command → allow (a guard bug must never block all Bash).
"""
import json
import os
import re
import shlex
import sys

HEAVY_SH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "heavy.sh")

CONTROL = {";", "&&", "||", "|", "&", "|&", "(", ")", "\n"}
LAUNCHERS = {"rtk", "time", "nice", "env", "command", "exec", "caffeinate"}
TEST_BINS = {"jest", "vitest", "playwright", "cypress", "tsc", "vue-tsc"}
BUILD_TOOLS = {"next", "vite", "nest", "turbo", "nx", "webpack", "expo"}
PKG_MANAGERS = {"npm", "pnpm", "yarn", "bun"}
EXEC_RUNNERS = {"npx", "pnpx", "bunx"}
SCRIPT_RE = re.compile(r"^(test|t|e2e|build|typecheck|type-check|tsc)([:\-_.].*)?$|[:\-_](test|e2e)([:\-_.].*)?$")
TASK_RE = re.compile(r"^(build|test|e2e)([:\-_.].*)?$")


def segments(cmd):
    lex = shlex.shlex(cmd.replace("\n", " ; "), posix=True, punctuation_chars=";&|()")
    lex.whitespace_split = True
    seg = []
    for tok in lex:
        if tok in CONTROL or set(tok) <= set(";&|()"):
            if seg:
                yield seg
            seg = []
        else:
            seg.append(tok)
    if seg:
        yield seg


def strip_prefix(words):
    """drop VAR=x assignments and launchers (rtk/time/nice -n 5/env …) → the real command words"""
    i = 0
    while i < len(words):
        w = words[i]
        if re.match(r"^[A-Za-z_][A-Za-z0-9_]*=", w):
            i += 1
        elif os.path.basename(w) in LAUNCHERS:
            i += 1
            while i < len(words) and words[i].startswith("-"):  # nice -n 10 / env -i
                i += 2 if words[i] in ("-n",) else 1
        else:
            break
    return words[i:]


def is_heavy(words):
    words = strip_prefix(words)
    if not words:
        return False
    if any(w in ("--help", "--version") for w in words):
        return False
    b = os.path.basename(words[0])
    rest = words[1:]
    if b == "heavy.sh":
        return False
    if b in ("bash", "sh", "zsh") and "-c" in rest:  # look inside bash -c '...'
        i = rest.index("-c")
        return i + 1 < len(rest) and any(is_heavy(s) for s in segments(rest[i + 1]))
    if b in ("lockf", "flock"):  # old per-project locks (lockf -k /tmp/x.lock npx jest) → heavy.sh now
        i = 0
        while i < len(rest) and rest[i].startswith("-"):
            i += 2 if rest[i] in ("-t", "-w") else 1
        return is_heavy(rest[i + 1:])
    if b in EXEC_RUNNERS or (b in PKG_MANAGERS and rest[:1] and rest[0] in ("exec", "dlx")):
        rest = [w for w in (rest[1:] if b in PKG_MANAGERS else rest) if not w.startswith("-")]
        return bool(rest) and is_heavy(rest)
    if b in TEST_BINS:
        return True
    if b in BUILD_TOOLS:
        return any(TASK_RE.match(w) for w in rest)
    if b in PKG_MANAGERS:
        args = [w for w in rest if not w.startswith("-")]
        if args[:1] == ["run"] or args[:1] == ["run-script"]:
            args = args[1:]
        # pnpm --filter api test → "api" is the filter value; any arg that names a test/build script counts
        return any(SCRIPT_RE.search(w) for w in args[:3])
    if b == "docker":
        return "build" in rest or "--build" in rest
    if b == "docker-compose":
        return "build" in rest or "--build" in rest
    if b == "flutter":
        return rest[:1] in (["test"], ["build"])
    if b in ("gradlew", "xcodebuild"):
        return True
    if b == "go":
        return rest[:1] in (["test"], ["build"])
    if b == "cargo":
        return rest[:1] in (["test"], ["build"])
    return False


def main():
    try:
        data = json.load(sys.stdin)
        if data.get("tool_name") != "Bash":
            return 0
        cmd = data.get("tool_input", {}).get("command", "")
        hits = [" ".join(s) for s in segments(cmd) if is_heavy(s)]
    except Exception:
        return 0
    if not hits:
        return 0
    print(
        f"BLOCKED: งานหนัก ({hits[0]}) ต้องรันผ่าน heavy.sh — รันทีละงานทั้งเครื่อง + timeout กันเครื่องค้าง\n"
        f"  {HEAVY_SH} <command>                      # e.g. {HEAVY_SH} npx jest src/x --maxWorkers=2\n"
        f"  {HEAVY_SH} bash -c 'cd <dir> && <cmd>'     # มี cd / && / pipe\n"
        f"  {HEAVY_SH} --timeout 40 <command>          # เกิน 20 นาที\n"
        f"  {HEAVY_SH} status                          # ใครถือคิวอยู่\n"
        "jest --maxWorkers=2 · Playwright --workers=1 · e2e เฉพาะ suite ที่เกี่ยวข้อง",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    sys.exit(main())
