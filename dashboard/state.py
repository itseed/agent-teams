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
