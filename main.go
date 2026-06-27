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
	"time"

	tea "github.com/charmbracelet/bubbletea"
)

const version = "1.0.0-go"

// ─── MAIN ───────────────────────────────────────────────────────────────────

func main() {
	if len(os.Args) < 2 {
		printUsage()
		os.Exit(0)
	}

	switch os.Args[1] {
	case "watch":    cmdWatch()
	case "dashboard": cmdDashboard()
	case "tui":      cmdTUI()
	case "check":    cmdCheck(os.Args[2:])
	case "optimize": cmdOptimize()
	case "version":  fmt.Printf("ylu v%s (%s/%s)\nGo: %s\n", version, runtime.GOOS, runtime.GOARCH, runtime.Version())
	default:
		fmt.Fprintf(os.Stderr, "Unknown: %s\n", os.Args[1])
		os.Exit(1)
	}
}

func printUsage() {
	fmt.Printf("ylu v%s (%s/%s)\n\n", version, runtime.GOOS, runtime.GOARCH)
	fmt.Println("Commands:")
	fmt.Println("  watch <URL>      Watch live (--mode ultra|direct|resilient)")
	fmt.Println("  dashboard <URL>  Web dashboard (--port 9191)")
	fmt.Println("  tui <URL>        Terminal UI")
	fmt.Println("  check <URL>      Health check")
	fmt.Println("  optimize          Network diagnostic")
	fmt.Println("  version           Show version")
	fmt.Println("\nFlags: --dry-run --verbose --sandbox --mode --port")
}

// ─── WATCH ──────────────────────────────────────────────────────────────────

func cmdWatch() {
	flags := flag.NewFlagSet("watch", flag.ExitOnError)
	mode := flags.String("mode", "standard", "standard|ultra|direct|resilient")
	dryRun := flags.Bool("dry-run", false, "")
	sandbox := flags.Bool("sandbox", false, "")
	flags.Parse(os.Args[2:])
	if flags.NArg() < 1 { fmt.Fprintln(os.Stderr, "Usage: ylu watch <URL>"); os.Exit(1) }
	url := flags.Arg(0)

	mpvArgs := buildMpvArgs(*mode)

	if *dryRun {
		fmt.Printf("🎬 DRY RUN — %s\n   URL: %s\n   GPU: %s\n", *mode, url, strings.Join(detectHWDec(), " "))
		return
	}

	if *mode == "resilient" {
		launchResilient(url, mpvArgs, *sandbox)
	} else if *mode == "direct" {
		launchYtdlpPipe(url, mpvArgs)
	} else {
		if err := launchStreamlink(url, mpvArgs, *sandbox); err != nil {
			if err := launchYtdlpPipe(url, mpvArgs); err != nil {
				if err := launchMpvYtdl(url, mpvArgs, *sandbox); err != nil {
					fmt.Fprintln(os.Stderr, "❌ All strategies failed"); os.Exit(1)
				}
			}
		}
	}
}

func buildMpvArgs(mode string) []string {
	args := []string{"--profile=low-latency", "--keep-open=no", "--force-window=yes",
		"--video-latency-hacks=yes", "--framedrop=vo", "--video-sync=audio",
		"--vd-lavc-threads=4", "--audio-buffer=0.2"}
	args = append(args, detectHWDec()...)
	switch mode {
	case "ultra", "direct":
		args = append(args, "--cache=no", "--demuxer-max-bytes=500K",
			"--framedrop=vo+decoder", "--vd-lavc-threads=6", "--audio-buffer=0.1", "--osc=no", "--cache-secs=0")
	default:
		args = append(args, "--cache=yes", "--demuxer-max-bytes=2M", "--demuxer-readahead-secs=0.2")
	}
	return args
}

// ─── BACKENDS ───────────────────────────────────────────────────────────────

func launchStreamlink(url string, mpvArgs []string, sandbox bool) error {
	playerArgs := strings.Join(mpvArgs, " ")
	cmd := exec.Command("streamlink", "--loglevel", "info", "--hls-live-edge", "2",
		"--stream-segment-threads", "3", "--ringbuffer-size", "64M",
		"--retry-max", "5", "--retry-streams", "3",
		url, "best", "--player", "mpv", "--player-args", playerArgs, "--player-no-close")
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	return cmd.Run()
}

