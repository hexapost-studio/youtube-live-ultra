#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — benchmark-latency.sh
# Mesure comparative de la latence des 3 modes de lecture.
#
# Compatible: macOS, Linux, WSL2
# Usage: ./scripts/benchmark-latency.sh <URL_YOUTUBE_LIVE>
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

BENCH_DIR="/tmp/youtube-live-benchmark-$$"
mkdir -p "$BENCH_DIR"

usage() {
    echo "Usage: $(basename "$0") <URL_YOUTUBE_LIVE>"
    echo ""
    echo "  Lance une mesure comparative de latence entre :"
    echo "    1. watch.sh       (streamlink + mpv, mode standard)"
    echo "    2. watch-ultra.sh (streamlink + mpv, mode agressif)"
    echo "    3. watch-ytdlp.sh (yt-dlp direct + mpv)"
    echo ""
    echo "  OS détecté : $YLU_OS ($YLU_ARCH)"
    exit 1
}

[ $# -eq 0 ] && usage
URL="$1"

for tool in streamlink yt-dlp mpv; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}❌ $tool manquant${NC}"
        exit 1
    fi
done

run_bench() {
    local mode="$1"
    local logfile="$BENCH_DIR/${mode}.log"

    echo ""
    echo -e "${CYAN}━━━ Benchmark : ${BLUE}$mode${CYAN} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "  Lancement → 5s stabilisation → 25s mesure..."

    if [ "$mode" = "ytdlp-direct" ]; then
        HLS_URL=$(yt-dlp -g --format "best" "$URL" 2>/dev/null || true)
        [ -z "$HLS_URL" ] && { echo "  ${RED}✗ yt-dlp failed${NC}"; return 1; }
        mpv --profile=low-latency --cache=no --video-latency-hacks=yes \
            --length=30 --really-quiet --no-config "$HLS_URL" > "$logfile" 2>&1 &
        BENCH_PID=$!
    elif [ "$mode" = "streamlink-standard" ]; then
        streamlink --loglevel debug --hls-live-edge 2 --ringbuffer-size 64M \
            "$URL" best --player mpv --player-args "--profile=low-latency --length=30 --really-quiet --no-config" \
            > "$logfile" 2>&1 &
        BENCH_PID=$!
    elif [ "$mode" = "streamlink-ultra" ]; then
        streamlink --loglevel debug --hls-live-edge 1 --ringbuffer-size 128M --stream-segment-threads 4 \
            "$URL" best --player mpv --player-args "--profile=low-latency --length=30 --really-quiet --no-config" \
            > "$logfile" 2>&1 &
        BENCH_PID=$!
    fi

    sleep 5   # stabilisation
    sleep 20  # mesure

    kill $BENCH_PID 2>/dev/null || true
    wait $BENCH_PID 2>/dev/null || true

    local segments
    segments=$(grep -c "segment" "$logfile" 2>/dev/null || echo "0")
    echo "  → Segments HLS : $segments"

    echo "$mode|$segments" >> "$BENCH_DIR/results.txt"
}

echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        📊  BENCHMARK LATENCE — 3 MODES DE LECTURE       ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}URL  :${NC} $URL"
echo -e "${CYAN}OS   :${NC} $YLU_OS ($YLU_ARCH)"
echo -e "${CYAN}Date :${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

TITLE=$(yt-dlp --print title "$URL" 2>/dev/null || echo "N/A")
IS_LIVE=$(yt-dlp --print is_live "$URL" 2>/dev/null || echo "unknown")
echo "  Titre    : $TITLE"
echo "  En live  : $IS_LIVE"

if [ "$IS_LIVE" != "True" ]; then
    echo -e "${RED}⚠ Stream pas en live — benchmark annulé.${NC}"
    exit 1
fi

run_bench "streamlink-standard"
run_bench "streamlink-ultra"
run_bench "ytdlp-direct"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   📈  RÉSULTATS FINAUX                   ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"

printf "${GREEN}║${NC} %-18s | %8s ${GREEN}║${NC}\n" "Mode" "Segments"
echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"

while IFS='|' read -r mode segs; do
    printf "${GREEN}║${NC} %-18s | %8s ${GREEN}║${NC}\n" "$mode" "$segs"
done < "$BENCH_DIR/results.txt"

echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}💡 Logs détaillés : $BENCH_DIR/${NC}"
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
