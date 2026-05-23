package main
import (
	"encoding/json"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"strings"
	"syscall"
	"time"
)

// dashboardHTML is embedded at build time from templates/index.html
var dashboardHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>YouTube Live Ultra</title><style>:root{--bg:#0a0a0f;--surf:#14141f;--bord:#1e1e30;--txt:#c8c8d4;--muted:#6b6b80;--green:#22c55e;--warn:#f59e0b;--red:#ef4444;--blue:#3b82f6}.stat .value{font-size:19px;font-weight:700}.stat .green{color:var(--green)}.stat .yellow{color:var(--warn)}.stat .red{color:var(--red)}body{font-family:-apple-system,sans-serif;background:var(--bg);color:var(--txt);margin:0;padding:20px}h1{font-size:18px}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}.stat{background:var(--surf);border:1px solid var(--bord);border-radius:6px;padding:12px}.stat .label{font-size:10px;color:var(--muted)}</style></head><body><h1>🎬 YouTube Live Ultra</h1><div class="stats" id="stats"><div class="stat"><div class="label">Latence</div><div class="value green" id="latency">--</div></div><div class="stat"><div class="label">Buffer</div><div class="value" id="buffer">--</div></div><div class="stat"><div class="label">Resolution</div><div class="value" id="res">--</div></div><div class="stat"><div class="label">FPS</div><div class="value" id="fps">--</div></div><div class="stat"><div class="label">Drops</div><div class="value" id="drops">--</div></div><div class="stat"><div class="label">Codec</div><div class="value" id="codec">--</div></div></div><script>setInterval(async()=>{try{let r=await fetch('/api/stats');let s=await r.json();document.getElementById('latency').textContent=s.cache_duration?(s.cache_duration+2).toFixed(1)+'s':'--';document.getElementById('buffer').textContent=s.cache_duration?s.cache_duration.toFixed(1)+'s':'--';document.getElementById('res').textContent=s.resolution||'--';document.getElementById('fps').textContent=s.fps?s.fps.toFixed(1):'--';document.getElementById('drops').textContent=s.dropped_frames||'0';document.getElementById('codec').textContent=s.video_codec||'--'}catch(e){}},500)</script></body></html>`

const version = "1.0.0-go"

// ─── MAIN ───────────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) < 2 {
		fmt.Printf("ylu v%s (%s/%s)\n", version, runtime.GOOS, runtime.GOARCH)
		fmt.Println("\nUsage: ylu <command> [args]")
		fmt.Println("\nCommands:")
		fmt.Println("  watch <URL>         Watch a live stream")
		fmt.Println("  dashboard <URL>     Start web dashboard")
		fmt.Println("  version             Show version")
		fmt.Println("\nFlags:")
		fmt.Println("  --mode     standard|ultra|direct|resilient")
		fmt.Println("  --port     Dashboard port (default 9191)")
		fmt.Println("  --dry-run  Test without launching")
		fmt.Println("  --sandbox  Run mpv in sandbox")
		fmt.Println("  --verbose  Verbose output")
		os.Exit(0)
	}

	switch os.Args[1] {
	case "watch":
		cmdWatch()
	case "dashboard":
		cmdDashboard()
	case "version":
		fmt.Printf("ylu v%s (%s/%s)\n", version, runtime.GOOS, runtime.GOARCH)
		fmt.Printf("Go: %s\n", runtime.Version())
	default:
		fmt.Fprintf(os.Stderr, "Unknown command: %s\n", os.Args[1])
		os.Exit(1)
	}
}

// ─── WATCH ──────────────────────────────────────────────────────────────────

