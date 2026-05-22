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

parse_common_args "$@"
[ -z "$URL" ] && { usage; exit 1; }

# Nettoyer l'URL (échappements shell accidentels)
URL="${URL//\\/}"

missing=()
command -v streamlink >/dev/null 2>&1 || missing+=("streamlink")
command -v mpv >/dev/null 2>&1 || missing+=("mpv")
command -v yt-dlp >/dev/null 2>&1 || missing+=("yt-dlp")
if [ ${#missing[@]} -gt 0 ]; then
    fail "Outils manquants : ${missing[*]}"
    echo -e "  ${C_CYAN}brew install streamlink mpv yt-dlp${C_NC}"
    exit 1
fi

HLS_LIVE_EDGE=2
SEGMENT_THREADS=3
RINGBUFFER_SIZE="64M"
RETRY_MAX=5

STREAMLINK_ARGS=(
    --loglevel info
    --hls-live-edge "$HLS_LIVE_EDGE"
    --stream-segment-threads "$SEGMENT_THREADS"
    --ringbuffer-size "$RINGBUFFER_SIZE"
    --retry-max "$RETRY_MAX"
    --retry-streams 3
    --stream-segmented-queue-deadline 0.5
    --stream-segment-timeout 10
)

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

# ─── FONCTION : lancer via streamlink ────────────────────────────────────────
launch_streamlink() {
    local quality="${1:-best}"
    progress "Streamlink" "Résolution en $quality..."

    streamlink "${STREAMLINK_ARGS[@]}" "$URL" "$quality" \
        --player mpv \
        --player-args "${MPV_ARGS[*]}" \
        --player-no-close 2>&1
    return $?
}

# ─── FONCTION : lancer via yt-dlp direct ─────────────────────────────────────
launch_ytdlp() {
    progress "yt-dlp" "Fallback direct..."

    # Essayer avec cookies navigateur (anti-blocage YouTube)
    local cookie_args=""
    for browser in chrome safari firefox; do
        if yt-dlp --cookies-from-browser "$browser" --print title "$URL" >/dev/null 2>&1; then
            cookie_args="--cookies-from-browser $browser"
            break
        fi
    done

    HLS_URL=$(yt-dlp -g --format "bestvideo+bestaudio/best" $cookie_args "$URL" 2>/dev/null)
    if [ -z "$HLS_URL" ]; then
        # Dernier essai sans cookies
        HLS_URL=$(yt-dlp -g --format "best" "$URL" 2>/dev/null)
    fi

    success "URL HLS extraite via yt-dlp"
    # shellcheck disable=SC2086
    exec mpv "${MPV_ARGS[@]}" "$HLS_URL"
}

# ─── FONCTION : lancer via mpv --ytdl (ultime fallback) ──────────────────────
launch_mpv_ytdl() {
    progress "mpv --ytdl" "Fallback intégré mpv..."

    exec mpv --ytdl=yes --ytdl-format="bestvideo+bestaudio/best" \
        --profile=low-latency \
        --cache=yes --demuxer-max-bytes=2M --demuxer-readahead-secs=0.2 \
        --video-latency-hacks=yes --framedrop=vo --video-sync=audio \
        --vd-lavc-threads=4 --audio-buffer=0.2 \
        --keep-open=no --force-window=yes \
        "${HW_ARGS[@]}" \
        "$1"
}

# ─── LANCEMENT ────────────────────────────────────────────────────────────────
print_header "${ICON_WATCH}  YouTube Live — Mode Standard" "$YLU_OS / $YLU_ARCH"
echo ""
echo -e "  ${C_CYAN}URL    ${C_NC}: $URL"
echo -e "  ${C_CYAN}GPU    ${C_NC}: $(mpv_hwdec_args | cut -c1-50)..."
echo -e "  ${C_DIM}Touches : q=quitter  f=plein écran  Shift+I=stats${C_NC}"
echo ""

renice_process -10

# ─── Essai 1 : streamlink best ───────────────────────────────────────────────
output=$(streamlink --loglevel error "$URL" 2>&1 || true)
quality=$(echo "$output" | grep -oE '[0-9]+p \(best\)' | grep -oE '[0-9]+p' || echo "unknown")

if [ "$quality" = "1080p" ] || [ "$quality" = "720p" ] || [ "$quality" = "480p" ]; then
    echo -e "  ${C_CYAN}Qualité${C_NC}: $quality détectée"
    if launch_streamlink "best" 2>&1 | grep -q "403\|Forbidden\|Could not open"; then
        warn_ux "YouTube 403 — IP datacenter bloquée. Fallback yt-dlp..."
        launch_ytdlp || launch_mpv_ytdl "$URL"
    fi
elif [ "$quality" != "unknown" ]; then
    warn_ux "YouTube throttle — $quality seulement. Fallback yt-dlp..."
    launch_ytdlp || launch_mpv_ytdl "$URL"
else
    warn_ux "Qualité inconnue. Fallback yt-dlp..."
    launch_ytdlp || launch_mpv_ytdl "$URL"
fi

# ─── Retry ────────────────────────────────────────────────────────────────────
MAX_STREAM_RETRIES=3
stream_retry=0

while [ $stream_retry -lt $MAX_STREAM_RETRIES ] && [ "${exit_code:-0}" -ne 0 ]; do
    stream_retry=$((stream_retry + 1))
    backoff=$((stream_retry * 2))
    warn_ux "Stream coupé — retry ${backoff}s ($stream_retry/$MAX_STREAM_RETRIES)"
    sleep "$backoff"

    launch_streamlink "best"
    exit_code=$?
done

if [ "${exit_code:-0}" -ne 0 ]; then
    fail "Impossible de lancer le stream. Essaie ${C_CYAN}watch-resilient.sh${C_NC}"
    exit 1
fi
