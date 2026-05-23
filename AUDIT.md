# BRUTALLY HONEST TECHNICAL AUDIT — youtube-live-ultra v1.0.0
Date: 2026-05-22 | Full-stack audit against FAANG standards and OSS equivalents

## EXECUTIVE SUMMARY

The project is surprisingly good for v1.0.0. The architecture — Bash launchers calling battle-tested Python/C binaries — is the correct choice at this scale. There are no catastrophic wrong tool choices. However, there are death-by-a-thousand-cuts issues: Bash at 2300+ lines is past its maintainability ceiling, dialog is a zombie from 1994, and the dashboard is held together with duct tape.

**Grade: B+**. Two critical fixes needed. One architectural decision to make before v2.0.

---

## COMPONENT-BY-COMPONENT AUDIT

### 1. BASH (~2300 lines across 10+ files) — CLI Launchers + Orchestration

**What similar OSS uses:**
| Project | Stars | Language | Build System | Test Framework |
|---------|-------|----------|-------------|----------------|
| yt-dlp | 164K | Python 3.10+ | hatchling | pytest |
| streamlink | ~11K | Python | setuptools | pytest |
| mpv | ~29K | C + Lua | meson | custom C |
| Invidious | ~20K | Crystal | shards | crystal spec |
| FreeTube | ~15K | JS/Electron | npm | jest |
| ytfzf | ~4K | POSIX sh | Makefile | bats-core |

**Brutal answer: ytfzf is your only real peer. It is POSIX sh + Makefile + bats-core — exactly your stack.**

**Is Bash correct for 2300 lines?**
- YES for v1.0.0 (~500 lines per file). Bash is the king of process orchestration.
- NO for where you are heading. At 2300 lines you are hitting Bash's cliff: no types, no modules, no package manager, no debugger, no stack traces, stringly-typed everything.

**What would a FAANG engineer choose?**
- Go (single binary). At YouTube, the live pipeline is C++ (encoder) and Go (serving/orchestration). A single Go binary: go build produces one executable with zero dependencies.
- Rust (if latency is religion). Overkill here.

**What would a solo developer optimizing for maintainability choose?**
- Python. Both streamlink and yt-dlp are Python. One language for everything except mpv itself.
- Go is a close second. Single binary = no pip install, no venv, no Python version hell.

**Hidden costs of Bash:**
1. Testing is a joke. bats-core runs scripts and checks stdout. No mocking, no fixtures, no code coverage.
2. Refactoring is Russian roulette. Rename a variable? Hope you found all 47 occurrences.
3. Multi-platform is brittle. platform.sh is 255 lines of if/elif that explodes combinatorially.
4. No ecosystem. Want structured logging? Write it. Want JSON? Hope grep/cut is enough.

**Verdict: STAY BASH FOR V1.0, PLAN GO FOR V2.0.** You are at Bash's ceiling. Do not write another 500 lines of Bash.

---

### 2. PYTHON STDLIB (~267 lines) — Dashboard Web Server

**What it does:** HTTP server using http.server, JSON IPC to mpv, HTML/CSS/JS inlined as a triple-quoted Python string.

**Is Python stdlib correct?**
- For 267 lines, YES. http.server is production-grade enough for localhost. Zero pip deps is beautiful.
- But the HTML-in-a-string pattern is a crime. 160 lines of minified HTML/CSS/JS stuffed into a Python variable. You cannot lint the JS, format the CSS, or use any frontend tooling.

**What would FAANG use?**
- Go single binary with embed.FS for the dashboard. net/http is more performant. The dashboard would be separate .html/.css/.js files, embedded at build time.
- For the frontend: HTMX + Pico.css/Water.css. No React, no build step, no node_modules.

**What would a solo dev choose?**
- Keep Python stdlib but EXTRACT HTML to separate files. Use pathlib to serve dashboard/templates/index.html as a file.
- Alternative: Just kill the dashboard. Press Shift+I then 2 in mpv and you get: frame drops, decoder speed, cache state, bitrate, display FPS. It is better than your dashboard and requires ZERO code.