func cmdWatch() {
	flags := flag.NewFlagSet("watch", flag.ExitOnError)
	mode := flags.String("mode", "standard", "standard|ultra|direct|resilient")
	dryRun := flags.Bool("dry-run", false, "Test without launching")
	sandbox := flags.Bool("sandbox", false, "Run mpv in sandbox")
	verbose := flags.Bool("verbose", false, "Verbose output")
	flags.Parse(os.Args[2:])

	if flags.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "Usage: ylu watch <URL>")
		os.Exit(1)
	}
	url := flags.Arg(0)

	// Detect hardware decode args
	hwdec := detectHWDec()
	mpvArgs := []string{
		"--profile=low-latency", "--keep-open=no", "--force-window=yes",
		"--video-latency-hacks=yes", "--framedrop=vo", "--video-sync=audio",
		"--vd-lavc-threads=4", "--audio-buffer=0.2",
	}
	mpvArgs = append(mpvArgs, hwdec...)

	switch *mode {
	case "ultra", "direct":
		mpvArgs = append(mpvArgs, "--cache=no", "--demuxer-max-bytes=500K",
			"--framedrop=vo+decoder", "--video-sync=display-resample",
			"--vd-lavc-threads=6", "--audio-buffer=0.1", "--osc=no", "--cache-secs=0")
	case "standard", "resilient":
		mpvArgs = append(mpvArgs, "--cache=yes", "--demuxer-max-bytes=2M", "--demuxer-readahead-secs=0.2")
	}

	if *dryRun {
		fmt.Printf("🎬 DRY RUN — %s mode\n   URL: %s\n   GPU: %s\n", *mode, url, strings.Join(hwdec, " "))
		return
	}

	if *verbose {
		fmt.Printf("🎬 YouTube Live Ultra — %s mode\n   URL: %s\n   OS:  %s/%s\n", *mode, url, runtime.GOOS, runtime.GOARCH)
	}

	// Triple fallback
	if *mode == "resilient" {
		launchResilient(url, mpvArgs, *sandbox)
	} else if *mode == "direct" {
		launchYtdlpPipe(url, mpvArgs)
	} else {
		if err := launchStreamlink(url, mpvArgs, *sandbox, *verbose); err != nil {
			if *verbose { fmt.Printf("   streamlink: %v\n", err) }
			if err := launchYtdlpPipe(url, mpvArgs); err != nil {
				if *verbose { fmt.Printf("   yt-dlp: %v\n", err) }
				if err := launchMpvYtdl(url, mpvArgs, *sandbox); err != nil {
					fmt.Fprintln(os.Stderr, "   ❌ All strategies failed")
					os.Exit(1)
				}
			}
		}
	}
}

// ─── BACKENDS ───────────────────────────────────────────────────────────────

func launchStreamlink(url string, mpvArgs []string, sandbox, verbose bool) error {
	playerArgs := strings.Join(mpvArgs, " ")
	cmd := exec.Command("streamlink",
		"--loglevel", "info", "--hls-live-edge", "2",
		"--stream-segment-threads", "3", "--ringbuffer-size", "64M",
		"--retry-max", "5", "--retry-streams", "3",
		url, "best", "--player", "mpv", "--player-args", playerArgs, "--player-no-close")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	return cmd.Run()
}

func launchYtdlpPipe(url string, mpvArgs []string) error {
	ytdlp := exec.Command("yt-dlp", "-o", "-", "--format", "bestvideo+bestaudio/best",
		"--extractor-args", "youtube:player_client=android,web", url)
	ytdlp.Stderr = nil
	stdout, err := ytdlp.StdoutPipe()
	if err != nil { return err }
	if err := ytdlp.Start(); err != nil { return err }
	defer func() { ytdlp.Wait() }() // Évite le zombie si mpv meurt

	mpv := exec.Command("mpv", append(mpvArgs, "-")...)
	mpv.Stdin = stdout
	mpv.Stdout = os.Stdout
	mpv.Stderr = os.Stderr
	return mpv.Run()
}

func launchMpvYtdl(url string, mpvArgs []string, sandbox bool) error {
	args := append([]string{"mpv", "--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best"}, mpvArgs...)
	args = append(args, url)
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	return cmd.Run()
}

// ─── RESILIENT ──────────────────────────────────────────────────────────────

