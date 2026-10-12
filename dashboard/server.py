#!/usr/bin/env python3
"""server.py — local read-only HTTP server for the Office Floor dashboard (agent-teams v1).

  GET /, /index.html  → dashboard/office-floor.html
  GET /api/state      → JSON from state.build_state()

Usage: python3 dashboard/server.py [--port 4780] [--state-file P] [--status-dir D] [--session S]
Binds 127.0.0.1 only. Started/stopped by start_dashboard / stop_dashboard in scripts/lib/common.sh.
"""
import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import state  # noqa: E402

HTML_FILE = os.path.join(HERE, "office-floor.html")


def make_server(port, state_file, status_dir, session, tmux):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _send(self, code, ctype, body):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            path = self.path.split("?", 1)[0]
            if path in ("/", "/index.html"):
                with open(HTML_FILE, "rb") as f:
                    self._send(200, "text/html; charset=utf-8", f.read())
            elif path == "/api/state":
                try:
                    data = state.build_state(state_file, status_dir, session, tmux)
                    code = 200
                except Exception as e:  # never kill the server on a bad read
                    data, code = {"error": f"{type(e).__name__}: {e}"}, 500
                body = json.dumps(data, ensure_ascii=False).encode("utf-8")
                self._send(code, "application/json; charset=utf-8", body)
            else:
                self._send(404, "text/plain; charset=utf-8", b"not found")

    return ThreadingHTTPServer(("127.0.0.1", port), Handler)


def main():
    ap = argparse.ArgumentParser(description="Office Floor dashboard server (agent-teams v1)")
    ap.add_argument("--port", type=int, default=int(os.environ.get("DASHBOARD_PORT", "4780")))
    ap.add_argument("--state-file", default=os.path.join(REPO, ".team-state.md"))
    ap.add_argument("--status-dir", default="/tmp/agent-status")
    ap.add_argument("--session", default="dev-team")
    args = ap.parse_args()

    try:
        httpd = make_server(args.port, args.state_file, args.status_dir, args.session, state.TmuxAdapter(REPO))
    except OSError as e:
        print(f"dashboard: cannot bind 127.0.0.1:{args.port} — {e.strerror or e}", file=sys.stderr)
        sys.exit(1)
    print(f"dashboard: http://127.0.0.1:{args.port}/ (session {args.session})", flush=True)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
