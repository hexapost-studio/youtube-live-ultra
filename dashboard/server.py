#!/usr/bin/env python3
"""
youtube-live-ultra — dashboard server.
Lance mpv avec IPC, expose stats + chat via WebSocket, sert l'UI web.

Usage: python3 dashboard/server.py <URL_YOUTUBE_LIVE> [--port 9191] [--mode ultra|standard|direct]
"""
import sys
import os
import json
import time
import socket
import subprocess
import threading
import signal
import re
from pathlib import Path

from flask import Flask, render_template, request, jsonify
from flask_sock import Sock

app = Flask(__name__)
sock = Sock(app)

# ─── STATE ───────────────────────────────────────────────────────────────────
state = {
    "url": "",
    "mode": "standard",
    "mpv_pid": None,
    "ipc_socket": "",
    "running": False,
    "stats": {
        "time_pos": 0, "paused": False, "resolution": "?",
        "fps": 0, "dropped_frames": 0, "cache_duration": 0,
        "cache_speed": 0, "video_codec": "?", "audio_codec": "?",
        "bitrate": 0, "hwdec": "?"
    },
    "chat_messages": [],
    "stream_title": "",
    "quality": "best",
    "start_time": 0
}

clients = []

# ─── MPV IPC ─────────────────────────────────────────────────────────────────

def mpv_ipc_send(cmd):
    """Send a JSON command to mpv via IPC socket."""
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(state["ipc_socket"])
        s.send((json.dumps(cmd) + "\n").encode())
        response = b""
        while True:
            chunk = s.recv(4096)
            if not chunk:
                break
            response += chunk
            if b"\n" in response:
                break
        s.close()
        return json.loads(response.decode().strip())
    except Exception:
        return None

def mpv_get_property(name):
    """Get a property from mpv via IPC."""
    result = mpv_ipc_send({"command": ["get_property", name]})
    if result and "data" in result:
        return result["data"]
    return None

def mpv_poll_stats():
    """Poll mpv for stats every 500ms."""
    while state["running"]:
        try:
            res = mpv_get_property("video-params")
            if res:
                state["stats"]["resolution"] = f"{res.get('w','?')}x{res.get('h','?')}"
                state["stats"]["video_codec"] = res.get("codec", "?")
            
            res = mpv_get_property("audio-params")
            if res:
                state["stats"]["audio_codec"] = res.get("codec", "?")
            
            state["stats"]["paused"] = mpv_get_property("pause") or False
            state["stats"]["time_pos"] = mpv_get_property("time-pos") or 0
            state["stats"]["fps"] = mpv_get_property("estimated-vf-fps") or 0
            state["stats"]["dropped_frames"] = mpv_get_property("vo-drop-frame-count") or 0
            state["stats"]["cache_duration"] = mpv_get_property("demuxer-cache-duration") or 0
            state["stats"]["cache_speed"] = mpv_get_property("cache-speed") or 0
            state["stats"]["hwdec"] = mpv_get_property("hwdec-current") or "?"
            
            # Estimer le bitrate
            fps = state["stats"]["fps"] or 30
            cache_dur = state["stats"]["cache_duration"] or 0
            state["stats"]["bitrate"] = mpv_get_property("video-bitrate") or 0
            
            # Broadcast aux clients
            broadcast({"type": "stats", "data": state["stats"]})
            
        except Exception:
            pass
        
        time.sleep(0.5)

def broadcast(msg):
    """Send to all connected WebSocket clients."""
    dead = []
    for c in clients:
        try:
            c.send(json.dumps(msg))
        except Exception:
            dead.append(c)
    for d in dead:
        clients.remove(d)

# ─── YOUTUBE CHAT ────────────────────────────────────────────────────────────

def fetch_chat():
    """Poll YouTube live chat via yt-dlp."""
    while state["running"]:
        try:
            result = subprocess.run(
                ["yt-dlp", "--print", "%(title)s", "--skip-download",
                 "--playlist-end", "1", state["url"]],
                capture_output=True, text=True, timeout=5
            )
            if result.stdout.strip():
                state["stream_title"] = result.stdout.strip().split("\n")[0]
            
            # Récupérer le chat via l'API yt-dlp
            chat_result = subprocess.run(
                ["yt-dlp", "--get-comments", "--skip-download",
                 "--playlist-end", "1", state["url"]],
                capture_output=True, text=True, timeout=10
            )
            lines = chat_result.stdout.strip().split("\n")
            for line in lines[-20:]:
                if line.strip() and line.strip() not in [m["text"] for m in state["chat_messages"][-50:]]:
                    state["chat_messages"].append({
                        "text": line.strip(),
                        "time": time.time()
                    })
            
            # Garder max 200 messages
            state["chat_messages"] = state["chat_messages"][-200:]
            
            broadcast({"type": "chat", "data": state["chat_messages"][-10:]})
            broadcast({"type": "title", "data": state["stream_title"]})
            
        except Exception:
            pass
        
        time.sleep(3)

# ─── WEBSOCKET ───────────────────────────────────────────────────────────────

