#!/usr/bin/env python3
"""
Local telemetry sidecar for the OHA Dota 2 bots.

Listens on 127.0.0.1 and appends everything the game sends to a per-match
JSONL file under tools/telemetry/data/. Nothing leaves this machine.

Endpoints (all POST unless noted, all return 200 even on bad input so the
game-side code never sees an error):

    GET  /health   liveness probe
    POST /start    once, when the match initialises
    POST /tick     periodically during the match
    POST /end      once, at post-game

Every payload is expected to carry a "session_id" string. Records are grouped
into one file per session, so a missed /start does not lose the ticks.

Usage:
    python tools/telemetry/server.py
    python tools/telemetry/server.py --port 8642 --data-dir some/other/dir
"""

import argparse
import json
import sys
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DEFAULT_PORT = 8642
DEFAULT_DATA_DIR = Path(__file__).resolve().parent / "data"
MAX_BODY_BYTES = 4 * 1024 * 1024

# session_id -> log path. Guarded by _lock. Handles are not held open: a match
# that never sends /end (alt-F4, crash) would otherwise leak one for the life of
# the process, and one append every 30s does not need a cached handle.
_paths = {}
_lock = threading.Lock()
_data_dir = DEFAULT_DATA_DIR


def _utc_now():
    return datetime.now(timezone.utc)


def _safe_component(value, fallback):
    """Reduce an untrusted string to something safe to put in a filename."""
    if not isinstance(value, str):
        return fallback
    cleaned = "".join(c for c in value if c.isalnum() or c in "-_")
    return cleaned[:48] or fallback


def _path_for(session_id):
    """Return the log path for this session, naming it on first use."""
    with _lock:
        path = _paths.get(session_id)
        if path is None:
            stamp = _utc_now().strftime("%Y%m%d-%H%M%S")
            path = _data_dir / f"{stamp}_{_safe_component(session_id, 'nosession')}.jsonl"
            _data_dir.mkdir(parents=True, exist_ok=True)
            _paths[session_id] = path
            print(f"[telemetry] new session -> {path.name}", flush=True)
        return path


def _write(kind, payload):
    session_id = payload.get("session_id")
    if not isinstance(session_id, str) or not session_id:
        session_id = "nosession"

    record = {
        "type": kind,
        "recv_at": _utc_now().isoformat(),
        "payload": payload,
    }
    line = json.dumps(record, separators=(",", ":"), default=str) + "\n"
    with _path_for(session_id).open("a", encoding="utf-8") as handle:
        handle.write(line)

    if kind == "tick":
        t = payload.get("dota_time")
        players = payload.get("players") or []
        print(f"[telemetry] tick t={t} players={len(players)}", flush=True)
    else:
        print(f"[telemetry] {kind} session={session_id}", flush=True)

    if kind == "end":
        with _lock:
            _paths.pop(session_id, None)


class Handler(BaseHTTPRequestHandler):
    server_version = "OHATelemetry/1.0"

    def _reply(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        # Silence the default per-request access log; we print our own summaries.
        pass

    def do_GET(self):
        if self.path.rstrip("/") in ("/health", ""):
            self._reply({"ok": True, "service": "oha-telemetry", "time": _utc_now().isoformat()})
        else:
            self._reply({"ok": False, "error": "not found"}, status=404)

    def do_POST(self):
        route = self.path.rstrip("/").lstrip("/").lower()

        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY_BYTES:
            self._reply({"ok": False, "error": "bad content-length"})
            return

        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8", errors="replace"))
        except json.JSONDecodeError as exc:
            # Keep the bad body so it can be inspected; never fail the caller.
            print(f"[telemetry] undecodable body on /{route}: {exc}", flush=True)
            _write("malformed", {"session_id": "malformed", "route": route,
                                 "raw": raw.decode("utf-8", errors="replace")[:8000]})
            self._reply({"ok": True, "note": "stored as malformed"})
            return

        if not isinstance(payload, dict):
            payload = {"value": payload}

        if route in ("start", "tick", "end"):
            try:
                _write(route, payload)
            except OSError as exc:
                print(f"[telemetry] write failed: {exc}", file=sys.stderr, flush=True)
                self._reply({"ok": False, "error": "write failed"})
                return
            # The bot code tolerates extra keys; these mirror the fields the
            # upstream chat server returns so this can stand in for it.
            self._reply({"ok": True, "updates_behind": 0})
        else:
            self._reply({"ok": False, "error": "unknown route"}, status=404)


def main():
    global _data_dir

    parser = argparse.ArgumentParser(description="Local telemetry sidecar for OHA bots")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--data-dir", type=Path, default=DEFAULT_DATA_DIR)
    args = parser.parse_args()

    _data_dir = args.data_dir
    _data_dir.mkdir(parents=True, exist_ok=True)

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"[telemetry] listening on http://{args.host}:{args.port}", flush=True)
    print(f"[telemetry] writing to {_data_dir}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[telemetry] shutting down", flush=True)
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