**Hidden costs:**
1. poll_chat() spawns yt-dlp --write-live-chat to a temp file, then polls it. File truncation races, zombie processes, no error recovery.
2. IPC polling runs a tight 0.5s loop hammering mpv's Unix socket. Fine for localhost but crude.
3. Your "latency estimate" is cache_duration + 2s — a heuristic, not a measurement. True end-to-end latency requires comparing frame-embedded timestamps with wall-clock time.

**Verdict: ADEQUATE for v1.0. Extract HTML to files. Kill the dashboard v2 (mpv stats overlay is better). Or rewrite in Go.**

---

### 3. dialog (C, 1994) — Terminal UI

**Current state:** watch-tui.sh (150 lines) uses dialog in a while loop sending mpv IPC commands via socat, displaying stats in a dialog --infobox.

**Is dialog correct?**
**NO. This is the worst tool choice in the project.** dialog is a 30-year-old utility designed for shell installer menus. It was NEVER designed for real-time streaming dashboards. --infobox flickers, has no scrollback, and looks like a BIOS setup screen.

**What would FAANG use?**
- bubbletea (Go) — The industry standard for TUIs. Used by Docker, Kubernetes tools, GitHub CLI. Mouse support, no flickering.
- textual (Python) — Rich-rendered TUIs with CSS-like styling, async, widget library.

**What do similar OSS projects use?**
- ytfzf: fzf + Ueberzug. Not a live dashboard.
- mpv: Built-in OSC + terminal output. No separate TUI needed.
- **No live-streaming TUI project uses dialog. None. Zero.**

**What would a solo dev choose?**
- bubbletea. Single Go binary includes the TUI. No dependency on a 30-year-old C utility.
- For Bash, use tput/ANSI directly instead of dialog. At least you have control over flickering.

**Hidden costs:**
1. dialog --infobox clears the screen on every refresh. Jarring.
2. Button-based interaction model (OK/Pause, Extra/Stop, Help/Refresh) is awkward for a video player.
3. dialog is not installed by default on macOS. Extra brew install for a 1994 tool.
4. socat IPC calls inside the dialog loop are fragile — one timeout and the TUI hangs.

**Verdict: REPLACE. dialog is a zombie. Use bubbletea (Go) or textual (Python). Or just kill the TUI — mpv's built-in stats overlay is already superior.**

---

### 4. streamlink (Python) — Stream Extraction

**Is streamlink correct?**
**YES, and it should be the PRIMARY backend, not the fallback.** Your current code uses yt-dlp first, streamlink as fallback. This is backwards. Streamlink provides:
- Ring buffer (--ringbuffer-size) — smooths network jitter. mpv native HLS has NO equivalent.
- Multi-threaded segment download (--stream-segment-threads)
- HLS live edge control (--hls-live-edge)
- Built-in retry (--retry-max, --retry-streams)

**Could mpv ytdl_hook.lua replace streamlink entirely?**
**NO.** ytdl_hook.lua bypasses streamlink's ring buffer and segment threading. For live HLS, you WANT streamlink's buffering layer. Direct mpv->HLS is more fragile (no retry, no parallel segments, no jitter smoothing).

| Feature | streamlink | mpv ytdl_hook.lua |
|---------|-----------|-------------------|
| Ring buffer (jitter smoothing) | YES | NO |
| Multi-threaded segments | YES | NO |
| Retry logic | YES | NO (stream just dies) |
| 403/datacenter bypass | YES (cookies) | NO |
| Latency | Baseline | ~100-500ms lower (bypasses buffer) |

**Verdict: CORRECT but REVERSE PRIORITY. streamlink -> yt-dlp -> mpv-native.**

---

### 5. yt-dlp (Python) — URL Extraction

**Is yt-dlp the best?**
**YES. Unquestionably.** 164K GitHub stars. Team of reverse-engineers keeping up with Google's changes. No alternative within an order of magnitude of quality.

**Are there better alternatives for live streams specifically?**
**NO.** yt-dlp already uses YouTube's InnerTube API (same API as the official mobile app). If there were a lower-latency format, yt-dlp would already support it.

**Verdict: CORRECT. No alternative exists.**

---

### 6. mpv (C+Lua) — Video Playback

**Is mpv the best player for low-latency live streaming?**
**YES, unmatched.** No other player has:
- --profile=low-latency (built-in preset)
- --video-latency-hacks=yes (bypasses timing safety checks)
- --framedrop=vo+decoder (aggressive frame dropping)
- JSON IPC server for external monitoring/control
- Hardware acceleration for every platform

