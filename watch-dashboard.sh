#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-dashboard.sh
# Lance le dashboard web (stats + chat + contrôles) pour un live YouTube.
#
# Usage: ./watch-dashboard.sh <URL_YOUTUBE_LIVE> [--mode MODE] [--port PORT]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

usage() {
    echo -e "${C_BOLD}Usage:${C_NC} $(basename "$0") <URL_YOUTUBE_LIVE> [--mode MODE] [--port PORT]"
    echo ""
    echo "  Lance le dashboard web avec :"
    echo "  📊 Stats live (latence, buffer, fps, drops)"
    echo "  💬 YouTube live chat"
    echo "  🎮 Contrôles (pause, qualité)"
    echo ""
    echo "  Ouvre http://localhost:9191 dans ton navigateur."
    echo ""
    echo -e "  ${C_DIM}OS: $YLU_OS ($YLU_ARCH)${C_NC}"
    echo ""
    echo "Modes: ultra | standard | direct"
    echo ""
    echo "Exemples:"
    echo "  $0 'https://www.youtube.com/watch?v=XXXXXXXXXXX'"
    echo "  $0 'https://www.youtube.com/watch?v=XXXXXXXXXXX' --mode ultra --port 8080"
    exit 1
}

URL=""
MODE="standard"
PORT=9191

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --mode) MODE="$2"; shift 2 ;;
        --port) PORT="$2"; shift 2 ;;
        *) URL="$1"; shift ;;
    esac
done

[ -z "$URL" ] && usage

# Vérifier Python
if ! command -v python3 >/dev/null 2>&1; then
    fail "Python 3 requis. Installe avec : brew install python3"
    exit 1
fi

# Vérifier Flask
if ! python3 -c "import flask" 2>/dev/null; then
    echo -e "  ${C_YELLOW}Installation de Flask...${C_NC}"
    pip3 install flask flask-sock 2>&1 | tail -1
fi

print_header "🎬  YouTube Live — Dashboard" "Stats · Chat · Contrôles"
echo ""
echo -e "  ${C_CYAN}URL   ${C_NC}: $URL"
echo -e "  ${C_CYAN}Mode  ${C_NC}: $MODE"
echo -e "  ${C_CYAN}Port  ${C_NC}: $PORT"
echo ""
echo -e "  🌐 ${C_GREEN}http://localhost:$PORT${C_NC}"
echo -e "  📺 La vidéo s'ouvre dans une fenêtre mpv séparée."
echo -e "  🛑 Ctrl+C pour tout arrêter."
echo ""

cd "$SCRIPT_DIR"
exec python3 dashboard/server.py "$URL" --port "$PORT" --mode "$MODE"
