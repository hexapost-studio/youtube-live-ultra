#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-ultra.sh
# Mode AGRESSIF : latence absolument minimale (hls-live-edge=1, cache=no).
#
# ⚠️ Latence ~2-5s. Micro-freezes possibles si réseau instable.
# Compatible: macOS (Intel + Apple Silicon), Linux, WSL2
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

usage() {
    show_help "$(basename "$0")" \
        "Ultra-Agressif — latence minimale (hls-live-edge=1, cache=no)" \
        "⚠️  Latence ~2-5s. Micro-freezes possibles si réseau instable."
    echo -e "${C_DIM}Mode stable : watch.sh | Résilient : watch-resilient.sh${C_NC}"
}

parse_common_args "$@"
[ -z "$URL" ] && { usage; exit 1; }
URL="${URL//\\/}"

missing=()
command -v streamlink >/dev/null 2>&1 || missing+=("streamlink")
command -v mpv >/dev/null 2>&1 || missing+=("mpv")
if [ ${#missing[@]} -gt 0 ]; then
    fail "Outils manquants : ${missing[*]}"
    echo -e "  ${C_CYAN}brew install streamlink mpv${C_NC}"
    exit 1
fi

# ─── STREAMLINK ULTRA ────────────────────────────────────────────────────────
STREAMLINK_ARGS=(
    --loglevel warning
    --hls-live-edge 1
    --stream-segment-threads 4
    --ringbuffer-size "128M"
    --retry-max 10
    --retry-streams 5
    --stream-segmented-queue-deadline 0.5
    --stream-segment-timeout 5
    --hls-live-restart
)

HW_DEC=$(mpv_hwdec_args)
MPV_ARGS=(
    --profile=low-latency
    --cache=no
    --demuxer-max-bytes=500K
    --demuxer-readahead-secs=0.05
    --video-latency-hacks=yes
    --framedrop=vo+decoder
    --video-sync=display-resample
    --vd-lavc-threads=6
    --audio-buffer=0.1
    --video-reversal-buffer=0
    --keep-open=no
    --force-window=yes
    --osc=no
)
read -ra HW_ARGS <<< "$HW_DEC"
MPV_ARGS+=("${HW_ARGS[@]}")
$YLU_IS_APPLE_SILICON && MPV_ARGS+=(--video-sync-max-video-change=10)

# ─── LANCEMENT ────────────────────────────────────────────────────────────────
print_header "${ICON_ROCKET}  YouTube Live — Mode ULTRA" "$YLU_OS / $YLU_ARCH · hls-live-edge=1"
echo ""

YT_LATENCY=$(ping_latency youtube.com 3)
echo -e "  ${C_CYAN}URL     ${C_NC}: $URL"
echo -e "  ${C_CYAN}Ping YT ${C_NC}: ${YT_LATENCY}ms"
echo -e "  ${C_CYAN}GPU     ${C_NC}: $(mpv_hwdec_args | cut -c1-50)..."
echo ""

renice_process -15

streamlink "${STREAMLINK_ARGS[@]}" "$URL" best \
    --player mpv \
    --player-args "${MPV_ARGS[*]}" \
    --player-no-close