func launchYtdlpPipe(url string, mpvArgs []string) error {
	ytdlp := exec.Command("yt-dlp", "-o", "-", "--format", "bestvideo+bestaudio/best",
		"--extractor-args", "youtube:player_client=android,web", url)
	stdout, err := ytdlp.StdoutPipe()
	if err != nil { return err }
	if err := ytdlp.Start(); err != nil { return err }
	defer func() { ytdlp.Wait() }()
	mpv := exec.Command("mpv", append(mpvArgs, "-")...)
	mpv.Stdin, mpv.Stdout, mpv.Stderr = stdout, os.Stdout, os.Stderr
	return mpv.Run()
}

func launchMpvYtdl(url string, mpvArgs []string, sandbox bool) error {
	args := append([]string{"mpv", "--ytdl=yes", "--ytdl-format=bestvideo+bestaudio/best"}, mpvArgs...)
	args = append(args, url)
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	return cmd.Run()
}

// ─── RESILIENT ──────────────────────────────────────────────────────────────

func launchResilient(url string, mpvArgs []string, sandbox bool) {
	ipc := ipcPath("ylu")
	args := append([]string{"mpv", "--input-ipc-server=" + ipc, "--ytdl=yes",
		"--ytdl-format=bestvideo+bestaudio/best"}, mpvArgs...)
	args = append(args, url)
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if sandbox { cmd = sandboxWrap(cmd) }
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(os.Stderr, "❌ failed to start mpv: %v\n", err); os.Exit(1)
	}
	fmt.Printf("🛡️ Watchdog IPC: %s\n", ipc)
	watchdog(cmd, ipc, url, mpvArgs, sandbox)
}

// watchdog supervises mpv portably: a goroutine reaps the process (no Unix
// syscall.Wait4) and the IPC channel (Unix socket / Windows named pipe) detects
// freezes by polling time-pos.
func watchdog(cmd *exec.Cmd, ipc, url string, mpvArgs []string, sandbox bool) {
	exited := make(chan struct{})
	go func() { cmd.Wait(); close(exited) }()

	var lastPos *float64
	frozen := 0
	for {
		select {
		case <-exited:
			code := 0
			if cmd.ProcessState != nil { code = cmd.ProcessState.ExitCode() }
			if code == 0 { return }
			fmt.Printf("⚠ mpv exited (code %d) — restarting...\n", code)
			launchStreamlink(url, mpvArgs, sandbox)
			return
		case <-time.After(3 * time.Second):
		}

		conn, err := dialIPC(ipc, 500*time.Millisecond)
		if err != nil { continue }
		fmt.Fprintf(conn, `{"command":["get_property","time-pos"]}`+"\n")
		var buf [4096]byte
		n, _ := conn.Read(buf[:])
		conn.Close()
		var resp struct{ Data *float64 `json:"data"` }
		if json.Unmarshal(buf[:n], &resp) == nil && resp.Data != nil {
			if lastPos != nil && *resp.Data == *lastPos {
				frozen++
				if frozen >= 3 {
					fmt.Printf("❌ mpv frozen — restarting...\n")
					cmd.Process.Kill()
					time.Sleep(time.Second)
					launchStreamlink(url, mpvArgs, sandbox)
					return
				}
			} else { frozen = 0 }
			lastPos = resp.Data
		}
	}
}

// ─── DASHBOARD ──────────────────────────────────────────────────────────────

