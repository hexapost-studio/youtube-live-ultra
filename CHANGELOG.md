# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
