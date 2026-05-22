# CRITICAL TECHNICAL AUDIT — youtube-live-ultra
Date: 2026-05-22 | Deep-dive across GitHub, docs, industry standards

## 1. LANGUAGE: Bash Shell Scripts

**Current:** Four Bash scripts (~500 lines) + platform.sh (~250 lines). Shellcheck-clean.

**Industry:** streamlink (Python, 11.5k stars), yt-dlp (Python, 164k), mpv (C+Lua), Invidious (Crystal, 20.1k), OBS Studio (C/C++, 72.6k). No major CLI launcher for YouTube live uses Bash — but no competitor does exactly what this project does.

**Analysis:** Bash is correct for THIS scope. The project is a launcher calling external binaries (streamlink, yt-dlp, mpv). Bash excels at process management. Startup: Bash <5ms vs Python ~50-150ms. What Python would add: proper JSON, structured config, async subprocess, easier testing, easier contributions. What Go/Rust would add: single binary, type safety, true concurrency. The project is near Bash's maintainability ceiling (~800 lines).

**Verdict: CORRECT for v1.0. Plan Python for v2.0 if features double.**

---

## 2. PLAYER: mpv vs ffplay vs VLC

**Current:** mpv with --profile=low-latency, --cache=no, --video-latency-hacks=yes, --untimed=yes, --framedrop=vo+decoder.

**Comparison:**
- mpv: Dedicated low-latency features (--untimed, --video-latency-hacks, --profile=low-latency). UNIQUE and UNMATCHED.
- ffplay: No equivalent to --untimed or --video-latency-hacks. No built-in yt-dlp hook. Higher latency.
- VLC: Heavy buffering by design. +2-5s additional latency. Wrong tool for sub-second latency.

**CRITICAL mpv Warning:** The official mpv manual states --untimed "will likely break, unless the stream has no audio." HLS live streams HAVE audio. This causes A/V desync. watch-ultra.sh uses --untimed — THIS IS A BUG.

**mpv built-in ytdl_hook.lua:** Can play YouTube URLs directly via --ytdl=yes. Calls yt-dlp internally, resolves URL, plays. Bypasses streamlink. Simple but less control.

**Verdict: CORRECT. Keep mpv. CRITICAL: Remove --untimed from all HLS modes.**

---

## 3. STREAM EXTRACTION: streamlink + yt-dlp

**Current:** yt-dlp first (yt-dlp -g --format best), streamlink fallback.

**Streamlink's unique value:** Ring buffer (--ringbuffer-size) smooths jitter — mpv native HLS has no equivalent. HLS live edge control (--hls-live-edge). Multi-threaded segment download (--hls-segment-threads). Retry logic. Streamlink is NOT just a URL resolver — it's a buffered, multi-threaded HLS proxy.

**Priority is BACKWARDS:** Current yt-dlp → streamlink. Should be streamlink → yt-dlp. streamlink provides smoother playback with its ring buffer.

**Third option:** mpv --ytdl=yes as fallback #3.

**Verdict: GOOD. Reverse priority: streamlink → yt-dlp → mpv-native.**

---

## 4. PROTOCOL: HLS with hls-live-edge=1

**Current:** Standard HLS (MPEG-TS segments, 2-6s). hls-live-edge=1 = ~2-6s theoretical minimum.

**YouTube reality:** Serves HLS and DASH. Does NOT serve: LL-HLS (Apple), WebRTC video, CMAF chunked. "Ultra Low Latency" setting is for STREAMER→YOUTUBE ingest, not viewer consumption. Viewers always get HLS.

**The project already achieves LOWER latency than the official YouTube web player** (which uses MSE with ~30s pre-buffer).

Protocol hierarchy for viewers (theoretical minimum):
1. WebRTC: 0.2-0.5s — NOT available from YouTube
2. LL-HLS: 1-3s — NOT available from YouTube  
3. HLS edge=1: 2-6s — CURRENT BEST
4. HLS edge=3: 6-18s
5. DASH: 6-30s

**Verdict: BEST CURRENTLY ACHIEVABLE. No lower latency protocol exists.**

---

## 5. CDN EDGE SELECTION: DNS-Based

**Current:** find-best-edge.sh uses HARDCODED Google CDN domains (rr1---sn-8xgn5u8a-2bole.googlevideo.com), pings IPs, suggests /etc/hosts override.

