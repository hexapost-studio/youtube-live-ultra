#!/usr/bin/env python3
"""
youtube-live-ultra — TUI v2 (stdlib curses, zero deps).
Remplace watch-tui.sh (dialog 1994) par une interface curses native Python.
Stats mpv IPC temps réel + contrôles clavier.

Usage: python3 dashboard/tui.py <URL_YOUTUBE_LIVE> [--mode ultra|standard]
"""
import sys, os, json, socket, time, signal, subprocess, curses, threading

URL, MODE, IPC, MPV_PID = "", "standard", "", None
running = True
stats = {"res": "?", "fps": 0, "drops": 0, "cache": 0, "codec": "?", "hwdec": "?", "br": 0, "paused": False, "time_pos": 0}

def mpv_get(prop):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.2)
        s.connect(IPC)
        s.send((json.dumps({"command": ["get_property", prop]}) + "\n").encode())
        r = b""
        while True:
            c = s.recv(4096)
            if not c: break
            r += c
            if b"\n" in r: break
        s.close()
        d = json.loads(r.decode().strip())
        return d.get("data")
    except: return None

def poll_stats():
    global stats
    while running:
        try:
            vp = mpv_get("video-params")
            if vp: stats["res"] = f"{vp.get('w','?')}x{vp.get('h','?')}"; stats["codec"] = vp.get("codec","?")
            stats["fps"] = mpv_get("estimated-vf-fps") or 0
            stats["drops"] = mpv_get("vo-drop-frame-count") or 0
            stats["cache"] = mpv_get("demuxer-cache-duration") or 0
            stats["hwdec"] = mpv_get("hwdec-current") or "?"
            stats["br"] = mpv_get("video-bitrate") or 0
            stats["paused"] = mpv_get("pause") or False
            stats["time_pos"] = mpv_get("time-pos") or 0
        except: pass
        time.sleep(0.5)

def launch_mpv():
    global IPC, MPV_PID
    IPC = f"/tmp/mpv-tui-{os.getpid()}"
    args = ["mpv", f"--input-ipc-server={IPC}", "--profile=low-latency",
            "--cache=yes", "--demuxer-max-bytes=2M", "--video-latency-hacks=yes",
            "--framedrop=vo", "--video-sync=audio", "--vd-lavc-threads=4",
            "--audio-buffer=0.2", "--keep-open=no", "--force-window=yes",
            "--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best",
            "--hwdec=videotoolbox", "--vo=gpu-next"]
    if MODE == "ultra":
        args.extend(["--cache=no", "--demuxer-max-bytes=500K", "--framedrop=vo+decoder"])
    args.append(URL)
    MPV_PID = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).pid
    for _ in range(30):
        if os.path.exists(IPC): break
        time.sleep(0.2)

def cleanup():
    global running
    running = False
    if MPV_PID:
        try: os.kill(MPV_PID, signal.SIGTERM)
        except: pass
    if IPC and os.path.exists(IPC):
        try: os.unlink(IPC)
        except: pass

def fmt_time(t):
    if not t: return "--:--:--"
    t = int(t)
    return f"{t//3600:02d}:{(t%3600)//60:02d}:{t%60:02d}"

def tui_main(stdscr):
    curses.curs_set(0)
    curses.start_color()
    curses.use_default_colors()
    curses.init_pair(1, curses.COLOR_GREEN, -1)
    curses.init_pair(2, curses.COLOR_YELLOW, -1)
    curses.init_pair(3, curses.COLOR_RED, -1)
    curses.init_pair(4, curses.COLOR_CYAN, -1)
    curses.init_pair(5, curses.COLOR_WHITE, -1)
    stdscr.nodelay(True)

    while running:
        stdscr.clear()
        h, w = stdscr.getmaxyx()

        # Header
        header = f" YouTube Live Ultra — TUI | {MODE} | q=quit p=pause r=refresh "
        stdscr.addstr(0, 0, header[:w-1], curses.A_REVERSE | curses.color_pair(5))

        # Stats
        latency = f"{stats['cache'] + 2:.1f}s" if stats['cache'] else "--"
        br = f"{stats['br']/1000:.1f} Mbps" if stats['br'] else "--"
        fps = f"{stats['fps']:.1f}" if stats['fps'] else "--"
        cache = f"{stats['cache']:.1f}s" if stats['cache'] else "--"
        status = "⏸ PAUSED" if stats['paused'] else "▶ PLAYING"
        elapsed = fmt_time(stats['time_pos'])

        rows = [
            ("Latence estimée", latency, 1 if stats.get('cache', 0) < 8 else (2 if stats.get('cache', 0) < 20 else 3)),
            ("Buffer", cache, 1 if stats.get('cache', 0) < 8 else (2 if stats.get('cache', 0) < 20 else 3)),
            ("Résolution", stats['res'], 4),
            ("FPS", fps, 4),
            ("Drops", str(stats['drops']), 1 if stats['drops'] == 0 else (2 if stats['drops'] < 10 else 3)),
            ("Codec", stats['codec'], 4),
            ("Décodeur", stats['hwdec'], 4),
            ("Débit", br, 4),
            ("Temps", elapsed, 4),
            ("Status", status, 1 if not stats['paused'] else 2),
        ]

        for i, (label, value, color) in enumerate(rows):
            if i + 2 >= h - 2: break
            stdscr.addstr(i + 2, 2, f"{label:<18}", curses.A_DIM)
            stdscr.addstr(i + 2, 22, value, curses.color_pair(color) | curses.A_BOLD)

        # Footer
        footer = " q:quit  p:pause  r:refresh  →:seek+10s  ←:seek-10s "
        stdscr.addstr(h - 1, 0, footer[:w-1], curses.A_REVERSE)

        stdscr.refresh()

        # Handle input
        try:
            key = stdscr.getch()
            if key == ord('q'):
                break
            elif key == ord('p'):
                subprocess.run(["bash", "-c", f"echo '{{\"command\":[\"cycle\",\"pause\"]}}' | socat - UNIX-CONNECT:{IPC}"], capture_output=True)
            elif key == ord('r'):
                pass  # auto-refresh
            elif key == curses.KEY_RIGHT:
                subprocess.run(["bash", "-c", f"echo '{{\"command\":[\"seek\",\"10\",\"relative\"]}}' | socat - UNIX-CONNECT:{IPC}"], capture_output=True)
            elif key == curses.KEY_LEFT:
                subprocess.run(["bash", "-c", f"echo '{{\"command\":[\"seek\",\"-10\",\"relative\"]}}' | socat - UNIX-CONNECT:{IPC}"], capture_output=True)
        except: pass

        if not running: break
        time.sleep(1)

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: dashboard/tui.py <URL_YOUTUBE_LIVE> [--mode MODE]")
        sys.exit(1)
    URL = sys.argv[1]
    for i, a in enumerate(sys.argv[2:], 2):
        if a == "--mode" and i+1 < len(sys.argv):
            MODE = sys.argv[i+1]

    signal.signal(signal.SIGINT, lambda s,f: (cleanup(), sys.exit(0)))
    launch_mpv()
    threading.Thread(target=poll_stats, daemon=True).start()
    curses.wrapper(tui_main)
    cleanup()
