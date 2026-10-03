"""Bounded loopback HTTP adapter. Deliberately not an Internet deployment server."""
from __future__ import annotations

import argparse
import collections
import signal
import sqlite3
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

from .model import APIError, MAX_BODY, Response, json_bytes, parse_json
from .store import Store


class LocalServer(HTTPServer):
    # Allow an intentional restart while old connections are in TIME_WAIT.
    # This does not enable SO_REUSEPORT or permit two active listeners.
    allow_reuse_address = True
    request_queue_size = 16

    def __init__(self, store: Store, port: int = 47831):
        # Bind only an explicit loopback address; no --host or proxy trust mode.
        self.store = store
        self.auth_attempts = collections.deque(maxlen=20)
        super().__init__(("127.0.0.1", port), Handler)

    def get_request(self):
        sock, address = super().get_request()
        sock.settimeout(3)
        return sock, address

    def check_auth_rate(self):
        now = time.monotonic()
        while self.auth_attempts and self.auth_attempts[0] <= now - 60:
            self.auth_attempts.popleft()
        if len(self.auth_attempts) >= 20:
            raise APIError(429, "rate_limited", "Wait a minute before another account or sign-in attempt.")
        self.auth_attempts.append(now)

    def handle_error(self, request, client_address):
        # Avoid default tracebacks containing request or account data.
        print("marketplace: a connection ended unexpectedly", file=sys.stderr)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    server_version = "ARCHiMarketplace/1"
    sys_version = ""

    def setup(self):
        self.request_id = str(uuid.uuid4())
        super().setup()

    def log_message(self, *_args):
        # No access logging: paths, queries, passwords and tokens are user data.
        pass

    def send_error(self, code, message=None, explain=None):
        self._respond(Response(code, {"error": {"code": "invalid_request", "message": "The HTTP request is invalid."},
                                      "requestID": self.request_id}))

    def _respond(self, response):
        raw = json_bytes(response.value)
        try:
            self.send_response(response.status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Request-ID", self.request_id)
            self.send_header("Connection", "close")
            for key, value in response.headers.items():
                self.send_header(key, value)
            self.end_headers()
            if self.command != "HEAD":
                self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            # The transaction may already be committed. Idempotent retry is the recovery path.
            pass
        self.close_connection = True

    def _single_header(self, key):
        values = self.headers.get_all(key, [])
        if len(values) > 1:
            raise APIError(400, "invalid_request", "Repeated security or framing headers are unsupported.")
        return values[0] if values else None

    def _handle_request(self):
        try:
            if sum(len(k) + len(v) for k, v in self.headers.items()) > 16_384:
                raise APIError(400, "invalid_request", "Request headers are too large.")
            if self._single_header("Host") != f"127.0.0.1:{self.server.server_port}":
                raise APIError(403, "host_forbidden", "Use this service's explicit loopback host and port.")
            if self._single_header("Origin") is not None:
                raise APIError(403, "origin_forbidden", "Browser-origin requests are disabled for this native development service.")
            if self._single_header("Transfer-Encoding") is not None or self._single_header("Content-Encoding") is not None:
                raise APIError(400, "invalid_request", "Encoded or chunked request bodies are unsupported.")
            length_value = self._single_header("Content-Length")
            if length_value is not None and (not length_value.isascii() or not length_value.isdigit() or len(length_value) > 8):
                raise APIError(400, "invalid_request", "Use a single bounded Content-Length.")
            length = int(length_value) if length_value is not None else 0
            if length > MAX_BODY:
                raise APIError(413, "body_too_large", "Request body cannot exceed 16,384 bytes.")
            if len(self.path) > 2048:
                raise APIError(400, "invalid_request", "Request URL is too long.")
            url = urlsplit(self.path)
            if url.scheme or url.netloc or url.fragment or not url.path.startswith("/"):
                raise APIError(400, "invalid_request", "Use a local API path.")
            try:
                query_items = parse_qsl(url.query, keep_blank_values=True, strict_parsing=True, max_num_fields=4,
                                        encoding="utf-8", errors="strict")
            except (ValueError, UnicodeError):
                raise APIError(400, "invalid_request", "Use valid bounded query parameters.") from None
            query = dict(query_items)
            if len(query) != len(query_items):
                raise APIError(400, "invalid_request", "Repeated query parameters are unsupported.")
            authorization = self._single_header("Authorization")
            token = None
            if authorization is not None:
                if not authorization.startswith("Bearer ") or len(authorization) != 50:
                    raise APIError(401, "unauthorized", "Use a valid bearer session.")
                token = authorization[7:]
            key = self._single_header("Idempotency-Key")
            body = None
            if self.command in {"POST", "PUT"}:
                if length_value is None:
                    raise APIError(411, "invalid_request", "A Content-Length is required.")
                content_type = self._single_header("Content-Type")
                if content_type is None or content_type.lower().replace(" ", "") not in {
                    "application/json", "application/json;charset=utf-8"
                }:
                    raise APIError(415, "unsupported_media_type", "Use application/json with UTF-8 encoding.")
                raw = self.rfile.read(length)
                if len(raw) != length:
                    raise APIError(400, "invalid_request", "The JSON request body was incomplete.")
                body = parse_json(raw)
            elif length:
                raise APIError(400, "invalid_request", "This method does not accept a request body.")
            if self.command == "POST" and url.path in {"/v1/accounts", "/v1/sessions"}:
                self.server.check_auth_rate()
            response = self.server.store.dispatch(self.command, url.path, body=body, query=query,
                                                  token=token, idempotency_key=key)
        except APIError as error:
            response = Response(error.status, {"error": {"code": error.code, "message": error.message},
                                                "requestID": self.request_id},
                                {"Retry-After": "60"} if error.code == "rate_limited" else {})
        except TimeoutError:
            response = Response(408, {"error": {"code": "invalid_request", "message": "Request body timed out."},
                                     "requestID": self.request_id})
        except (sqlite3.Error, OSError):
            response = Response(503, {"error": {"code": "storage_unavailable", "message": "Storage is unavailable. Retry with the same operation key."},
                                     "requestID": self.request_id})
        except (ValueError, UnicodeError):
            response = Response(400, {"error": {"code": "invalid_request", "message": "The request could not be decoded."},
                                     "requestID": self.request_id})
        self._respond(response)

    do_GET = do_POST = do_PUT = do_DELETE = do_OPTIONS = do_HEAD = do_PATCH = _handle_request


def main(argv=None):
    parser = argparse.ArgumentParser(description="Run ARCHi's local creator marketplace. No Internet publishing or commerce.")
    parser.add_argument("--database", required=True, type=Path, help="Explicit path to a private SQLite database (created if absent).")
    parser.add_argument("--port", type=int, default=47831, help="Loopback port (default: 47831).")
    args = parser.parse_args(argv)
    if not 1 <= args.port <= 65535:
        parser.error("port must be 1–65535")
    try:
        store = Store(args.database)
        with LocalServer(store, args.port) as server:
            def terminate(_signum, _frame):
                raise KeyboardInterrupt
            signal.signal(signal.SIGTERM, terminate)
            print(f"ARCHi creator marketplace · DEVELOPMENT · http://127.0.0.1:{server.server_port}", flush=True)
            print("Persistent local database selected. Catalog starts empty. Ctrl-C stops the service.", flush=True)
            try:
                server.serve_forever(poll_interval=0.25)
            except KeyboardInterrupt:
                pass
    except (OSError, sqlite3.Error, ValueError):
        print("Cannot start marketplace. Check database ownership/schema, private file permissions and loopback port availability.", file=sys.stderr)
        return 1
    return 0
