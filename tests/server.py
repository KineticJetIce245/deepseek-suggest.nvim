import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

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

    def _send_stream(self, chunks, total_tokens=0):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        for text, _code in chunks:
            event = json.dumps({"choices": [{"index": 0, "text": text}]})
            self.wfile.write(("data: " + event + "\n\n").encode("utf-8"))
            self.wfile.flush()
            time.sleep(0.05)
        if total_tokens:
            event = json.dumps({"choices": [], "usage": {"total_tokens": total_tokens}})
            self.wfile.write(("data: " + event + "\n\n").encode("utf-8"))
            self.wfile.flush()
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

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
        stream = bool(data.get("stream"))

        if self.path == "/beta/completions":
            if prompt == "FAIL":
                return self._send(200, json.dumps({"error": {"message": "boom"}}))
            if prompt == "NOBALANCE":
                return self._send(402, json.dumps({"error": {"message": "Insufficient Balance"}}))
            if prompt == "GARBAGE":
                return self._send(200, "this is not json")
            if prompt == "STREAMEMPTY":
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.end_headers()
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
                return
            if prompt == "SLOW":
                time.sleep(10)
                return self._send(200, json.dumps({"choices": [{"text": "late"}]}))
            if stream:
                return self._send_stream(
                    [
                        ("    return ", 200),
                        ("fib(", 200),
                        ("n-1) + fib(n-2)", 200),
                    ],
                    total_tokens=42,
                )
            return self._send(
                200,
                json.dumps(
                    {
                        "choices": [{"text": "    return fib(n-1) + fib(n-2)"}],
                        "usage": {"total_tokens": 42},
                    }
                ),
            )
        elif self.path == "/beta/chat/completions":
            return self._send(
                200,
                json.dumps(
                    {
                        "choices": [{"message": {"content": "    return total"}}],
                        "usage": {"total_tokens": 17},
                    }
                ),
            )
        else:
            return self._send(404, json.dumps({"error": {"message": "not found"}}))


ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