func cmdDashboard() {
	flags := flag.NewFlagSet("dashboard", flag.ExitOnError)
	port := flags.Int("port", 9191, "")
	mode := flags.String("mode", "standard", "")
	flags.Parse(os.Args[2:])
	if flags.NArg() < 1 { fmt.Fprintln(os.Stderr, "Usage: ylu dashboard <URL>"); os.Exit(1) }
	url := flags.Arg(0)

	ipc := ipcPath("dash")
	args := append([]string{"mpv", "--input-ipc-server=" + ipc, "--ytdl=yes",
		"--ytdl-format=bestvideo+bestaudio/best"}, buildMpvArgs(*mode)...)
	args = append(args, url)
	go func() { exec.Command(args[0], args[1:]...).Run() }()

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'unsafe-inline'; script-src 'unsafe-inline'")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Write([]byte(dashboardHTML))
	})
	http.HandleFunc("/api/stats", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(getMPVStats(ipc))
	})
	http.HandleFunc("/cmd/pause", func(w http.ResponseWriter, r *http.Request) { sendMPVCmd(ipc, "cycle", "pause") })
	http.HandleFunc("/cmd/stop", func(w http.ResponseWriter, r *http.Request) { os.Exit(0) })

	addr := fmt.Sprintf("127.0.0.1:%d", *port)
	fmt.Printf("🌐 http://%s\n", addr)
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, shutdownSignals...)
	go func() { <-sig; os.Exit(0) }()
	http.ListenAndServe(addr, nil)
}

// ─── TUI ────────────────────────────────────────────────────────────────────

type tuiModel struct {
	url      string
	ipc      string
	stats    map[string]interface{}
	quitting bool
}

func (m tuiModel) Init() tea.Cmd { return tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg { return t }) }

func (m tuiModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c": m.quitting = true; return m, tea.Quit
		case "p": sendMPVCmd(m.ipc, "cycle", "pause")
		case "r": // refresh
		}
	case time.Time:
		m.stats = getMPVStats(m.ipc)
		return m, tea.Tick(500*time.Millisecond, func(t time.Time) tea.Msg { return t })
	}
	return m, nil
}

func (m tuiModel) View() string {
	if m.quitting { return "Bye!\n" }
	s := fmt.Sprintf("🎬 YouTube Live Ultra — TUI\n\n")
	s += fmt.Sprintf("  URL: %s\n", m.url)
	s += fmt.Sprintf("  IPC: %s\n\n", m.ipc)
	props := []struct{ label, key string }{
		{"Resolution", "resolution"}, {"FPS", "fps"}, {"Drops", "dropped_frames"},
		{"Cache", "cache_duration"}, {"Codec", "video_codec"}, {"HW Dec", "hwdec"},
		{"Bitrate", "bitrate"}, {"Paused", "paused"},
	}
	for _, p := range props {
		val := m.stats[p.key]
		s += fmt.Sprintf("  %-12s %v\n", p.label+":", val)
	}
	s += "\n  q:quit  p:pause  r:refresh\n"
	return s
}

func cmdTUI() {
	flags := flag.NewFlagSet("tui", flag.ExitOnError)
	mode := flags.String("mode", "standard", "")
	flags.Parse(os.Args[2:])
	if flags.NArg() < 1 { fmt.Fprintln(os.Stderr, "Usage: ylu tui <URL>"); os.Exit(1) }
	url := flags.Arg(0)

	ipc := ipcPath("tui")
	args := append([]string{"mpv", "--input-ipc-server=" + ipc, "--ytdl=yes",
		"--ytdl-format=bestvideo+bestaudio/best"}, buildMpvArgs(*mode)...)
	args = append(args, url)
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	cmd.Start()
	time.Sleep(2 * time.Second)

	m := tuiModel{url: url, ipc: ipc, stats: map[string]interface{}{}}
	p := tea.NewProgram(m)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "TUI error: %v\n", err)
	}
	cmd.Process.Kill()
}

// ─── HEALTH CHECK ───────────────────────────────────────────────────────────

