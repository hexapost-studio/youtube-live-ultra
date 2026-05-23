#!/usr/bin/env python3
"""
youtube-live-ultra — dashboard v2 (stdlib only, zero pip deps).
Python 3.7+ stdlib: http.server + json + socket + threading.
No Flask, no flask-sock, no pip install needed.

Usage: python3 dashboard/server.py <URL_YOUTUBE_LIVE> [--port 9191] [--mode ultra|standard|direct]
"""
import sys, os, json, time, socket, signal, subprocess, threading, re
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

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
quality = "best"

# ─── MPV IPC ─────────────────────────────────────────────────────────────────

def mpv_cmd(cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(IPC_SOCKET)
        s.send((json.dumps(cmd) + "\n").encode())
        resp = b""
        while True:
            c = s.recv(4096)
            if not c: break
            resp += c
            if b"\n" in resp: break
        s.close()
        return json.loads(resp.decode().strip())
    except: return None

def mpv_prop(name):
    r = mpv_cmd({"command": ["get_property", name]})
    return r.get("data") if r and "data" in r else None

def poll_stats():
    global stats
    while RUNNING:
        try:
            vp = mpv_prop("video-params")
            if vp:
                stats["resolution"] = f"{vp.get('w','?')}x{vp.get('h','?')}"
                stats["video_codec"] = vp.get("codec", "?")
            ap = mpv_prop("audio-params")
            if ap: stats["audio_codec"] = ap.get("codec", "?")
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
    global chat_messages, stream_title, CHAT_FILE
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
                                actions = msg["replayChatItemAction"]["actions"]
                                for a in actions:
                                    item = a.get("addChatItemAction", {}).get("item", {})
                                    live_msg = item.get("liveChatTextMessageRenderer", {})
                                    if live_msg:
                                        text = "".join(
                                            r.get("text", "") for r in
                                            live_msg.get("message", {}).get("runs", []))
                                        author = live_msg.get("authorName", {}).get("simpleText", "?")
                                        chat_messages.append({
                                            "author": author, "text": text, "time": time.time()
                                        })
                        except: pass
                os.truncate(open(CHAT_FILE, 'r+'), 0)  # clear file
            chat_messages = chat_messages[-200:]
        except: pass
        time.sleep(2)

# ─── HTTP SERVER ─────────────────────────────────────────────────────────────

HTML = """<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>YouTube Live Ultra</title><style>
:root{--bg:#0a0a0f;--surf:#14141f;--bord:#1e1e30;--txt:#c8c8d4;--muted:#6b6b80;--green:#22c55e;--warn:#f59e0b;--red:#ef4444;--blue:#3b82f6;--rad:8px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:var(--bg);color:var(--txt);height:100vh;overflow:hidden}
.app{display:flex;height:100vh}
.main{flex:1;display:flex;flex-direction:column;min-width:0}
.topbar{display:flex;align-items:center;gap:12px;padding:12px 16px;background:var(--surf);border-bottom:1px solid var(--bord);flex-shrink:0}
.topbar h1{font-size:15px;font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.badge{font-size:10px;padding:2px 8px;border-radius:10px;background:var(--green);color:#000;font-weight:600}
.spacer{flex:1}
.btn{padding:6px 14px;border-radius:var(--rad);border:1px solid var(--bord);background:var(--surf);color:var(--txt);cursor:pointer;font-size:13px;transition:.15s}
.btn:hover{background:#222;border-color:#333}
.btn.primary{background:var(--blue);border-color:var(--blue);color:#fff}
.btn.danger{background:var(--red);border-color:var(--red);color:#fff}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:8px;padding:12px 16px;flex-shrink:0}
.stat{background:var(--surf);border:1px solid var(--bord);border-radius:var(--rad);padding:10px 14px}
.stat .label{font-size:10px;color:var(--muted);text-transform:uppercase;letter-spacing:.5px}
.stat .value{font-size:19px;font-weight:700;font-variant-numeric:tabular-nums}
.stat .green{color:var(--green)}.stat .yellow{color:var(--warn)}.stat .red{color:var(--red)}
.vid{flex:1;display:flex;align-items:center;justify-content:center;color:var(--muted);font-size:13px}
.chat{width:320px;background:var(--surf);border-left:1px solid var(--bord);display:flex;flex-direction:column;flex-shrink:0}
.chat-h{padding:12px 16px;border-bottom:1px solid var(--bord);font-weight:600;font-size:13px}
.chat-msgs{flex:1;overflow-y:auto;padding:8px;display:flex;flex-direction:column;gap:3px}
.chat-msg{font-size:12px;line-height:1.4;padding:3px 8px;border-radius:4px;background:rgba(255,255,255,0.03);animation:fadeIn .3s}
.chat-msg .author{font-weight:600;color:var(--blue);margin-right:4px}
@keyframes fadeIn{from{opacity:0;transform:translateY(4px)}to{opacity:1;transform:translateY(0)}}
.controls{display:flex;gap:8px;padding:12px 16px;background:var(--surf);border-top:1px solid var(--bord);flex-shrink:0}
select.btn{appearance:none;padding-right:28px}
.dot{width:8px;height:8px;border-radius:50%;background:var(--green);animation:pulse 2s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
</style></head><body>
<div class="app"><div class="main">
<div class="topbar"><div class="dot"></div><h1 id="title">YouTube Live Ultra</h1><span class="badge" id="liveBadge">LIVE</span><span class="spacer"></span><span style="font-size:11px;color:var(--muted)" id="clock">00:00:00</span><button class="btn danger" onclick="fetch('/cmd/stop')">⏹</button></div>
<div class="stats">
<div class="stat"><div class="label">Latence</div><div class="value green" id="latency">--</div></div>
<div class="stat"><div class="label">Buffer</div><div class="value" id="buffer">--</div></div>
<div class="stat"><div class="label">Résolution</div><div class="value" id="res">--</div></div>
<div class="stat"><div class="label">FPS</div><div class="value" id="fps">--</div></div>
<div class="stat"><div class="label">Drops</div><div class="value" id="drops">--</div></div>
<div class="stat"><div class="label">Codec</div><div class="value" id="codec">--</div></div>
<div class="stat"><div class="label">Décodeur</div><div class="value" id="hwdec">--</div></div>
<div class="stat"><div class="label">Débit</div><div class="value" id="bitrate">--</div></div>
</div>
<div class="vid">🎬 La vidéo joue dans la fenêtre mpv</div>
<div class="controls">
<button class="btn" onclick="fetch('/cmd/pause')">⏯ Pause</button>
<select class="btn" onchange="fetch('/cmd/quality/'+this.value)"><option value="best">Auto</option><option value="1080p">1080p</option><option value="720p">720p</option><option value="480p">480p</option></select>
<span class="spacer"></span><span style="font-size:10px;color:var(--muted)">stdlib only · 0 deps</span>
</div></div>
<div class="chat"><div class="chat-h">💬 Live Chat</div><div class="chat-msgs" id="chatMsgs"><div style="color:var(--muted);font-size:12px;padding:12px">Connexion au chat...</div></div></div>
</div>
<script>
let start=Date.now(),chatN=0;
setInterval(()=>{let e=Math.floor((Date.now()-start)/1000);document.getElementById('clock').textContent=new Date(e*1000).toISOString().substr(11,8)},1000);
async function poll(){try{let r=await fetch('/api/stats');if(!r.ok)return;let s=await r.json();let l=s.cache_duration?(s.cache_duration+2).toFixed(1)+'s':'--';document.getElementById('latency').textContent=l;let b=s.cache_duration?s.cache_duration.toFixed(1)+'s':'--',be=document.getElementById('buffer');be.textContent=b;be.className='value '+(s.cache_duration>20?'red':s.cache_duration>8?'yellow':'green');document.getElementById('res').textContent=s.resolution||'--';document.getElementById('fps').textContent=s.fps?s.fps.toFixed(1):'--';document.getElementById('drops').textContent=s.dropped_frames||'0';document.getElementById('codec').textContent=s.video_codec||'--';document.getElementById('hwdec').textContent=s.hwdec||'--';document.getElementById('bitrate').textContent=s.bitrate?(s.bitrate/1000).toFixed(1)+' Mbps':'--'}catch(e){}}
async function pollChat(){try{let r=await fetch('/api/chat');if(!r.ok)return;let msgs=await r.json();if(chatN===0)document.getElementById('chatMsgs').innerHTML='';msgs.forEach(m=>{chatN++;let d=document.createElement('div');d.className='chat-msg';d.innerHTML='<span class="author">'+esc(m.author)+'</span>'+esc(m.text);document.getElementById('chatMsgs').appendChild(d)});let c=document.getElementById('chatMsgs');c.scrollTop=c.scrollHeight}catch(e){}}
function esc(s){let d=document.createElement('div');d.textContent=s;return d.innerHTML}
setInterval(poll,500);setInterval(pollChat,2000);poll();pollChat();
</script></body></html>"""

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/' or self.path == '/index.html':
            self._respond(200, "text/html", HTML.encode())
        elif self.path == '/api/stats':
            self._respond(200, "application/json", json.dumps(stats).encode())
        elif self.path == '/api/chat':
            self._respond(200, "application/json", json.dumps(chat_messages[-30:]).encode())
        elif self.path == '/api/title':
            self._respond(200, "text/plain", stream_title.encode())
        elif self.path == '/cmd/pause':
            mpv_cmd({"command": ["cycle", "pause"]})
            self._respond(200, "text/plain", b"ok")
        elif self.path.startswith('/cmd/quality/'):
            q = self.path.split('/')[-1]
            mpv_cmd({"command": ["set_property", "ytdl-format", q]})
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
    
    def log_message(self, *args): pass  # silence

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
    return proc

def cleanup():
    global RUNNING
    RUNNING = False
    if MPV_PID:
        try: os.kill(MPV_PID, signal.SIGTERM)
        except: pass
    if IPC_SOCKET and os.path.exists(IPC_SOCKET):
        try: os.unlink(IPC_SOCKET)
        except: pass
    if CHAT_FILE and os.path.exists(CHAT_FILE):
        try: os.unlink(CHAT_FILE)
        except: pass

# ─── MAIN ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: dashboard/server.py <URL_YOUTUBE_LIVE> [--port PORT] [--mode MODE]")
        sys.exit(1)
    
    URL = sys.argv[1]
    for i, a in enumerate(sys.argv[2:], 2):
        if a == "--port" and i+1 < len(sys.argv):
            PORT = int(sys.argv[i+1])
        elif a == "--mode" and i+1 < len(sys.argv):
            MODE = sys.argv[i+1]
    
    print(f"🎬 Dashboard v2 (stdlib) — {URL}")
    launch_mpv()
    print(f"✅ mpv PID: {MPV_PID}")
    
    threading.Thread(target=poll_stats, daemon=True).start()
    threading.Thread(target=poll_chat, daemon=True).start()
    
    signal.signal(signal.SIGINT, lambda s,f: (cleanup(), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda s,f: (cleanup(), sys.exit(0)))
    
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    print(f"🌐 http://localhost:{PORT}")
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally: cleanup()