**Competitors:**
- **ffplay:** No low-latency profile, no hardware decode API, no IPC. +2-5s latency.
- **VLC:** Heavy buffering by design. +2-5s additional latency.
- **QuickTime/Windows Media Player:** Joke answers. 30s+ buffering.

**One issue:** mpv.conf hardcodes hwdec=videotoolbox and vo=gpu-next. Works on Apple Silicon Macs but will fail on Intel Macs without Metal support, and on Linux without right drivers. platform.sh correctly detects per platform — good. But the config file should NOT hardcode platform-specific values.

**Verdict: CORRECT. Fix hardcoded mpv.conf values.**

---

### 7. bats-core — Test Framework

**Is bats-core correct for testing Bash scripts?**
**For Bash scripts, yes — it is the standard.** ytfzf uses it too.

**But your tests are shallow.** Let me be brutally honest:
- Your unit tests check: "does file exist?", "is it executable?", "does bash -n pass?", "does --help show Usage?".
- These are linting checks, not behavioral tests.
- ZERO tests for: URL parsing, HLS resolution, exit code handling, retry logic, lock file acquisition/cleanup, IPC command serialization, exponential backoff calculation.
- Integration tests skip if tools aren't installed or if there is no network. In CI, half your integration tests are skipped.

**What would FAANG use?**
- **Pytest with mocks and fixtures** (Python). Mock subprocess, mock socket, test every code path.
- **Go built-in testing with table-driven tests** (Go). Test every function in isolation.
- **Property-based testing** (Hypothesis for Python, rapid for Go) for the retry/backoff logic.

**What would a solo dev choose?**
- bats-core with better test design. Mock external commands by putting fake streamlink/mpv/yt-dlp scripts in PATH during tests.
- If moving to Python/Go: pytest / go test with proper fixtures and coverage reporting.

**Verdict: bats-core is CORRECT but your tests are INSUFFICIENT. Write behavioral tests.**

---

### 8. Makefile — Build System

**Is Make correct?**
**For a Bash project with no compilation, YES.** There is nothing to build. Your "build" is copying shell scripts to /usr/local/bin. Make is perfect.

**What do similar OSS projects use?**
- **ytfzf:** Makefile. Same as you.
- **yt-dlp:** hatchling (Python build). Not applicable.
- **mpv:** meson (C/C++). Not applicable.

**Verdict: CORRECT. Consider just as a nicer command runner but not necessary.**

---

### 9. shellcheck + GitHub Actions — Linting + CI

**shellcheck: CORRECT. Essential.** Your .shellcheckrc pragmatically disables SC2086 (quoting) for mpv arg arrays and SC1091 (source following). Add shfmt for formatting.

**GitHub Actions: GOOD.** Four parallel jobs (lint, test, version, build). Missing:
- Cross-platform CI: You claim macOS+Linux+WSL support but only test on ubuntu-latest. Add macos-latest runner.
- Pin ludeeus/action-shellcheck from master to a specific version tag.

**Verdict: GOOD. Add macOS CI runner. Add shfmt.**

---

## CROSS-CUTTING: SHOULD WE UNIFY TO A SINGLE LANGUAGE?

**YES, for v2.0. Go or Python?**

| Criterion | Go | Python |
|-----------|-----|--------|
| Single binary deployment | YES (go build) | NO (needs Python + pip) |
| Startup time | <5ms | 50-150ms |
| Async/concurrency | goroutines (built-in) | asyncio (stdlib) |
| mpv IPC | net.Dial (stdlib) | socket (stdlib) |
| HTTP dashboard | net/http + embed (stdlib) | http.server (stdlib) |
| YouTube ecosystem | Subprocess to yt-dlp | Could import yt-dlp as library |
| Cross-compilation | Trivial (GOOS=darwin) | Platform-specific Python |
| Binary size | ~6-12MB | N/A (script) |
| FAANG alignment | YouTube live = Go | yt-dlp = Python |
| Learning curve for Bash devs | Moderate (types, pointers) | Low (duck typing) |

**Recommendation: Go.** The killer feature is go build -> single binary. No pip install, no venv, no Python version management. The binary embeds the dashboard HTML. Ships as one file. This is what FAANG would do.

