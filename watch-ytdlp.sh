#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-ytdlp.sh
# Mode DIRECT : yt-dlp → HLS URL → mpv (sans streamlink).
# Gain : -100 à -500ms. Risque : pas de retry automatique.
#
# Compatible: macOS (Intel + Apple Silicon), Linux, WSL2
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

usage() {
    show_help "$(basename "$0")" \
        "Direct — yt-dlp → mpv (sans streamlink, le plus rapide)" \
        "Gain : -100 à -500ms. Risque : pas de retry auto."
    echo -e "${C_DIM}Résilient : watch-resilient.sh | Stable : watch.sh${C_NC}"
}

parse_common_args "$@"
[ -z "$URL" ] && { usage; exit 1; }

missing=()
command -v yt-dlp >/dev/null 2>&1 || missing+=("yt-dlp")
command -v mpv >/dev/null 2>&1 || missing+=("mpv")
if [ ${#missing[@]} -gt 0 ]; then
    fail "Outils manquants : ${missing[*]}"
    echo -e "  ${C_CYAN}brew install yt-dlp mpv${C_NC}"
    exit 1
fi

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
    --hls-live-edge=1
    --cache-secs=0
)
read -ra HW_ARGS <<< "$HW_DEC"
MPV_ARGS+=("${HW_ARGS[@]}")

# ─── LANCEMENT ────────────────────────────────────────────────────────────────
print_header "🔗  YouTube Live — Mode DIRECT" "$YLU_OS / $YLU_ARCH · yt-dlp → mpv"
echo ""
echo -e "  ${C_CYAN}URL  ${C_NC}: $URL"

progress "Résolution" "Extraction de l'URL HLS via yt-dlp..."
HLS_URL=$(yt-dlp -g --format "best" "$URL" 2>/dev/null)

if [ -z "$HLS_URL" ]; then
    fail "Impossible d'extraire l'URL HLS."
    echo -e "  ${C_YELLOW}→ Essaie ${C_CYAN}watch.sh${C_YELLOW} (streamlink) pour contourner.${C_NC}"
    exit 1
fi

success "URL HLS extraite"
echo ""

renice_process -15
exec mpv "${MPV_ARGS[@]}" "$HLS_URL"
