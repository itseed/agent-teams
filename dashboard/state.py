"""state.py — build live dashboard state for agent-teams v1 (tmux session dev-team).

Pure parse/derive functions + a tmux adapter that tests replace with a fake.
Spec: docs/superpowers/specs/2026-10-13-office-dashboard-live-design.md
"""
import os
import re

ROLES = ["frontend", "backend", "mobile", "devops", "designer", "architect", "qa", "reviewer"]
EVIDENCE_MAX = 600

_STATUS_KEYS = ("status", "task", "blocker")


def _sections(text):
    """Split markdown into {heading: [lines]} for '## ' headings; preamble under ''."""
    out, cur = {"": []}, ""
    for line in text.splitlines():
        if line.startswith("## "):
            cur = line[3:].strip()
            out[cur] = []
        else:
            out[cur].append(line)
    return out


def _first_line(lines):
    for line in lines:
        if line.strip():
            return line.strip()
    return None


def parse_team_state(text):
    """Parse .team-state.md → updated/project/stage/recent/rows (rows keyed by role)."""
    secs = _sections(text)

    updated = None
    m = re.search(r"^_Updated: (.*)_$", text, re.M)
    if m:
        updated = m.group(1).strip()

    project = _first_line(secs.get("Active Project", []))
    if project and project.startswith("["):
        project = None

    recent = []
    for line in secs.get("Recently Completed", []):
        line = line.strip()
        if not line or line == "(ยังไม่มี)":
            continue
        recent.append(re.sub(r"^[-*]\s+", "", line))

    rows = {}
    for line in secs.get("Agents in Panes", []):
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 4 or cells[0] not in ROLES:
            continue
        task = "|".join(cells[3:]).strip()
        task = re.sub(r"\s*\|\s*", " | ", task)
        rows[cells[0]] = {"pane": cells[1], "status": cells[2], "task": None if task in ("", "—", "-") else task}

    return {
        "updated": updated,
        "project": project,
        "stage": _first_line(secs.get("Pipeline Stage", [])),
        "recent": recent,
        "rows": rows,
    }


def parse_status_file(text):
    """Parse /tmp/agent-status/<role>.md → status/task/blocker/evidence (None when missing)."""
    out = {"status": None, "task": None, "blocker": None, "evidence": None}
    lines = text.splitlines()
    for line in lines:
        if not line.strip() or line.startswith("## "):
            break
        key, sep, value = line.partition(":")
        key = key.strip().lower()
        if sep and key in _STATUS_KEYS and value.strip():
            out[key] = value.strip()

    for i, line in enumerate(lines):
        if line.strip().lower() == "## verification evidence":
            ev = "\n".join(lines[i + 1:]).strip()
            if ev:
                out["evidence"] = ev if len(ev) <= EVIDENCE_MAX else ev[:EVIDENCE_MAX] + "…"
            break
    return out


SHELLS = {"zsh", "bash", "sh", "fish", "dash"}


def _pane_alive(pane):
    return pane is not None and pane.get("cmd", "").lstrip("-") not in SHELLS


def derive_status(row, pane, fs):
    """Spec §4. row = team-state row (None = not spawned), pane = tmux pane info (None = gone),
    fs = parsed status file already filtered for staleness (None = no usable file)."""
    if row is None:
        return "absent"
    if not _pane_alive(pane):
        return "offline"
    fs_status = (fs or {}).get("status")
    if fs_status == "blocked":
        return "blocked"
    if fs_status == "working":
        return "working"
    if fs_status == "done":
        return "done" if row.get("status") == "working" else "idle"
    return "working" if row.get("status") == "working" else "idle"