However, Python is defensible. yt-dlp and streamlink ARE Python. If you ever want to import them as libraries instead of subprocess, Python is the only option. And your dashboard server is already Python stdlib.

**For v1.0: stay Bash + Python. For v2.0: rewrite in Go. Timeline: 2-3 weeks for a competent Go developer.**

---

## CROSS-CUTTING: CAN mpv ytdl_hook.lua REPLACE streamlink?

**NO.** The ring buffer is streamlink's secret weapon. It absorbs network jitter — when WiFi drops a packet, streamlink already downloaded the next 1-2 segments. mpv native HLS fetches just-in-time, so any hiccup causes a visible stutter.

Optimal strategy (which watch-resilient.sh already implements correctly):
1. streamlink with ring buffer (primary, smoothest)
2. yt-dlp direct extraction (fallback, when streamlink blocked)
3. mpv --ytdl=yes (ultime fallback)

---

## PRIORITY ACTION ITEMS

### CRITICAL (do before any public release):
1. **Remove find-best-edge.sh** — DNS-overriding Google CDN entries is actively harmful. Google uses Anycast + GeoDNS; hardcoding IPs bypasses routing intelligence. (Already done per prior AUDIT.)
2. **Add mpv JSON IPC health checks to watchdog** — PID-only monitoring misses freezes (most common failure mode). watch-resilient.sh already has IPC health checks implemented (time-pos, cache-duration) — ensure ALL launchers use them. (Already done.)

### HIGH (do before v1.1):
3. **Extract HTML/CSS/JS from server.py to separate files** — the inline string is unmaintainable.
4. **Fix mpv.conf hardcoded values** — hwdec=videotoolbox and vo=gpu-next should be platform-detected, not hardcoded.
5. **Reverse streamlink/yt-dlp priority in watch.sh** — streamlink should be primary (already correct in watch-resilient.sh).

### MEDIUM (plan for v1.2-v1.3):
6. **Replace dialog TUI with bubbletea or textual** — dialog is a 1994 zombie. This is the single worst tool choice in the project.
7. **Add macOS CI runner** to GitHub Actions.
8. **Write behavioral tests** that mock external binaries and test retry/backoff/logic.
9. **Add shfmt to lint workflow** for consistent formatting.

### STRATEGIC (v2.0 planning):
10. **Rewrite orchestration in Go** — single binary, embedded dashboard, proper concurrency, type safety.
11. **Investigate YouTube InnerTube API** for lower-latency formats (yt-dlp already uses it partially).

---

## FINAL VERDICT MATRIX

| # | Component | Current | Grade | FAANG would use | Solo dev should use | Action |
|---|-----------|---------|-------|-----------------|---------------------|--------|
| 1 | CLI launchers | Bash | B+ | Go | Python or Go | Rewrite v2.0 |
| 2 | Dashboard server | Python stdlib | B | Go embed | Python (extract HTML) | Extract HTML |
| 3 | Dashboard UI | Inline HTML/JS | C | HTMX + embedded | Separate template files | Extract to files |
| 4 | TUI | dialog (C, 1994) | D | bubbletea (Go) | bubbletea or textual | REPLACE |
| 5 | Stream extraction | streamlink+yt-dlp | A | Same | Same | Reverse priority |
| 6 | URL extraction | yt-dlp | A+ | Same | Same | Keep |
| 7 | Video player | mpv | A+ | Same | Same | Keep |
| 8 | Tests | bats-core | C (shallow) | pytest/go test | bats-core (better tests) | Behavioral tests |
| 9 | Build system | Makefile | A | Just or Make | Make | Keep |
| 10 | Linting | shellcheck | A | shellcheck + shfmt | Same | Add shfmt |
| 11 | CI | GitHub Actions | B+ | Same + macOS runner | Same | Add macOS runner |
| 12 | Config | Shell KEY=VALUE | C | TOML + XDG | TOML + XDG | Migrate format |

**Overall: B+.** The architecture is sound. The tool choices are mostly correct for v1.0. The Bash ceiling is approaching. The dashboard HTML-in-a-string and dialog TUI are the weakest links. Fix the critical items, plan Go for v2.0, and you have a genuinely impressive tool.
