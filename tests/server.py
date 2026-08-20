import json
import sys
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

BODY_FILE = sys.argv[1] if len(sys.argv) > 1 else "request_body.txt"
PORT = int(sys.argv[2]) if len(sys.argv) > 2 else 18080


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, json.dumps({"ok": True}))
        else:
            self._send(404, json.dumps({"error": {"message": "not found"}}))

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length).decode("utf-8")
        with open(BODY_FILE, "w", encoding="utf-8") as f:
            f.write(body)

        data = json.loads(body) if body else {}
        prompt = (data.get("prompt") or "").strip()

        if self.path == "/beta/completions":
            if prompt == "FAIL":
                return self._send(200, json.dumps({"error": {"message": "boom"}}))
            if prompt == "GARBAGE":
                return self._send(200, "this is not json")
            if prompt == "SLOW":
                time.sleep(10)
                return self._send(200, json.dumps({"choices": [{"text": "late"}]}))
            return self._send(200, json.dumps({"choices": [{"text": "    return fib(n-1) + fib(n-2)"}]}))
        elif self.path == "/beta/chat/completions":
            return self._send(200, json.dumps({"choices": [{"message": {"content": "    return total"}}]}))
        else:
            return self._send(404, json.dumps({"error": {"message": "not found"}}))


HTTPServer(("127.0.0.1", PORT), H).serve_forever()
