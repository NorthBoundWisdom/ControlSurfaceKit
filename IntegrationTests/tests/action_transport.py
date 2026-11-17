#!/usr/bin/env python3
"""Actual SDK RPC, forwarding to the parent production registry, then losing one reply."""
import argparse
import http.server
import json
from pathlib import Path
import socket
import socketserver
import sys
import threading


def emit(value):
    raw = json.dumps(value, allow_nan=False, separators=(",", ":"))
    assert len(raw.encode()) <= 65536
    print(raw, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sdk-root", type=Path, required=True)
    parser.add_argument("--retry-after-loss", action="store_true")
    args = parser.parse_args()
    sys.path.insert(0, str(args.sdk_root))
    from surface_control import Client, SurfaceError
    requests = []
    lost_responses = 0
    errors = []

    class LiteralLoopbackServer(http.server.HTTPServer):
        def server_bind(self):
            socketserver.TCPServer.server_bind(self)
            self.server_name, self.server_port = self.server_address

    class Handler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"
        def setup(self):
            super().setup()
            self.connection.settimeout(3)
        def log_message(self, *_):
            pass
        def do_POST(self):
            nonlocal lost_responses
            size = int(self.headers.get("Content-Length", "0"))
            assert 0 < size <= 65536 and self.path == "/mcp"
            request = json.loads(self.rfile.read(size))
            assert request["method"] == "tools/call"
            requests.append(request)
            assert len(requests) <= 2
            emit(dict(event="rpc", request=request))
            line = sys.stdin.buffer.readline(65538)
            assert len(line) <= 65537 and line.endswith(b"\n")
            result = json.loads(line)
            assert result["event"] == "committed" and result["id"] == request["id"]
            if lost_responses == 0:
                lost_responses += 1
                self.close_connection = True
                self.connection.shutdown(socket.SHUT_RDWR)
                self.connection.close()
                return
            body = json.dumps(dict(jsonrpc="2.0", id=request["id"], result=result["result"]), allow_nan=False).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(body)

    server = LiteralLoopbackServer(("127.0.0.1", 0), Handler)
    server.socket.settimeout(3)
    worker = threading.Thread(target=server.serve_forever, kwargs={"poll_interval": 0.01}, daemon=True)
    worker.start()
    client = Client("http://127.0.0.1:" + str(server.server_port) + "/mcp", "test-only-no-privilege",
                    "offline.actions", protocol="2026-07-28", timeout=2)
    automatic_retry_attempts = 0
    try:
        client.rpc("tools/call", dict(name="surface_agent_primary", arguments=dict(instance_id="fire1", slot=1)))
    except SurfaceError as error:
        errors.append(error.code)
        if args.retry_after_loss:
            automatic_retry_attempts += 1
            client.rpc("tools/call", dict(name="surface_agent_primary", arguments=dict(instance_id="fire1", slot=1)))
    finally:
        server.shutdown(); server.server_close(); worker.join(timeout=2)
    assert not worker.is_alive()
    emit(dict(event="complete", client_errors=errors, lost_responses=lost_responses,
              upstream_request_ids=[request["id"] for request in requests],
              automatic_retry_attempts=automatic_retry_attempts))


if __name__ == "__main__":
    main()
