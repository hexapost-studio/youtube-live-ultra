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

# ─── NO_COLOR ────────────────────────────────────────────────────────────────
if [ -n "${NO_COLOR:-}" ] || [ -n "${YLU_NO_COLOR:-}" ]; then
    C_RED="" C_GREEN="" C_YELLOW="" C_CYAN="" C_BOLD="" C_DIM="" C_NC=""
fi

usage() {
    show_help "$(basename "$0")" \
        "Standard — équilibre latence/stabilité (streamlink + mpv)" \
        "hls-live-edge=2 · segments 2-6s · latence ~4-8s"
    echo -e "${C_DIM}Options : --dry-run  --verbose  --no-color${C_NC}"
    echo -e "${C_DIM}Autres modes : watch-ultra.sh | watch-ytdlp.sh | watch-resilient.sh${C_NC}"
}

# ─── PARSER ──────────────────────────────────────────────────────────────────
DRY_RUN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        --version)     show_version; exit 0 ;;
        --dry-run)     DRY_RUN=true; shift ;;
        --verbose|-v)  VERBOSE=true; shift ;;
        --no-color)    export YLU_NO_COLOR=1; shift ;;
        *)             URL="$1"; shift ;;
    esac
done

[ -z "${URL:-}" ] && { usage; exit 0; }

# Nettoyer l'URL (échappements shell accidentels)
URL="${URL//\\/}"

# ─── CHECK DEPS ──────────────────────────────────────────────────────────────
missing=()
command -v streamlink >/dev/null 2>&1 || missing+=("streamlink")
command -v mpv >/dev/null 2>&1 || missing+=("mpv")
command -v yt-dlp >/dev/null 2>&1 || missing+=("yt-dlp")
if [ ${#missing[@]} -gt 0 ]; then
    fail "Outils manquants : ${missing[*]}"
    echo -e "  ${C_CYAN}brew install ${missing[*]}${C_NC}"
    echo -e "  ${C_DIM}ou lance : ./install.sh --cli${C_NC}"
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

# ─── FONCTIONS ───────────────────────────────────────────────────────────────

launch_streamlink() {
    local quality="${1:-best}"
    $VERBOSE && progress "Streamlink" "Résolution en $quality..."
    streamlink "${STREAMLINK_ARGS[@]}" "$URL" "$quality" \
        --player mpv \
        --player-args "${MPV_ARGS[*]}" \
        --player-no-close 2>&1
    return $?
}

launch_ytdlp() {
    $VERBOSE && progress "yt-dlp" "Fallback direct..."
    local cookie_args=""
    for browser in chrome safari firefox; do
        if yt-dlp --cookies-from-browser "$browser" --print title "$URL" >/dev/null 2>&1; then
            cookie_args="--cookies-from-browser $browser"
            break
        fi
    done
    local extractor_args="--extractor-args youtube:player_client=android,web"
    $DRY_RUN && { success "Mode dry-run : stream détecté, pas de lancement."; exit 0; }
    success "Pipe yt-dlp → mpv (token frais)"
    exec yt-dlp -o - --format "bestvideo+bestaudio/best" $cookie_args $extractor_args "$URL" 2>/dev/null | \
        mpv "${MPV_ARGS[@]}" -
}

launch_mpv_ytdl() {
    $VERBOSE && progress "mpv --ytdl" "Fallback intégré..."
    $DRY_RUN && { success "Mode dry-run : stream détecté via mpv --ytdl."; exit 0; }
    exec mpv --ytdl=yes --ytdl-format="bestvideo+bestaudio/best" \
        --profile=low-latency --cache=yes --demuxer-max-bytes=2M \
        --demuxer-readahead-secs=0.2 --video-latency-hacks=yes \
        --framedrop=vo --video-sync=audio --vd-lavc-threads=4 \
        --audio-buffer=0.2 --keep-open=no --force-window=yes \
        "${HW_ARGS[@]}" "$URL"
}

# ─── LANCEMENT ────────────────────────────────────────────────────────────────
print_header "${ICON_WATCH}  YouTube Live — Mode Standard" "$YLU_OS / $YLU_ARCH"
echo ""

YT_LATENCY=$(ping_latency youtube.com 3)
echo -e "  ${C_CYAN}URL    ${C_NC}: $URL"
echo -e "  ${C_CYAN}Ping YT${C_NC}: ${YT_LATENCY}ms"
echo -e "  ${C_CYAN}GPU    ${C_NC}: $(mpv_hwdec_args | cut -c1-50)..."
echo -e "  ${C_DIM}Touches : q=quitter  f=plein écran  Shift+I=stats${C_NC}"
echo ""

renice_process -10

# Détection qualité
output=$(streamlink --loglevel error "$URL" 2>&1 || true)
# Extraire la meilleure qualité : "1080p (best)" ou "360p (worst, best)"
quality=$(echo "$output" | grep -oE '[0-9]+p[^)]*best' | grep -oE '^[0-9]+p' | tail -1 || echo "unknown")
stream_count=$(echo "$output" | grep -oE '[0-9]+p' | wc -l | tr -d ' ')

if [ "$quality" = "1080p" ] || [ "$quality" = "720p" ] || [ "$quality" = "480p" ]; then
    echo -e "  ${C_CYAN}Qualité${C_NC}: $quality ($stream_count streams dispo)"
    $DRY_RUN && { success "Mode dry-run : $quality détectée, stream prêt."; exit 0; }
    if launch_streamlink "best" 2>&1 | grep -q "403\|Forbidden\|Could not open"; then
        warn_ux "YouTube 403 — IP datacenter bloquée. Fallback yt-dlp..."
        launch_ytdlp || launch_mpv_ytdl "$URL"
    fi
elif [ "$quality" != "unknown" ]; then
    warn_ux "YouTube throttle — $quality seulement (${stream_count} streams). Fallback yt-dlp..."
    launch_ytdlp || launch_mpv_ytdl "$URL"
else
    warn_ux "Aucune qualité détectée (${stream_count} streams). Vérifie l'URL."
    echo -e "  ${C_DIM}Causes possibles : stream pas en live, URL invalide, VPN/Proxy bloqué${C_NC}"
    exit 1
fi