class TmuxAdapter:
    """Real tmux/git access. Every failure → None (dashboard must never crash on tmux)."""

    PANE_FMT = "#{pane_id}\t#{pane_current_command}\t#{pane_current_path}\t#{@workdir}\t#{@role}"

    def __init__(self, repo_dir, timeout=2):
        self.repo_dir = repo_dir
        self.timeout = timeout

    def _run(self, args):
        import subprocess
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=self.timeout)
        except (OSError, subprocess.SubprocessError):
            return None
        return r.stdout if r.returncode == 0 else None

    def session(self, name):
        created = self._run(["tmux", "display-message", "-p", "-t", f"={name}", "#{session_created}"])
        listing = self._run(["tmux", "list-panes", "-s", "-t", f"={name}", "-F", self.PANE_FMT])
        if not created or listing is None:
            return None
        panes = {}
        for line in listing.splitlines():
            parts = line.split("\t")
            if len(parts) != 5:
                continue
            pid, cmd, path, workdir, role = parts
            panes[pid] = {"cmd": cmd, "path": path, "workdir": workdir, "role": role}
        try:
            created_ts = int(created.strip())
        except ValueError:
            return None
        return {"created": created_ts, "panes": panes}

    def branch(self, workdir, path):
        script = os.path.join(self.repo_dir, "scripts", "pane-branch.sh")
        out = self._run(["bash", script, workdir or "", path or ""])
        return (out.strip() or None) if out else None


def _agent(role, **kw):
    a = {"role": role, "pane": None, "spawned": False, "alive": False, "status": "absent", "task": None,
         "blocker": None, "evidence": None, "since": None, "branch": None, "error": None}
    a.update(kw)
    return a


def _read_status(status_dir, role, created):
    """→ (parsed status file | None, mtime | None). Stale (mtime < created) → (None, None)."""
    path = os.path.join(status_dir, f"{role}.md")
    if not os.path.exists(path):
        return None, None
    mtime = int(os.path.getmtime(path))
    if created is not None and mtime < created:
        return None, None
    with open(path, encoding="utf-8", errors="replace") as f:
        return parse_status_file(f.read()), mtime


def build_state(state_file, status_dir, session, tmux):
    """Spec §3 JSON for GET /api/state."""
    import time

    ts = None
    if os.path.isfile(state_file):
        with open(state_file, encoding="utf-8", errors="replace") as f:
            ts = parse_team_state(f.read())
    sess = tmux.session(session) if ts is not None else None
    panes = sess["panes"] if sess else {}
    created = sess["created"] if sess else None

    lead_id = next((pid for pid, p in panes.items() if p.get("role") == "Lead"), None)
    lead_alive = _pane_alive(panes.get(lead_id)) if lead_id else False
    agents = [_agent("lead", pane=lead_id or f"{session}:0.0", spawned=True, alive=lead_alive,
                     status="working" if lead_alive else "offline")]

    rows = ts["rows"] if ts else {}
    for role in ROLES:
        row = rows.get(role)
        if row is None:
            agents.append(_agent(role))
            continue
        pane = panes.get(row["pane"])
        a = _agent(role, pane=row["pane"], spawned=True, alive=_pane_alive(pane))
        fs = mtime = None
        try:
            fs, mtime = _read_status(status_dir, role, created)
        except OSError as e:
            a["error"] = f"status file: {e.strerror or e}"
        a["status"] = derive_status(row, pane, fs)
        a["task"] = (fs or {}).get("task") or row.get("task")
        if a["status"] in ("blocked", "working", "done"):
            a["blocker"] = (fs or {}).get("blocker")
            a["evidence"] = (fs or {}).get("evidence")
            a["since"] = mtime
        if pane is not None:
            a["branch"] = tmux.branch(pane.get("workdir"), pane.get("path"))
        agents.append(a)

    return {
        "session": {"name": session, "running": sess is not None, "created": created},
        "project": ts["project"] if ts else None,
        "stage": ts["stage"] if ts else None,
        "updated": ts["updated"] if ts else None,
        "recent": ts["recent"] if ts else [],
        "agents": agents,
        "serverTime": int(time.time()),
    }
