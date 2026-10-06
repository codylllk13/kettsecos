"""Per-user Unix socket task service."""
import json
import os
import socketserver
from .service import TaskService, _socket_path


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        try:
            line = self.rfile.readline(1_000_001)
            if len(line) > 1_000_000: raise ValueError("Request too large")
            request = json.loads(line)
            response = {"ok": True, "data": SERVICE.handle(request)}
        except Exception as exc:
            response = {"ok": False, "error": str(exc)}
        self.wfile.write(json.dumps(response).encode() + b"\n")


class Server(socketserver.UnixStreamServer):
    allow_reuse_address = True


SERVICE = TaskService()


def main():
    path = _socket_path()
    if os.path.exists(path):
        probe = __import__("socket").socket(__import__("socket").AF_UNIX, __import__("socket").SOCK_STREAM)
        try:
            probe.connect(path)
            return
        except OSError:
            os.unlink(path)
        finally:
            probe.close()
    with Server(path, Handler) as server:
        os.chmod(path, 0o600)
        server.serve_forever()


if __name__ == "__main__": main()
