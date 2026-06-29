# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - branche `go`

### Added
- **Support Windows natif** pour la version Go (`ylu.exe`), sans WSL2.
- `ipc_unix.go` / `ipc_windows.go` : IPC mpv abstrait par build-tags — socket Unix
  sur macOS/Linux, *named pipe* (`\\.\pipe\...`) sur Windows (sans dépendance tierce).
- Décodage GPU `d3d11va` détecté automatiquement sur Windows.
- CI : tests Go exécutés aussi sur `windows-latest` ; cross-compile `windows/arm64`.
- `bootstrap.ps1` : installe mpv/streamlink/yt-dlp via winget puis compile le
  binaire natif ; repli WSL2 via `-Wsl`.
- **Installation Windows facile + résiliente** : `bootstrap.ps1` télécharge
  désormais `ylu.exe` depuis la dernière GitHub Release (repli build-from-source) ;
  mpv installé via Scoop/Choco (vrai `mpv.exe`, plus `mpv.net`) ; PATH rafraîchi ;
  flag `-Build` pour forcer la compilation.
- `.github/workflows/release.yml` : publie les binaires précompilés
  (windows amd64/arm64, linux, macos + SHA256SUMS) sur une GitHub Release au tag `v*`.
- README : section « Installation » Windows en première page (download `ylu.exe`).

### Changed
- Watchdog mpv portable : supervision via goroutine + `cmd.Wait()` au lieu des
  appels Unix `syscall.Wait4` / `syscall.Kill` (compile désormais sur Windows).
- Chemins IPC dérivés de `os.TempDir()` (Unix) au lieu de `/tmp` codé en dur.

## [1.0.0] - 2026-05-22

### Added
- `watch.sh`: Standard mode with streamlink + mpv
- `watch-ultra.sh`: Aggressive ultra-low latency mode
- `watch-ytdlp.sh`: Direct yt-dlp mode bypassing streamlink
- `watch-resilient.sh`: Self-healing launcher with watchdog, multi-backend, exponential backoff
- `mpv.conf`: Optimized mpv configuration for Apple Silicon (VideoToolbox, Metal, GPU-next)
- `optimize-network.sh`: DNS, TCP, WiFi pre-flight network tuning
- `find-best-edge.sh`: Google CDN edge latency detection
- `benchmark-latency.sh`: Comparative latency measurement across 3 modes
- `health-check.sh`: 7-step pre-flight pipeline validation
- Multi-backend fallback (yt-dlp → streamlink)
- Watchdog with auto-restart and exponential backoff
- Lock file to prevent duplicate instances
- Structured session logging
- Makefile with install, test, lint, clean targets
- bats-core test suite
- Shellcheck integration
- GitHub Actions CI pipeline
- Homebrew formula
- Centralized configuration file support

### Research
- Academic survey: Bentaleb, Begen, Zimmermann et al. — IEEE COMST 2025 (arXiv:2310.03256)
- Camel: Frame-level congestion control for WebRTC live streaming — WWW 2026 (arXiv:2602.09500)
- JALE: JND-aware low latency encoding for HLS — MHV 2024 (arXiv:2401.15343)
- YouTube Live ingestion protocol comparison (RTMP, HLS, DASH)
- Twitch engineering blog: LL-HLS architecture, Intelligest, TwitchTranscoder

[1.0.0]: https://github.com/hexapost-studio/youtube-live-ultra/releases/tag/v1.0.0