func launchResilient(url string, mpvArgs []string, sandbox bool) {
	ipc := fmt.Sprintf("/tmp/mpv-ylu-%d", os.Getpid())
	args := append([]string{
		"mpv", "--input-ipc-server=" + ipc, "--ytdl=yes",
		"--ytdl-format=bestvideo+bestaudio/best",
	}, mpvArgs...)
	args = append(args, url)

	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	cmd.Start()

	fmt.Printf("   Watchdog actif (IPC: %s)\n", ipc)
	watchdog(cmd.Process.Pid, ipc, url, mpvArgs, sandbox)
}

func watchdog(pid int, ipc, url string, mpvArgs []string, sandbox bool) {
	var lastPos *float64
	frozen := 0

	for {
		time.Sleep(3 * time.Second)

		// Check process alive
		var wstatus syscall.WaitStatus
		_, err := syscall.Wait4(pid, &wstatus, syscall.WNOHANG, nil)
		if err != nil || wstatus.Exited() {
			code := wstatus.ExitStatus()
			if code == 0 { return }
			fmt.Printf("   ⚠ mpv crashed (exit %d) — restarting...\n", code)
			launchStreamlink(url, mpvArgs, sandbox, false)
			return
		}

		// IPC health check
		conn, err := net.DialTimeout("unix", ipc, 500*time.Millisecond)
		if err != nil { continue }
		fmt.Fprintf(conn, `{"command":["get_property","time-pos"]}`+"\n")
		var buf [4096]byte
		n, _ := conn.Read(buf[:])
		conn.Close()

		var resp struct {
			Data *float64 `json:"data"`
		}
		if json.Unmarshal(buf[:n], &resp) == nil && resp.Data != nil {
			if lastPos != nil && *resp.Data == *lastPos {
				frozen++
				if frozen >= 3 {
					fmt.Printf("   ❌ mpv frozen — killing & restarting...\n")
					syscall.Kill(pid, syscall.SIGTERM)
					time.Sleep(time.Second)
					launchStreamlink(url, mpvArgs, sandbox, false)
					return
				}
			} else {
				frozen = 0
			}
			lastPos = resp.Data
		}
	}
}

// ─── DASHBOARD ──────────────────────────────────────────────────────────────

func cmdDashboard() {
	flags := flag.NewFlagSet("dashboard", flag.ExitOnError)
	port := flags.Int("port", 9191, "HTTP port")
	mode := flags.String("mode", "standard", "standard|ultra")
	flags.Parse(os.Args[2:])

	if flags.NArg() < 1 {
		fmt.Fprintln(os.Stderr, "Usage: ylu dashboard <URL>")
		os.Exit(1)
	}
	url := flags.Arg(0)

	// Launch mpv in background
	ipc := fmt.Sprintf("/tmp/mpv-dash-%d", os.Getpid())
	args := []string{
		"mpv", "--input-ipc-server=" + ipc,
		"--profile=low-latency", "--cache=yes", "--demuxer-max-bytes=2M",
		"--video-latency-hacks=yes", "--framedrop=vo", "--video-sync=audio",
		"--vd-lavc-threads=4", "--audio-buffer=0.2",
		"--keep-open=no", "--force-window=yes",
		"--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best",
	}
	if *mode == "ultra" {
		args = append(args, "--cache=no", "--demuxer-max-bytes=500K", "--framedrop=vo+decoder")
	}
	hwdec := detectHWDec()
	args = append(args, hwdec...)
	args = append(args, url)

	go func() {
		cmd := exec.Command(args[0], args[1:]...)
		cmd.Run()
	}()

	// HTTP server
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Write([]byte(dashboardHTML))
	})

	http.HandleFunc("/api/stats", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		stats := getMPVStats(ipc)
		json.NewEncoder(w).Encode(stats)
	})

	http.HandleFunc("/cmd/pause", func(w http.ResponseWriter, r *http.Request) {
		sendMPVCmd(ipc, "cycle", "pause")
	})

	http.HandleFunc("/cmd/stop", func(w http.ResponseWriter, r *http.Request) {
		os.Exit(0)
	})

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	fmt.Printf("🌐 Dashboard: http://%s\n", addr)
	fmt.Printf("🎬 mpv launched\n")

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)
	go func() { <-sig; os.Exit(0) }()

	http.ListenAndServe(addr, nil)
}

