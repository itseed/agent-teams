"""Tests for dashboard/state.py and dashboard/server.py — run: python3 -m unittest dashboard/test_state.py -v"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import state  # noqa: E402

TEAM_STATE = """# Team State
_Updated: 2026-10-13 10:42_
_Mode: v1 — interactive panes_
_RTK: yes_

## Active Project
pms

## Agents in Panes
| Role     | Pane ID            | Status | Current Task |
|----------|--------------------|--------|--------------|
| frontend | %1 | idle | — |
| backend | %3 | working | implement /auth/login (docs/plan/login.md) |
| qa | %7 | idle | — |

## Pipeline Stage
qa — login

## Recently Completed
- backend: /auth/register ✓
- frontend: login page ✓

## Notes
Session เริ่มใหม่
"""


class TeamStateParseTest(unittest.TestCase):
    def test_full_file(self):
        ts = state.parse_team_state(TEAM_STATE)
        self.assertEqual(ts["updated"], "2026-10-13 10:42")
        self.assertEqual(ts["project"], "pms")
        self.assertEqual(ts["stage"], "qa — login")
        self.assertEqual(ts["recent"], ["backend: /auth/register ✓", "frontend: login page ✓"])
        self.assertEqual(set(ts["rows"]), {"frontend", "backend", "qa"})
        self.assertEqual(ts["rows"]["backend"],
                         {"pane": "%3", "status": "working", "task": "implement /auth/login (docs/plan/login.md)"})
        self.assertEqual(ts["rows"]["frontend"], {"pane": "%1", "status": "idle", "task": None})

    def test_placeholders(self):
        text = TEAM_STATE.replace("pms", "[Lead ต้อง set หลังอ่าน projects.json]").replace(
            "- backend: /auth/register ✓\n- frontend: login page ✓", "(ยังไม่มี)")
        ts = state.parse_team_state(text)
        self.assertIsNone(ts["project"])
        self.assertEqual(ts["recent"], [])

    def test_malformed_and_unknown_rows(self):
        text = TEAM_STATE.replace("| qa | %7 | idle | — |", "| qa | %7 |\n| ghost | %9 | idle | — |")
        ts = state.parse_team_state(text)
        self.assertEqual(set(ts["rows"]), {"frontend", "backend"})

    def test_pipe_in_task_keeps_rest(self):
        text = TEAM_STATE.replace("implement /auth/login (docs/plan/login.md)", "a | b")
        ts = state.parse_team_state(text)
        self.assertEqual(ts["rows"]["backend"]["status"], "working")
        self.assertEqual(ts["rows"]["backend"]["task"], "a | b")

    def test_empty(self):
        ts = state.parse_team_state("")
        self.assertEqual(ts, {"updated": None, "project": None, "stage": None, "recent": [], "rows": {}})


class StatusFileParseTest(unittest.TestCase):
    def test_working(self):
        fs = state.parse_status_file("status: working\ntask: implement login\nupdated: 10:01:02\n")
        self.assertEqual(fs, {"status": "working", "task": "implement login", "blocker": None, "evidence": None})

    def test_done_with_evidence_truncated(self):
        body = "x" * 700
        fs = state.parse_status_file(f"status: done\ntask: t\nupdated: 10:00:00\n\n## Verification evidence\n{body}\n")
        self.assertEqual(fs["status"], "done")
        self.assertEqual(len(fs["evidence"]), state.EVIDENCE_MAX + 1)
        self.assertTrue(fs["evidence"].endswith("…"))

    def test_done_short_evidence(self):
        fs = state.parse_status_file("status: done\ntask: t\n\n## Verification evidence\n  tests: 12 passed\n")
        self.assertEqual(fs["evidence"], "tests: 12 passed")

    def test_blocked(self):
        fs = state.parse_status_file("status: blocked\ntask: t\nblocker: need API spec\nupdated: 10:00:00\n")
        self.assertEqual(fs["status"], "blocked")
        self.assertEqual(fs["blocker"], "need API spec")

    def test_garbage(self):
        fs = state.parse_status_file("\x00\x01 random\nnot a header")
        self.assertEqual(fs, {"status": None, "task": None, "blocker": None, "evidence": None})


if __name__ == "__main__":
    unittest.main()
