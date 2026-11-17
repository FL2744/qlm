#!/usr/bin/env python3
"""Serve one HTML file on loopback for browser testing of online embeds."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import secrets
import sys
from urllib.parse import quote

source = Path(sys.argv[1]).expanduser().resolve(strict=True)
route = '/' + secrets.token_urlsafe(18) + '/' + quote(source.name)

class Preview(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path.split('?', 1)[0] != route:
            self.send_error(404)
            return
        try:
            data = source.read_bytes()
        except OSError:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Referrer-Policy', 'strict-origin-when-cross-origin')
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)
    def log_message(self, *args):
        pass

server = ThreadingHTTPServer(('127.0.0.1', 0), Preview)
print(f'http://127.0.0.1:{server.server_port}{route}', flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
finally:
    server.server_close()