// ─── MPV IPC HELPERS ────────────────────────────────────────────────────────

func sendMPVCmd(ipc string, cmd ...string) error {
	conn, err := net.Dial("unix", ipc)
	if err != nil { return err }
	defer conn.Close()
	req, _ := json.Marshal(map[string]interface{}{"command": cmd})
	fmt.Fprintf(conn, "%s\n", req)
	return nil
}

func getMPVStats(ipc string) map[string]interface{} {
	stats := map[string]interface{}{}
	props := map[string]string{
		"resolution": "video-params", "video_codec": "video-params/codec",
		"fps": "estimated-vf-fps", "dropped_frames": "vo-drop-frame-count",
		"cache_duration": "demuxer-cache-duration", "hwdec": "hwdec-current",
		"bitrate": "video-bitrate", "paused": "pause", "time_pos": "time-pos",
	}
	for key, prop := range props {
		val := getMPVProp(ipc, prop)
		if val != nil { stats[key] = val }
	}
	return stats
}

func getMPVProp(ipc, prop string) interface{} {
	conn, err := net.DialTimeout("unix", ipc, 300*time.Millisecond)
	if err != nil { return nil }
	defer conn.Close()

	fmt.Fprintf(conn, `{"command":["get_property","%s"]}`, prop)
	fmt.Fprintf(conn, "\n")
	var buf [4096]byte
	n, _ := conn.Read(buf[:])
	
	var resp struct{ Data interface{} `json:"data"` }
	if json.Unmarshal(buf[:n], &resp) == nil {
		return resp.Data
	}
	return nil
}

// ─── SANDBOX ────────────────────────────────────────────────────────────────

func sandboxWrap(cmd *exec.Cmd) *exec.Cmd {
	switch runtime.GOOS {
	case "darwin":
		// sandbox-exec
		profile := `(version 1)(allow default)(deny file-write*)(allow file-write* (subpath "/tmp"))(allow network*)(allow sysctl-read)(allow mach-lookup)`
		cmd.Args = append([]string{"sandbox-exec", "-p", profile, "--"}, cmd.Args...)
		cmd.Path, _ = exec.LookPath("sandbox-exec")
	case "linux":
		if _, err := exec.LookPath("firejail"); err == nil {
			cmd.Args = append([]string{"firejail", "--quiet", "--net=none", "--noprofile",
				"--caps.drop=all", "--nonewprivs", "--seccomp", "--tmpfs=/tmp"}, cmd.Args...)
			cmd.Path, _ = exec.LookPath("firejail")
		} else if _, err := exec.LookPath("bwrap"); err == nil {
			cmd.Args = append([]string{"bwrap", "--ro-bind", "/usr", "/usr",
				"--dev", "/dev", "--tmpfs", "/tmp", "--unshare-all", "--share-net"}, cmd.Args...)
			cmd.Path, _ = exec.LookPath("bwrap")
		} else {
			fmt.Fprintln(os.Stderr, "⚠ --sandbox demandé mais ni firejail ni bwrap trouvé. Installe l'un des deux.")
		}
	}
	return cmd
}

// ─── HW DECODE ──────────────────────────────────────────────────────────────

func detectHWDec() []string {
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("mpv", "--gpu-api=help").Output(); err == nil {
			if strings.Contains(string(out), "metal") {
				return []string{"--hwdec=videotoolbox", "--vo=gpu-next", "--gpu-api=metal", "--gpu-context=cocoa"}
			} else if strings.Contains(string(out), "vulkan") {
				return []string{"--hwdec=videotoolbox", "--vo=gpu-next", "--gpu-api=vulkan", "--gpu-context=macvk"}
			}
		}
		return []string{"--hwdec=videotoolbox", "--vo=gpu-next"}
	}
	if runtime.GOOS == "linux" {
		if _, err := os.Stat("/dev/dri/renderD128"); err == nil {
			return []string{"--hwdec=vaapi", "--vo=gpu-next"}
		}
		return []string{"--hwdec=auto-safe", "--vo=gpu-next"}
	}
	return []string{"--hwdec=auto-safe", "--vo=gpu-next"}
}
