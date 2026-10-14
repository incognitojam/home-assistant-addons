"""Local deterministic API responses; the tests still run the real Claude UI."""

import json
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{}')

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        if self.path.startswith("/v1/messages/count_tokens"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(b'{"input_tokens": 10}')
            return
        if not self.path.startswith("/v1/messages"):
            self.send_error(404)
            return

        # A multi-line response exercises real renderer scrolling and selection.
        reply = "\n".join(f"Synthetic renderer line {i:03}" for i in range(1, 81))
        message = {"id": "msg_synthetic_renderer", "type": "message", "role": "assistant",
                   "model": body.get("model"), "content": [{"type": "text", "text": reply}],
                   "stop_reason": "end_turn", "stop_sequence": None,
                   "usage": {"input_tokens": 10, "output_tokens": 100}}
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream" if body.get("stream") else "application/json")
        self.end_headers()
        if not body.get("stream"):
            self.wfile.write(json.dumps(message).encode())
            return

        def event(kind, **data):
            self.wfile.write(f"event: {kind}\ndata: {json.dumps(dict(type=kind, **data))}\n\n".encode())
            self.wfile.flush()

        event("message_start", message=dict(message, content=[], stop_reason=None,
                                            usage={"input_tokens": 10, "output_tokens": 0}))
        event("content_block_start", index=0, content_block={"type": "text", "text": ""})
        for line in reply.splitlines():
            event("content_block_delta", index=0, delta={"type": "text_delta", "text": line + "\n"})
            time.sleep(0.025)
        event("content_block_stop", index=0)
        event("message_delta", delta={"stop_reason": "end_turn", "stop_sequence": None},
              usage={"output_tokens": 100})
        event("message_stop")


ThreadingHTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
