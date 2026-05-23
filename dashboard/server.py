#!/usr/bin/env python3
"""
youtube-live-ultra — dashboard v3 (stdlib only, zero pip deps).
Python 3.7+ stdlib: http.server + json + socket + threading.
No Flask, no flask-sock, no pip install needed.
HTML chargé depuis templates/index.html.

Usage: python3 dashboard/server.py <URL_YOUTUBE_LIVE> [--port 9191] [--mode ultra|standard|direct]
"""
import sys, os, json, time, socket, signal, subprocess, threading
from http.server import HTTPServer, BaseHTTPRequestHandler

PORT = 9191
URL = ""
MODE = "standard"
IPC_SOCKET = ""
MPV_PID = None
RUNNING = False
CHAT_FILE = ""

stats = {
    "time_pos": 0, "paused": False, "resolution": "?", "fps": 0,
    "dropped_frames": 0, "cache_duration": 0, "video_codec": "?",
    "audio_codec": "?", "bitrate": 0, "hwdec": "?"
}
chat_messages = []
stream_title = ""

# ─── HTML ────────────────────────────────────────────────────────────────────
HTML = ""
_HTML_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates", "index.html")
if os.path.exists(_HTML_PATH):
    with open(_HTML_PATH) as f:
        HTML = f.read()
else:
    HTML = "<h1>Dashboard</h1><p>templates/index.html not found</p>"

# ─── MPV IPC ─────────────────────────────────────────────────────────────────
def mpv_cmd(cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3); s.connect(IPC_SOCKET)
        s.send((json.dumps(cmd) + "\n").encode())
        r = b""
        while True:
            c = s.recv(4096)
            if not c: break
            r += c
            if b"\n" in r: break
        s.close()
        return json.loads(r.decode().strip())
    except: return None

def mpv_prop(name):
    r = mpv_cmd({"command": ["get_property", name]})
    return r.get("data") if r and "data" in r else None

def poll_stats():
    while RUNNING:
        try:
            vp = mpv_prop("video-params")
            if vp: stats["resolution"] = f"{vp.get('w','?')}x{vp.get('h','?')}"; stats["video_codec"] = vp.get("codec","?")
            ap = mpv_prop("audio-params")
            if ap: stats["audio_codec"] = ap.get("codec","?")
            stats["paused"] = mpv_prop("pause") or False
            stats["time_pos"] = mpv_prop("time-pos") or 0
            stats["fps"] = mpv_prop("estimated-vf-fps") or 0
            stats["dropped_frames"] = mpv_prop("vo-drop-frame-count") or 0
            stats["cache_duration"] = mpv_prop("demuxer-cache-duration") or 0
            stats["hwdec"] = mpv_prop("hwdec-current") or "?"
            stats["bitrate"] = mpv_prop("video-bitrate") or 0
        except: pass
        time.sleep(0.5)

def poll_chat():
    global chat_messages, CHAT_FILE
    while RUNNING:
        try:
            if not CHAT_FILE:
                CHAT_FILE = f"/tmp/yt-live-chat-{os.getpid()}.json"
                subprocess.Popen(
                    ["yt-dlp", "--write-live-chat", "-o", CHAT_FILE,
                     "--skip-download", "--playlist-end", "1", URL],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if os.path.exists(CHAT_FILE):
                with open(CHAT_FILE, 'r') as f:
                    for line in f:
                        try:
                            msg = json.loads(line.strip())
                            if msg.get("replayChatItemAction"):
                                for a in msg["replayChatItemAction"]["actions"]:
                                    item = a.get("addChatItemAction", {}).get("item", {})
                                    live = item.get("liveChatTextMessageRenderer", {})
                                    if live:
                                        text = "".join(r.get("text","") for r in live.get("message",{}).get("runs",[]))
                                        author = live.get("authorName",{}).get("simpleText","?")
                                        chat_messages.append({"author":author,"text":text,"time":time.time()})
                        except: pass
                with open(CHAT_FILE, 'w') as f: pass  # clear
            chat_messages = chat_messages[-200:]
        except: pass
        time.sleep(2)

# ─── HTTP HANDLER ────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ('/', '/index.html'):
            self._respond(200, "text/html", HTML.encode())
        elif self.path == '/api/stats':
            self._respond(200, "application/json", json.dumps(stats).encode())
        elif self.path == '/api/chat':
            self._respond(200, "application/json", json.dumps(chat_messages[-30:]).encode())
        elif self.path == '/cmd/pause':
            mpv_cmd({"command": ["cycle", "pause"]})
            self._respond(200, "text/plain", b"ok")
        elif self.path.startswith('/cmd/quality/'):
            mpv_cmd({"command": ["set_property", "ytdl-format", self.path.split('/')[-1]]})
            self._respond(200, "text/plain", b"ok")
        elif self.path == '/cmd/stop':
            cleanup()
            self._respond(200, "text/plain", b"ok")
        else:
            self._respond(404, "text/plain", b"not found")
    def _respond(self, code, ct, body):
        self.send_response(code)
        self.send_header("Content-Type", ct)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass

# ─── MPV CONTROL ─────────────────────────────────────────────────────────────
def launch_mpv():
    global IPC_SOCKET, MPV_PID, RUNNING
    IPC_SOCKET = f"/tmp/mpv-dash-{os.getpid()}"
    args = ["mpv", f"--input-ipc-server={IPC_SOCKET}",
            "--profile=low-latency", "--cache=yes", "--demuxer-max-bytes=2M",
            "--demuxer-readahead-secs=0.2", "--video-latency-hacks=yes",
            "--framedrop=vo", "--video-sync=audio", "--vd-lavc-threads=4",
            "--audio-buffer=0.2", "--keep-open=no", "--force-window=yes",
            "--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best",
            "--hwdec=videotoolbox", "--vo=gpu-next"]
    if MODE == "ultra":
        args.extend(["--cache=no", "--demuxer-max-bytes=500K", "--framedrop=vo+decoder"])
    args.append(URL)
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    MPV_PID = proc.pid
    RUNNING = True
    for _ in range(30):
        if os.path.exists(IPC_SOCKET): break
        time.sleep(0.2)

def cleanup():
    global RUNNING
    RUNNING = False
    if MPV_PID:
        try: os.kill(MPV_PID, signal.SIGTERM)
        except: pass
    for p in [IPC_SOCKET, CHAT_FILE]:
        if p and os.path.exists(p):
            try: os.unlink(p)
            except: pass

# ─── MAIN ────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: dashboard/server.py <URL> [--port PORT] [--mode MODE]")
        sys.exit(1)
    URL = sys.argv[1]
    for i, a in enumerate(sys.argv[2:], 2):
        if a == "--port" and i+1 < len(sys.argv): PORT = int(sys.argv[i+1])
        elif a == "--mode" and i+1 < len(sys.argv): MODE = sys.argv[i+1]
    print(f"🎬 Dashboard v3 (stdlib) — {URL}")
    launch_mpv()
    print(f"✅ mpv PID: {MPV_PID}, IPC: {IPC_SOCKET}")
    threading.Thread(target=poll_stats, daemon=True).start()
    threading.Thread(target=poll_chat, daemon=True).start()
    signal.signal(signal.SIGINT, lambda s,f: (cleanup(), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda s,f: (cleanup(), sys.exit(0)))
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"🌐 http://localhost:{PORT}")
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: cleanup()