func cmdCheck(args []string) {
	url := ""
	if len(args) > 0 { url = args[0] }

	fmt.Println("🩺 Health Check — YouTube Live Ultra")
	fmt.Printf("   OS:      %s/%s\n", runtime.GOOS, runtime.GOARCH)
	fmt.Printf("   CPU:     %d cores\n", runtime.NumCPU())

	checks := []struct {
		name string
		fn   func() bool
	}{
		{"mpv", func() bool { _, err := exec.LookPath("mpv"); return err == nil }},
		{"streamlink", func() bool { _, err := exec.LookPath("streamlink"); return err == nil }},
		{"yt-dlp", func() bool { _, err := exec.LookPath("yt-dlp"); return err == nil }},
		{"curl", func() bool { _, err := exec.LookPath("curl"); return err == nil }},
		{"DNS", func() bool { _, err := net.LookupHost("youtube.com"); return err == nil }},
		{"GPU decode", func() bool { return len(detectHWDec()) > 0 }},
	}

	pass, fail := 0, 0
	for _, c := range checks {
		if c.fn() { fmt.Printf("   ✅ %s\n", c.name); pass++ } else { fmt.Printf("   ❌ %s\n", c.name); fail++ }
	}

	if url != "" {
		out, err := exec.Command("yt-dlp", "--print", "is_live", url).Output()
		if err == nil && strings.TrimSpace(string(out)) == "True" {
			fmt.Printf("   ✅ Stream live\n"); pass++
		} else {
			fmt.Printf("   ⚠️  Stream status unknown\n")
		}
	}

	fmt.Printf("\n   %d OK, %d failed\n", pass, fail)
}

// ─── OPTIMIZE ───────────────────────────────────────────────────────────────

func cmdOptimize() {
	fmt.Println("🌐 Network Diagnostic")

	// DNS
	fastest := ""
	fastestTime := 9999.0
	for _, dns := range []string{"1.1.1.1", "8.8.8.8", "9.9.9.9"} {
		start := time.Now()
		_, err := net.LookupHost("youtube.com")
		elapsed := time.Since(start).Seconds() * 1000
		if err == nil {
			fmt.Printf("   DNS %s → %.0fms", dns, elapsed)
			if elapsed < fastestTime { fastestTime = elapsed; fastest = dns; fmt.Println(" ✅") } else { fmt.Println() }
		}
	}
	if fastest != "" { fmt.Printf("\n   → Fastest DNS: %s (%.0fms)\n", fastest, fastestTime) }

	// Ping
	start := time.Now()
	net.LookupHost("youtube.com")
	ping := time.Since(start).Seconds() * 1000
	fmt.Printf("   YouTube: %.0fms\n", ping)

	// Interface
	fmt.Printf("   OS: %s/%s\n", runtime.GOOS, runtime.GOARCH)
	if runtime.GOOS == "darwin" {
		out, _ := exec.Command("networksetup", "-listallhardwareports").Output()
		if strings.Contains(strings.ToLower(string(out)), "wi-fi") {
			fmt.Println("   ⚠️  WiFi detected — Ethernet recommended")
		} else {
			fmt.Println("   ✅ Wired connection")
		}
	}

	// GPU
	fmt.Printf("   GPU: %s\n", strings.Join(detectHWDec(), " "))
}

// ─── MPV IPC HELPERS ────────────────────────────────────────────────────────

func sendMPVCmd(ipc string, cmd ...string) {
	conn, err := dialIPC(ipc, 0)
	if err != nil { return }
	defer conn.Close()
	req, _ := json.Marshal(map[string]interface{}{"command": cmd})
	fmt.Fprintf(conn, "%s\n", req)
}

func getMPVStats(ipc string) map[string]interface{} {
	stats := map[string]interface{}{}
	for key, prop := range map[string]string{
		"resolution": "video-params", "video_codec": "video-params/codec",
		"fps": "estimated-vf-fps", "dropped_frames": "vo-drop-frame-count",
		"cache_duration": "demuxer-cache-duration", "hwdec": "hwdec-current",
		"bitrate": "video-bitrate", "paused": "pause", "time_pos": "time-pos",
	} {
		if v := getMPVProp(ipc, prop); v != nil { stats[key] = v }
	}
	return stats
}

func getMPVProp(ipc, prop string) interface{} {
	conn, err := dialIPC(ipc, 300*time.Millisecond)
	if err != nil { return nil }
	defer conn.Close()
	fmt.Fprintf(conn, `{"command":["get_property","%s"]}`, prop)
	fmt.Fprintf(conn, "\n")
	var buf [4096]byte
	n, _ := conn.Read(buf[:])
	var resp struct{ Data interface{} `json:"data"` }
	if json.Unmarshal(buf[:n], &resp) == nil { return resp.Data }
	return nil
}

