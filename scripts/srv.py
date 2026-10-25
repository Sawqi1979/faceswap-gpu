import http.server, os
TOKEN = os.environ["FS_TOKEN"]
FILES = {"status": "/work/status", "log": "/work/job.log", "result.mp4": "/work/out/result.mp4",
         "facefusion.mp4": "/work/out/facefusion.mp4"}
class H(http.server.BaseHTTPRequestHandler):
    def _ok(self):
        if not self.path.startswith("/" + TOKEN + "/"):
            self.send_response(403); self.end_headers(); return False
        return True
    def do_PUT(self):
        if not self._ok(): return
        name = os.path.basename(self.path)
        if name not in ("swap_input.mp4", "swap_face.jpg", "ready"):
            self.send_response(400); self.end_headers(); return
        n = int(self.headers.get("Content-Length", 0)); rem = n
        with open("/work/in/" + name + ".part", "wb") as f:
            while rem > 0:
                b = self.rfile.read(min(1 << 20, rem))
                if not b: break
                f.write(b); rem -= len(b)
        os.replace("/work/in/" + name + ".part", "/work/in/" + name)
        self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
    def do_GET(self):
        if not self._ok(): return
        p = FILES.get(os.path.basename(self.path))
        if not p or not os.path.exists(p):
            self.send_response(404); self.end_headers(); return
        data = open(p, "rb").read()
        if p.endswith(".log"): data = data[-15000:]
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers()
        self.wfile.write(data)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("0.0.0.0", 8000), H).serve_forever()
