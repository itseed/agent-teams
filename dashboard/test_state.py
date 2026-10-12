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


ALIVE = {"cmd": "claude", "path": "/tmp/agent-x", "workdir": "", "role": "X"}
DEAD = {"cmd": "-zsh", "path": "/tmp/agent-x", "workdir": "", "role": "X"}
ROW_IDLE = {"pane": "%1", "status": "idle", "task": None}
ROW_WORKING = {"pane": "%1", "status": "working", "task": "ts task"}


def fs(status, **kw):
    out = {"status": status, "task": None, "blocker": None, "evidence": None}
    out.update(kw)
    return out


class DeriveStatusTest(unittest.TestCase):
    def test_rule1_absent(self):
        self.assertEqual(state.derive_status(None, ALIVE, fs("working")), "absent")

    def test_rule2_pane_missing(self):
        self.assertEqual(state.derive_status(ROW_WORKING, None, fs("working")), "offline")

    def test_rule2_shell(self):
        self.assertEqual(state.derive_status(ROW_WORKING, DEAD, fs("working")), "offline")
        self.assertEqual(state.derive_status(ROW_WORKING, dict(ALIVE, cmd="bash"), None), "offline")

    def test_rule4_blocked(self):
        self.assertEqual(state.derive_status(ROW_IDLE, ALIVE, fs("blocked")), "blocked")

    def test_rule5_working_from_file(self):
        self.assertEqual(state.derive_status(ROW_IDLE, ALIVE, fs("working")), "working")

    def test_rule6_done_waiting_for_lead(self):
        self.assertEqual(state.derive_status(ROW_WORKING, ALIVE, fs("done")), "done")

    def test_rule6_done_accepted(self):
        self.assertEqual(state.derive_status(ROW_IDLE, ALIVE, fs("done")), "idle")

    def test_rule7_team_state(self):
        self.assertEqual(state.derive_status(ROW_WORKING, ALIVE, None), "working")
        self.assertEqual(state.derive_status(ROW_IDLE, ALIVE, None), "idle")
        self.assertEqual(state.derive_status(dict(ROW_IDLE, status="weird"), ALIVE, fs(None)), "idle")


class FakeTmux:
    def __init__(self, session=None, branches=None):
        self._session = session
        self._branches = branches or {}

    def session(self, name):
        return self._session

    def branch(self, workdir, path):
        return self._branches.get(workdir or path)