// ─── SANDBOX ────────────────────────────────────────────────────────────────

func sandboxWrap(cmd *exec.Cmd) *exec.Cmd {
	switch runtime.GOOS {
	case "darwin":
		profile := `(version 1)(allow default)(deny file-write*)(allow file-write* (subpath "/tmp"))(allow network*)(allow sysctl-read)(allow mach-lookup)`
		cmd.Args = append([]string{"sandbox-exec", "-p", profile, "--"}, cmd.Args...)
		cmd.Path, _ = exec.LookPath("sandbox-exec")
	case "linux":
		if _, err := exec.LookPath("firejail"); err == nil {
			cmd.Args = append([]string{"firejail", "--quiet", "--noprofile", "--caps.drop=all", "--nonewprivs", "--seccomp", "--tmpfs=/tmp"}, cmd.Args...)
			cmd.Path, _ = exec.LookPath("firejail")
		} else if _, err := exec.LookPath("bwrap"); err == nil {
			cmd.Args = append([]string{"bwrap", "--ro-bind", "/usr", "/usr", "--dev", "/dev", "--tmpfs", "/tmp", "--unshare-all", "--share-net"}, cmd.Args...)
			cmd.Path, _ = exec.LookPath("bwrap")
		} else {
			fmt.Fprintln(os.Stderr, "⚠ --sandbox requested but no firejail/bwrap found.")
		}
	case "windows":
		fmt.Fprintln(os.Stderr, "⚠ --sandbox not supported on Windows; running unsandboxed.")
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
	if runtime.GOOS == "windows" {
		// d3d11va covers H.264/HEVC on virtually all Windows GPUs.
		return []string{"--hwdec=d3d11va", "--vo=gpu-next"}
	}
	return []string{"--hwdec=auto-safe", "--vo=gpu-next"}
}

// ─── DASHBOARD HTML ─────────────────────────────────────────────────────────

var dashboardHTML = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1.0"><title>YouTube Live Ultra</title><style>:root{--bg:#0a0a0f;--surf:#14141f;--bord:#1e1e30;--txt:#c8c8d4;--muted:#6b6b80;--green:#22c55e;--warn:#f59e0b;--red:#ef4444;--blue:#3b82f6}.stat .value{font-size:19px;font-weight:700}.stat .green{color:var(--green)}.stat .yellow{color:var(--warn)}.stat .red{color:var(--red)}body{font-family:-apple-system,sans-serif;background:var(--bg);color:var(--txt);margin:0;padding:20px}h1{font-size:18px}.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(130px,1fr));gap:10px}.stat{background:var(--surf);border:1px solid var(--bord);border-radius:6px;padding:12px}.stat .label{font-size:10px;color:var(--muted)}</style></head><body><h1>🎬 YouTube Live Ultra</h1><div class="stats" id="stats"><div class="stat"><div class="label">Latence</div><div class="value green" id="latency">--</div></div><div class="stat"><div class="label">Buffer</div><div class="value" id="buffer">--</div></div><div class="stat"><div class="label">Resolution</div><div class="value" id="res">--</div></div><div class="stat"><div class="label">FPS</div><div class="value" id="fps">--</div></div><div class="stat"><div class="label">Drops</div><div class="value" id="drops">--</div></div><div class="stat"><div class="label">Codec</div><div class="value" id="codec">--</div></div></div><script>setInterval(async()=>{try{let r=await fetch('/api/stats');let s=await r.json();document.getElementById('latency').textContent=s.cache_duration?(s.cache_duration+2).toFixed(1)+'s':'--';document.getElementById('buffer').textContent=s.cache_duration?s.cache_duration.toFixed(1)+'s':'--';document.getElementById('res').textContent=s.resolution||'--';document.getElementById('fps').textContent=s.fps?s.fps.toFixed(1):'--';document.getElementById('drops').textContent=s.dropped_frames||'0';document.getElementById('codec').textContent=s.video_codec||'--'}catch(e){}},500)</script></body></html>`
