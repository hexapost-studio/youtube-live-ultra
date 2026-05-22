#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch.sh
# Regarder un live YouTube avec latence minimale + résolution maximale.
#
# Compatible: macOS (Intel + Apple Silicon), Linux (X11 + Wayland), WSL2
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

usage() {
    show_help "$(basename "$0")" \
        "Standard — équilibre latence/stabilité (streamlink + mpv)" \
        "hls-live-edge=2 · segments 2-6s · latence ~4-8s"
    echo -e "${C_DIM}Autres modes : watch-ultra.sh | watch-ytdlp.sh | watch-resilient.sh${C_NC}"
}

# ─── PARSER ──────────────────────────────────────────────────────────────────
parse_common_args "$@"
[ -z "$URL" ] && { usage; exit 1; }

# ─── CHECK DEPS ──────────────────────────────────────────────────────────────
missing=()
command -v streamlink >/dev/null 2>&1 || missing+=("streamlink")
command -v mpv >/dev/null 2>&1 || missing+=("mpv")
if [ ${#missing[@]} -gt 0 ]; then
    fail "Outils manquants : ${missing[*]}"
    echo ""
    echo -e "  Installation rapide :"
    echo -e "    ${C_CYAN}brew install streamlink mpv${C_NC}"
    exit 1
fi

# ─── CONFIG ───────────────────────────────────────────────────────────────────
HLS_LIVE_EDGE=2
SEGMENT_THREADS=3
RINGBUFFER_SIZE="64M"
RETRY_MAX=5

# ─── STREAMLINK ARGS ─────────────────────────────────────────────────────────
STREAMLINK_ARGS=(
    --loglevel info
    --hls-live-edge "$HLS_LIVE_EDGE"
    --hls-segment-threads "$SEGMENT_THREADS"
    --stream-segment-threads "$SEGMENT_THREADS"
    --ringbuffer-size "$RINGBUFFER_SIZE"
    --retry-max "$RETRY_MAX"
    --retry-streams 3
    --hls-segment-queue-threshold 2
    --hls-segment-timeout 10
    --hls-timeout 30
)

# ─── MPV ARGS ────────────────────────────────────────────────────────────────
HW_DEC=$(mpv_hwdec_args)
MPV_ARGS=(
    --profile=low-latency
    --cache=yes
    --demuxer-max-bytes=2M
    --demuxer-readahead-secs=0.2
    --video-latency-hacks=yes
    --framedrop=vo
    --video-sync=audio
    --vd-lavc-threads=4
    --audio-buffer=0.2
    --keep-open=no
    --force-window=yes
)
read -ra HW_ARGS <<< "$HW_DEC"
MPV_ARGS+=("${HW_ARGS[@]}")

# ─── LANCEMENT ────────────────────────────────────────────────────────────────
print_header "${ICON_WATCH}  YouTube Live — Mode Standard" "$YLU_OS / $YLU_ARCH"
echo ""
echo -e "  ${C_CYAN}URL    ${C_NC}: $URL"
echo -e "  ${C_CYAN}Mode   ${C_NC}: Standard (hls-live-edge=$HLS_LIVE_EDGE)"
echo -e "  ${C_CYAN}GPU    ${C_NC}: $(mpv_hwdec_args | cut -c1-50)..."
echo -e "  ${C_CYAN}Qualité${C_NC}: best (auto)"
echo ""
echo -e "  ${C_DIM}Touches : q=quitter  f=plein écran  Shift+I=stats  9/0=volume${C_NC}"
echo ""

renice_process -10

MAX_STREAM_RETRIES=3
stream_retry=0

while [ $stream_retry -lt $MAX_STREAM_RETRIES ]; do
    streamlink "${STREAMLINK_ARGS[@]}" "$URL" best \
        --player "mpv ${MPV_ARGS[*]}" \
        --player-no-close

    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        exit 0
    fi

    stream_retry=$((stream_retry + 1))
    backoff=$((stream_retry * 2))

    warn_ux "Stream coupé — nouvel essai dans ${backoff}s ($stream_retry/$MAX_STREAM_RETRIES)"
    sleep "$backoff"
done

fail "Trop de tentatives. Essaie ${C_CYAN}watch-resilient.sh${C_NC} (self-healing)."
exit 1
