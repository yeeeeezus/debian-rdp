#!/usr/bin/env python3
"""boot-placeholder.py — serves the Debian boot page on :3000 while the
real desktop stack is being (re)built.

Why: during a full rebuild nothing listens on :3000, so the web preview
would show a dead gateway error. This tiny server keeps the preview alive
and serves the SAME boot page the real stack uses, plus a status.json
that bootstrap.sh updates at every stage — the open browser tab shows
live boot notes ("Downloading packages", "Unpacking root filesystem"…)
and switches to the real desktop automatically when the stack is ready
(placeholder dies, websockify takes over :3000, page sees status.json 404
and connects).

stdlib only. Run detached:  setsid nohup boot-placeholder.py WEBROOT &
"""
import http.server
import os
import socketserver
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else '/home/z/debian/bootpage'
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 3000

os.chdir(ROOT)


class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass  # quiet - status.json is polled every 2s

    def end_headers(self):
        # status.json must never be cached
        if self.path.endswith('.json'):
            self.send_header('Cache-Control', 'no-store')
        super().end_headers()


socketserver.TCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(('0.0.0.0', PORT), Handler) as srv:
    srv.serve_forever()
