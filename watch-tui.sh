#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-tui.sh
# Interface terminal interactive (dialog) pour les serveurs headless/SSH.
# Affiche : stats mpv IPC, chat, contrôles — tout dans le terminal.
#
# Usage: ./watch-tui.sh <URL_YOUTUBE_LIVE> [--mode ultra|standard|direct]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

usage() {
    echo -e "${C_BOLD}Usage:${C_NC} $(basename "$0") <URL_YOUTUBE_LIVE> [--mode MODE]"
    echo ""
    echo "  Interface terminal interactive pour serveurs/SSH."
    echo "  Affiche stats live + chat dans une TUI."
    echo -e "  ${C_DIM}OS: $YLU_OS ($YLU_ARCH)${C_NC}"
    exit 1
}

URL=""
MODE="standard"
export MODE

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --mode) MODE="$2"; shift 2 ;;
        *) URL="$1"; shift ;;
    esac
done
[ -z "$URL" ] && usage

# ─── CHECK DEPS ──────────────────────────────────────────────────────────────
if ! command -v dialog >/dev/null 2>&1; then
    fail "dialog requis. Installe : brew install dialog"
    exit 1
fi
for tool in streamlink yt-dlp mpv socat; do
    command -v "$tool" >/dev/null 2>&1 || { fail "$tool manquant"; exit 1; }
done

# ─── LAUNCH MPV ──────────────────────────────────────────────────────────────
IPC_SOCKET="/tmp/mpv-tui-$$"
HW_DEC=$(mpv_hwdec_args)
read -ra HW_ARGS <<< "$HW_DEC"

mpv --input-ipc-server="$IPC_SOCKET" \
    --profile=low-latency --cache=yes --demuxer-max-bytes=2M \
    --video-latency-hacks=yes --framedrop=vo --video-sync=audio \
    --vd-lavc-threads=4 --audio-buffer=0.2 \
    --keep-open=no --force-window=yes \
    --ytdl=yes --ytdl-format=bestvideo+bestaudio/best \
    "${HW_ARGS[@]}" "$URL" &
MPV_PID=$!
sleep 2

# ─── IPC HELPERS ─────────────────────────────────────────────────────────────
mpv_get() {
    local prop="$1"
    echo '{ "command": ["get_property", "'"$prop"'"] }' | \
        socat - "UNIX-CONNECT:$IPC_SOCKET" 2>/dev/null | \
        grep -o '"data":[^,}]*' | cut -d: -f2- | tr -d '"' || echo "?"
}

# ─── TUI MAIN LOOP ───────────────────────────────────────────────────────────
cleanup() { kill "$MPV_PID" 2>/dev/null; rm -f "$IPC_SOCKET"; clear; }
trap cleanup EXIT INT TERM

# Arrêter le stream
stop_stream() {
    kill "$MPV_PID" 2>/dev/null
    rm -f "$IPC_SOCKET"
    clear
    echo "Stream arrêté."
    exit 0
}

while kill -0 "$MPV_PID" 2>/dev/null; do
    # Récupérer les stats
    res=$(mpv_get "video-params/w")
    resh=$(mpv_get "video-params/h")
    fps=$(mpv_get "estimated-vf-fps")
    drops=$(mpv_get "vo-drop-frame-count")
    cache=$(mpv_get "demuxer-cache-duration")
    codec=$(mpv_get "video-params/codec")
    hw=$(mpv_get "hwdec-current")
    bitrate=$(mpv_get "video-bitrate")
    paused=$(mpv_get "pause")
    time_pos=$(mpv_get "time-pos")

    # Formater
    [[ "$res" == "?" ]] && res="--"
    [[ "$resh" == "?" ]] && resh="--"
    [[ "$fps" == "?" ]] && fps="--"
    [[ "$drops" == "?" ]] && drops="0"
    [[ "$cache" == "?" ]] && cache="--"
    [[ "$codec" == "?" ]] && codec="--"
    [[ "$hw" == "?" ]] && hw="--"
    [[ "$bitrate" == "?" ]] && bitrate="0"
    [[ "$paused" == "true" ]] && paused="⏸" || paused="▶"

    latency="--"
    [[ "$cache" != "--" ]] && latency=$(echo "scale=1; $cache + 2" | bc 2>/dev/null || echo "--")
    br_mbps=$(echo "scale=1; $bitrate / 1000" | bc 2>/dev/null || echo "0")
    t=$(echo "$time_pos" | cut -d. -f1)
    elapsed=""
    [[ "$t" != "?" && "$t" != "--" ]] && elapsed=$(printf '%02d:%02d:%02d' $((t/3600)) $(((t%3600)/60)) $((t%60)))

    # Construire la sortie
    body="\
Latence estimée : ${latency}s
Buffer         : ${cache}s
Résolution     : ${res}x${resh}
FPS            : ${fps}
Drops          : ${drops}
Codec          : ${codec}
Décodeur       : ${hw}
Débit          : ${br_mbps} Mbps
Temps          : ${elapsed}
Status         : ${paused}
"

    # Afficher avec dialog
    dialog --title "🎬 YouTube Live Ultra — $YLU_OS/$YLU_ARCH" \
        --no-collapse \
        --ok-label "⏯ Pause" \
        --extra-button --extra-label "⏹ Stop" \
        --help-button --help-label "🔄 Rafraîchir" \
        --infobox "$body" 15 50 2>&1
    
    ret=$?
    case $ret in
        0)  # OK = pause
            echo '{ "command": ["cycle", "pause"] }' | socat - "UNIX-CONNECT:$IPC_SOCKET" 2>/dev/null
            ;;
        3)  # Extra = stop
            stop_stream
            ;;
        2)  # Help = refresh
            ;;
    esac
    
    sleep 1
done

cleanup