@sock.route('/ws')
def ws_handler(ws):
    clients.append(ws)
    # Envoyer l'état actuel
    ws.send(json.dumps({"type": "stats", "data": state["stats"]}))
    ws.send(json.dumps({"type": "chat", "data": state["chat_messages"][-10:]}))
    ws.send(json.dumps({"type": "title", "data": state["stream_title"]}))
    try:
        while True:
            msg = ws.receive()
            if msg:
                handle_command(json.loads(msg))
    except Exception:
        pass
    finally:
        if ws in clients:
            clients.remove(ws)

def handle_command(cmd):
    """Handle commands from the web UI."""
    action = cmd.get("action", "")
    if action == "pause":
        mpv_ipc_send({"command": ["cycle", "pause"]})
    elif action == "seek":
        mpv_ipc_send({"command": ["seek", cmd.get("seconds", 0), "relative"]})
    elif action == "quality":
        state["quality"] = cmd.get("quality", "best")
        # Relancer avec la nouvelle qualité
        restart_stream()
    elif action == "stop":
        cleanup()

# ─── ROUTES ──────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    return render_template('index.html', 
        url=state["url"], 
        mode=state["mode"],
        title=state["stream_title"] or "YouTube Live Ultra")

@app.route('/api/status')
def api_status():
    return jsonify({
        "running": state["running"],
        "mpv_pid": state["mpv_pid"],
        "stats": state["stats"],
        "title": state["stream_title"],
        "url": state["url"]
    })

@app.route('/api/command', methods=['POST'])
def api_command():
    cmd = request.get_json() or {}
    handle_command(cmd)
    return jsonify({"ok": True})

# ─── STREAM CONTROL ──────────────────────────────────────────────────────────

def launch_mpv(url, mode="standard"):
    """Launch mpv with IPC server."""
    socket_path = f"/tmp/mpv-dashboard-{os.getpid()}"
    state["ipc_socket"] = socket_path
    
    args = [
        "mpv", f"--input-ipc-server={socket_path}",
        "--profile=low-latency",
        "--cache=yes", "--demuxer-max-bytes=2M", "--demuxer-readahead-secs=0.2",
        "--video-latency-hacks=yes", "--framedrop=vo", "--video-sync=audio",
        "--vd-lavc-threads=4", "--audio-buffer=0.2",
        "--keep-open=no", "--force-window=yes",
        "--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best",
        "--hwdec=videotoolbox", "--vo=gpu-next"
    ]
    
    if mode == "ultra":
        args.extend(["--cache=no", "--demuxer-max-bytes=500K",
                      "--video-latency-hacks=yes", "--framedrop=vo+decoder"])
    
    args.append(url)
    
    proc = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    state["mpv_pid"] = proc.pid
    state["running"] = True
    state["start_time"] = time.time()
    
    # Attendre que le socket IPC soit prêt
    for _ in range(30):
        if os.path.exists(socket_path):
            break
        time.sleep(0.2)
    
    return proc

def restart_stream():
    """Restart the stream with new quality."""
    cleanup_mpv()
    time.sleep(1)
    launch_mpv(state["url"], state["mode"])

def cleanup_mpv():
    """Stop mpv."""
    if state["mpv_pid"]:
        try:
            os.kill(state["mpv_pid"], signal.SIGTERM)
        except Exception:
            pass
        state["mpv_pid"] = None
    state["running"] = False
    if state["ipc_socket"] and os.path.exists(state["ipc_socket"]):
        os.unlink(state["ipc_socket"])

def cleanup():
    """Clean shutdown."""
    cleanup_mpv()
    state["running"] = False

# ─── MAIN ────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage: dashboard/server.py <URL_YOUTUBE_LIVE> [--port PORT] [--mode MODE]")
        sys.exit(1)
    
    state["url"] = sys.argv[1]
    port = 9191
    
    for i, arg in enumerate(sys.argv[2:], 2):
        if arg == "--port" and i + 1 < len(sys.argv):
            port = int(sys.argv[i + 1])
        elif arg == "--mode" and i + 1 < len(sys.argv):
            state["mode"] = sys.argv[i + 1]
    
    # Lancer mpv
    print(f"🎬 Lancement mpv pour {state['url']}...")
    launch_mpv(state["url"], state["mode"])
    print(f"✅ mpv lancé (PID: {state['mpv_pid']})")
    
    # Démarrer les threads de polling
    stats_thread = threading.Thread(target=mpv_poll_stats, daemon=True)
    stats_thread.start()
    
    chat_thread = threading.Thread(target=fetch_chat, daemon=True)
    chat_thread.start()
    
    # Démarrer le serveur web
    print(f"🌐 Dashboard: http://localhost:{port}")
    print(f"   Ctrl+C pour quitter")
    
    signal.signal(signal.SIGINT, lambda s, f: (cleanup(), sys.exit(0)))
    signal.signal(signal.SIGTERM, lambda s, f: (cleanup(), sys.exit(0)))
    
    try:
        app.run(host="127.0.0.1", port=port, debug=False)
    except KeyboardInterrupt:
        pass
    finally:
        cleanup()

if __name__ == "__main__":
    main()
