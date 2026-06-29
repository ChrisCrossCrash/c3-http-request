#!/usr/bin/env python3
"""Standalone benchmark server for the C3Http benchmark.

Serves the same two endpoints as the hosted benchmark API, but with no
framework and no dependencies — just the Python standard library. Run it on
any machine (localhost for a deterministic loopback run, or a remote box to
measure a real network link) and point the benchmark at its address.

Endpoints (mirroring the hosted Django/DRF API):

    GET /api/benchmark/ping/            -> {"ok": true}
    GET /api/benchmark/download/<n>/    -> n zero bytes, streamed,
                                           with a Content-Length header

Requests are served on threads (ThreadingHTTPServer), so the concurrency
benchmark's simultaneous requests are handled in parallel rather than queued.

Usage:

    python benchmark_server.py                 # listen on 127.0.0.1:8927
    python benchmark_server.py --host 0.0.0.0  # listen on all interfaces
    python benchmark_server.py --port 8080
    python benchmark_server.py --token SECRET   # require "Authorization: Token SECRET"
"""

import argparse
import json
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Largest download the server will produce, matching the hosted API's cap.
DOWNLOAD_MAX = 100 * 1024 * 1024
# Bytes per streamed slice. 64 KiB matches the benchmark's download_chunk_size
# and the hosted server's chunk, so the body is delivered the same way.
CHUNK = 65536

_PING_PATH = re.compile(r"^/api/benchmark/ping/?$")
_DOWNLOAD_PATH = re.compile(r"^/api/benchmark/download/(\d+)/?$")

# Set from --token; when non-empty, requests must carry a matching
# "Authorization: Token <value>" header, mirroring DRF TokenAuthentication.
_required_token = ""


class Handler(BaseHTTPRequestHandler):
    # HTTP/1.1 so connections can stream a known Content-Length cleanly.
    protocol_version = "HTTP/1.1"

    def do_GET(self) -> None:
        if not self._authorized():
            self._send_status(401)
            return
        if _PING_PATH.match(self.path):
            self._send_ping()
            return
        match = _DOWNLOAD_PATH.match(self.path)
        if match:
            self._send_download(int(match.group(1)))
            return
        self._send_status(404)

    def _authorized(self) -> bool:
        if not _required_token:
            return True
        return self.headers.get("Authorization", "") == "Token %s" % _required_token

    def _send_ping(self) -> None:
        body = json.dumps({"ok": True}).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_download(self, num_bytes: int) -> None:
        if num_bytes > DOWNLOAD_MAX:
            self._send_status(400)
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/octet-stream")
        self.send_header("Content-Length", str(num_bytes))
        self.end_headers()
        chunk = b"\x00" * CHUNK
        remaining = num_bytes
        while remaining >= CHUNK:
            self.wfile.write(chunk)
            remaining -= CHUNK
        if remaining:
            self.wfile.write(b"\x00" * remaining)

    def _send_status(self, code: int) -> None:
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    # Quiet by default: the benchmark fires thousands of requests, and the
    # default per-request stderr log would bury its output. Pass -v to restore.
    def log_message(self, *args: object) -> None:
        if self.server.verbose:  # type: ignore[attr-defined]
            super().log_message(*args)  # type: ignore[arg-type]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1", help="bind address (default: 127.0.0.1)")
    parser.add_argument("--port", type=int, default=8927, help="bind port (default: 8927)")
    parser.add_argument(
        "--token",
        default="",
        help='require "Authorization: Token <value>"; off by default',
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="log every request")
    args = parser.parse_args()

    global _required_token
    _required_token = args.token

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.verbose = args.verbose  # type: ignore[attr-defined]
    print("Benchmark server listening on http://%s:%d/" % (args.host, args.port))
    print("  ping:     GET /api/benchmark/ping/")
    print("  download: GET /api/benchmark/download/<bytes>/")
    if _required_token:
        print('  auth:     "Authorization: Token %s" required' % _required_token)
    print("Press Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.shutdown()


if __name__ == "__main__":
    main()
