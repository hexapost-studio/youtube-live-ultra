#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-tui.sh
# Interface terminal curses (Python stdlib) pour serveurs/SSH.
# Remplace l'ancienne version dialog (1994) par curses natif Python.
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
    echo "  TUI curses (Python stdlib) — stats mpv IPC en temps réel."
    echo "  q=quitter  p=pause  ←→=seek  r=rafraîchir"
    echo -e "  ${C_DIM}OS: $YLU_OS ($YLU_ARCH)${C_NC}"
    exit 1
}

URL=""
MODE="standard"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) usage ;;
        --mode) MODE="$2"; shift 2 ;;
        *) URL="$1"; shift ;;
    esac
done
[ -z "$URL" ] && usage

if ! command -v python3 >/dev/null 2>&1; then
    fail "Python 3 requis. Installe : brew install python3"
    exit 1
fi

print_header "🖥️  YouTube Live — TUI" "$YLU_OS / $YLU_ARCH"
echo ""
echo -e "  ${C_CYAN}URL  ${C_NC}: $URL"
echo -e "  ${C_CYAN}Mode ${C_NC}: $MODE"
echo ""

exec python3 "$SCRIPT_DIR/dashboard/tui.py" "$URL" --mode "$MODE"