class BuildStateTest(unittest.TestCase):
    CREATED = 1_000_000

    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.state_file = os.path.join(self.tmp.name, ".team-state.md")
        self.status_dir = os.path.join(self.tmp.name, "agent-status")
        os.makedirs(self.status_dir)
        with open(self.state_file, "w") as f:
            f.write(TEAM_STATE)

    def tearDown(self):
        self.tmp.cleanup()

    def write_status(self, role, text, mtime):
        p = os.path.join(self.status_dir, f"{role}.md")
        with open(p, "w") as f:
            f.write(text)
        os.utime(p, (mtime, mtime))

    def session(self, **overrides):
        panes = {
            "%0": dict(ALIVE, role="Lead", path="/repo/agent-teams"),
            "%1": dict(ALIVE, role="Frontend", workdir="/repo/web"),
            "%3": dict(ALIVE, role="Backend", workdir="/repo/api"),
            "%7": dict(ALIVE, role="QA"),
        }
        panes.update(overrides)
        return {"created": self.CREATED, "panes": panes}

    def build(self, tmux):
        return state.build_state(self.state_file, self.status_dir, "dev-team", tmux)

    def agent(self, st, role):
        return next(a for a in st["agents"] if a["role"] == role)

    def test_shape_and_order(self):
        st = self.build(FakeTmux(self.session()))
        self.assertEqual([a["role"] for a in st["agents"]], ["lead"] + state.ROLES)
        self.assertEqual(st["session"], {"name": "dev-team", "running": True, "created": self.CREATED})
        self.assertEqual(st["project"], "pms")
        self.assertEqual(st["stage"], "qa — login")
        self.assertEqual(st["updated"], "2026-10-13 10:42")
        self.assertEqual(len(st["recent"]), 2)
        self.assertIsInstance(st["serverTime"], int)

    def test_mixed_team(self):
        self.write_status("frontend", "status: blocked\ntask: login page\nblocker: no API\n", self.CREATED + 10)
        self.write_status("backend", "status: done\ntask: auth\n\n## Verification evidence\nok\n", self.CREATED + 10)
        st = self.build(FakeTmux(self.session(), {"/repo/api": "feature/login"}))
        fe, be, qa, mobile, lead = (self.agent(st, r) for r in ("frontend", "backend", "qa", "mobile", "lead"))
        self.assertEqual((fe["status"], fe["blocker"], fe["task"]), ("blocked", "no API", "login page"))
        self.assertEqual((be["status"], be["evidence"], be["branch"], be["since"]),
                         ("done", "ok", "feature/login", self.CREATED + 10))
        self.assertEqual((qa["status"], qa["task"], qa["since"]), ("idle", None, None))
        self.assertEqual((mobile["status"], mobile["spawned"], mobile["pane"]), ("absent", False, None))
        self.assertEqual((lead["status"], lead["pane"], lead["alive"]), ("working", "%0", True))

    def test_stale_status_file_ignored(self):
        self.write_status("qa", "status: blocked\ntask: old\nblocker: old\n", self.CREATED - 5)
        st = self.build(FakeTmux(self.session()))
        qa = self.agent(st, "qa")
        self.assertEqual((qa["status"], qa["blocker"], qa["since"]), ("idle", None, None))

    def test_task_falls_back_to_team_state(self):
        st = self.build(FakeTmux(self.session()))
        be = self.agent(st, "backend")
        self.assertEqual((be["status"], be["task"]), ("working", "implement /auth/login (docs/plan/login.md)"))

    def test_dead_pane_offline(self):
        st = self.build(FakeTmux(self.session(**{"%3": DEAD})))
        self.assertEqual(self.agent(st, "backend")["status"], "offline")
        self.assertFalse(self.agent(st, "backend")["alive"])

    def test_session_not_running(self):
        st = self.build(FakeTmux(None))
        self.assertFalse(st["session"]["running"])
        self.assertEqual(self.agent(st, "backend")["status"], "offline")
        self.assertEqual(self.agent(st, "mobile")["status"], "absent")
        self.assertEqual(self.agent(st, "lead")["status"], "offline")

    def test_missing_state_file(self):
        os.remove(self.state_file)
        st = self.build(FakeTmux(self.session()))
        self.assertFalse(st["session"]["running"])
        self.assertTrue(all(a["status"] == "absent" for a in st["agents"] if a["role"] != "lead"))

    def test_missing_status_dir(self):
        import shutil
        shutil.rmtree(self.status_dir)
        st = self.build(FakeTmux(self.session()))
        self.assertEqual(self.agent(st, "backend")["status"], "working")

    def test_unreadable_status_file_sets_error_only_for_role(self):
        os.makedirs(os.path.join(self.status_dir, "qa.md"))  # a directory: open() fails
        st = self.build(FakeTmux(self.session()))
        self.assertIsNotNone(self.agent(st, "qa")["error"])
        self.assertEqual(self.agent(st, "backend")["status"], "working")


class ServerTest(unittest.TestCase):
    def setUp(self):
        import tempfile
        import threading
        import server
        self.tmp = tempfile.TemporaryDirectory()
        state_file = os.path.join(self.tmp.name, ".team-state.md")
        with open(state_file, "w") as f:
            f.write(TEAM_STATE)
        self.httpd = server.make_server(0, state_file, os.path.join(self.tmp.name, "none"), "dev-team",
                                        FakeTmux({"created": 1, "panes": {}}))
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        self.tmp.cleanup()

    def request(self, path, method="GET"):
        import http.client
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        c.request(method, path)
        r = c.getresponse()
        body = r.read()
        c.close()
        return r, body

    def test_api_state(self):
        import json
        r, body = self.request("/api/state")
        self.assertEqual(r.status, 200)
        self.assertEqual(r.getheader("Cache-Control"), "no-store")
        self.assertIn("application/json", r.getheader("Content-Type"))
        data = json.loads(body)
        self.assertEqual(len(data["agents"]), 9)
        self.assertTrue(data["session"]["running"])

    def test_index(self):
        for path in ("/", "/index.html"):
            r, body = self.request(path)
            self.assertEqual(r.status, 200)
            self.assertIn("text/html", r.getheader("Content-Type"))
            self.assertIn(b"<html", body.lower())

    def test_other_paths_404(self):
        for path in ("/state.py", "/../state.py", "/etc/passwd", "/office-floor.html/../state.py"):
            r, _ = self.request(path)
            self.assertEqual(r.status, 404, path)

    def test_post_rejected(self):
        r, _ = self.request("/api/state", "POST")
        self.assertIn(r.status, (405, 501))

    def test_binds_localhost_only(self):
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")


if __name__ == "__main__":
    unittest.main()