**PROBLEMS:**
1. Hardcoded edge node names are EPHEMERAL — Google rotates them regularly
2. Overriding DNS BYPASSES Google's intelligent GeoDNS (load balancing, BGP peering, ISP colocation)
3. Google CDN uses ANYCAST — DNS override can break anycast routing
4. Benefit is marginal (10-20ms) but risk is high (stale entries, broken routing)

**Verdict: DANGEROUS anti-pattern. REMOVE find-best-edge.sh entirely.**

---

## 6. WATCHDOG: PID Monitoring

**Current:** kill -0 $MPV_PID every 3s. Detects death. Does NOT detect freezes (most common failure mode), buffer underrun, A/V desync.

**Fix:** mpv JSON IPC. Add --input-ipc-server=/tmp/mpv-socket-$$. Watchdog sends commands:
  echo '{ "command": ["get_property", "time-pos"] }' | socat - /tmp/mpv-socket-$$
Check: responding? time advancing? demuxer-cache-duration growing? If cache >5s → stuck → restart.

**Verdict: INSUFFICIENT. Must add mpv IPC health checks.**

---

## 7. NETWORKING: sysctl TCP Tuning

**Current:** YLU_TCP_RECVSPACE=4194304 (4MB buffer), YLU_TCP_DELAYED_ACK=0 (disable Nagle).

**Reality:** Modern OSes auto-tune TCP perfectly. HLS is bursty (segments with gaps between downloads) — TCP buffers rarely fill. Manual tuning is cargo-cult from 2005. HTTP/3 (QUIC) wouldn't help — HLS segment downloads are bulk transfers where TCP HOL blocking doesn't matter.

**What actually helps:** Fast DNS (1.1.1.1), Ethernet vs WiFi (+15ms), avoiding competing traffic. fq_codel/tc qdisc for traffic prioritization if on Linux.

**Verdict: INEFFECTIVE. Remove TCP tuning. Keep only DNS preference. Add WiFi warning.**

---

## 8. CONFIGURATION: Config File + Env Vars

**Current:** Shell-style KEY=VALUE in config.example. Sourced by scripts (code injection risk). Lock/log in /tmp/ (not XDG compliant).

**XDG spec:** Config → ~/.config/, Cache → ~/.cache/. What leaders use: streamlink (INI, XDG), yt-dlp (option format, XDG), mpv (INI-like, XDG).

**Recommended:** TOML with sections ([streamlink], [mpv], [network], [watchdog]). Priority: CLI > env > local > user > system > defaults.

**Verdict: ADEQUATE but needs XDG compliance and TOML format.**

---

## 9. WHAT ARE WE MISSING?

**Headless Chromium + YouTube Player:** TERRIBLE idea. 5-10s latency, 500MB+ RAM, headless detection issues. Anti-goal for low latency.

**YouTube Mobile API (InnerTube):** Potentially exposes lower-latency formats. yt-dlp already uses it partially. Worth investigating.

**Missing features worth adding:**
1. mpv IPC health dashboard (latency to edge, segment times, buffer, dropped frames)
2. Audio-only mode for podcasts/talk shows (yt-dlp -f bestaudio + mpv --no-video)
3. Simultaneous recording (streamlink --record-and-pipe)
4. YouTube live chat overlay in terminal
5. Adaptive quality switching (requires stream restart with mpv HLS)

---

## SUMMARY TABLE

| # | Area | Verdict | Priority | Action |
|---|------|---------|----------|--------|
| 1 | Language (Bash) | CORRECT | Low | Stay Bash v1.0; Python v2.0 |
| 2 | Player (mpv) | CORRECT | HIGH | Remove --untimed from HLS |
| 3 | Extraction (dual backend) | GOOD | Medium | streamlink first, then yt-dlp |
| 4 | Protocol (HLS edge=1) | BEST | Low | No changes |
| 5 | CDN edge (DNS override) | DANGEROUS | CRITICAL | Remove find-best-edge.sh |
| 6 | Watchdog (PID-only) | INSUFFICIENT | CRITICAL | Add mpv JSON IPC |
| 7 | Networking (TCP tuning) | INEFFECTIVE | Medium | Remove; keep DNS pref |
| 8 | Configuration (shell) | ADEQUATE | Medium | XDG + TOML format |
| 9 | Missing features | — | Medium | IPC metrics, audio-only |

---

**THREE CRITICAL ACTIONS before any release:**

1. REMOVE find-best-edge.sh and /etc/hosts override suggestion — actively harmful
2. ADD mpv JSON IPC health checks to watchdog — PID-only misses freezes
3. REMOVE --untimed from HLS modes — breaks A/V sync per mpv documentation
