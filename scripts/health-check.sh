#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — health-check.sh
# Valide l'ensemble du pipeline avant de lancer un live.
# Détecte les problèmes AVANT qu'ils ne surviennent pendant le stream.
#
# Compatible: macOS, Linux, WSL2
# Usage: ./scripts/health-check.sh <URL_YOUTUBE_LIVE>
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

check() {
    local name="$1"; shift
    if "$@"; then
        echo -e "  ${GREEN}✓${NC} $name"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $name"
        FAIL=$((FAIL + 1))
    fi
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARN=$((WARN + 1))
}

echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           🩺  HEALTH CHECK — YOUTUBE LIVE ULTRA         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}OS : $YLU_OS ($YLU_ARCH)${NC}"
echo ""

# ─── 1. DÉPENDANCES ──────────────────────────────────────────────────────────
echo -e "${CYAN}[1/7] Dépendances${NC}"

check "mpv installé"             command -v mpv >/dev/null 2>&1
if command -v mpv >/dev/null 2>&1; then
    MPV_VER=$(mpv --version 2>/dev/null | head -1 || echo "unknown")
    echo -e "       → $MPV_VER"
    check "mpv --hwdec"          mpv --hwdec=help 2>/dev/null | grep -qE 'videotoolbox|vaapi|vdpau|auto' || true
fi

check "streamlink installé"      command -v streamlink >/dev/null 2>&1
check "yt-dlp installé"          command -v yt-dlp >/dev/null 2>&1
check "curl installé"            command -v curl >/dev/null 2>&1
check "DNS resolver"             command -v dig >/dev/null 2>&1 || command -v host >/dev/null 2>&1 || command -v nslookup >/dev/null 2>&1

# ─── 2. RÉSEAU ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/7] Réseau${NC}"

check "Connexion internet"       curl -s --max-time 5 https://youtube.com >/dev/null 2>&1
check "DNS fonctionnel"          resolve_host youtube.com >/dev/null 2>&1

YT_PING=$(ping_latency youtube.com 3)
if [ "$YT_PING" != "" ] && [ "$YT_PING" != "N/A" ]; then
    if [ "$(echo "$YT_PING < 30" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        check "Ping YouTube (${YT_PING}ms)" true
    elif [ "$(echo "$YT_PING < 100" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
        warn "Ping YouTube (${YT_PING}ms) — acceptable"
    else
        warn "Ping YouTube (${YT_PING}ms) — élevé"
    fi
fi

# WiFi check
iface=$(default_iface)
if [ -n "$iface" ] && is_wifi "$iface" 2>/dev/null; then
    warn "WiFi détecté (${iface}) — Ethernet recommandé"
else
    check "Connexion filaire" true
fi

# ─── 3. MATÉRIEL ─────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[3/7] Matériel${NC}"

echo -e "       OS    : $YLU_OS"
echo -e "       Arch  : $YLU_ARCH"
echo -e "       CPU   : $(cpu_cores) cœurs"
echo -e "       RAM   : $(total_ram_mb) MB"

if $YLU_IS_APPLE_SILICON; then
    check "Apple Silicon" true
elif $YLU_IS_ARM; then
    warn "ARM détecté (non Apple) — performances de décodeur inconnues"
else
    check "Architecture x86_64" true
fi

# GPU / hwdec
HW_DEC=$(mpv_hwdec_args)
echo -e "       GPU   : $HW_DEC"
if echo "$HW_DEC" | grep -q "auto-safe"; then
    warn "Pas d'accélération matérielle détectée — latence de décodeur plus élevée"
else
    check "Accélération matérielle" true
fi

# ─── 4. STREAM ────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[4/7] Vérification du stream${NC}"

URL="${1:-}"
if [ -z "$URL" ]; then
    warn "Pas d'URL fournie"
else
    if command -v yt-dlp >/dev/null 2>&1; then
        IS_LIVE=$(yt-dlp --print is_live "$URL" 2>/dev/null || echo "unknown")
        case "$IS_LIVE" in
            True)  check "Stream live actif" true ;;
            False) warn "Stream pas en live actuellement" ;;
            *)     warn "Impossible de vérifier le statut live" ;;
        esac
        TITLE=$(yt-dlp --print title "$URL" 2>/dev/null || echo "N/A")
        echo -e "       Titre : $TITLE"
    fi

    if command -v streamlink >/dev/null 2>&1; then
        if streamlink --stream-url "$URL" best >/dev/null 2>&1; then
            check "Streamlink OK" true
        else
            warn "Streamlink ne peut pas extraire"
        fi
    fi

    if command -v yt-dlp >/dev/null 2>&1; then
        if yt-dlp -g --format best "$URL" >/dev/null 2>&1; then
            check "yt-dlp OK" true
        else
            warn "yt-dlp ne peut pas extraire"
        fi
    fi
fi

# ─── 5. DISQUE ───────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[5/7] Espace disque${NC}"

DISK_FREE=$(disk_free_mb .)
echo -e "       Libre : ${DISK_FREE}MB"
if [ "$DISK_FREE" -lt 500 ] 2>/dev/null; then
    warn "Moins de 500MB"
else
    check "Espace disque OK" true
fi

# ─── 6. CONFLITS ─────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[6/7] Conflits potentiels${NC}"

if [ -f "$YLU_LOCK_FILE" ]; then
    LOCK_PID=$(cat "$YLU_LOCK_FILE" 2>/dev/null | cut -d- -f1 || echo "unknown")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        warn "Une autre instance tourne (PID: $LOCK_PID)"
    else
        check "Pas de stale lock" true
    fi
else
    check "Pas de lock existant" true
fi

# Apps lourdes (cross-platform)
HEAVY_APPS=""
for app in "chrome" "docker" "code" "slack" "discord"; do
    if pgrep -i "$app" >/dev/null 2>&1; then
        HEAVY_APPS="$HEAVY_APPS $app"
    fi
done
if [ -n "$HEAVY_APPS" ]; then
    warn "Apps lourdes :$HEAVY_APPS"
else
    check "Pas d'apps lourdes" true
fi

# ─── 7. BANDWIDTH ────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[7/7] Bande passante${NC}"

SPEED=$(curl -s -o /dev/null -w '%{speed_download}' --max-time 10 \
    "https://storage.googleapis.com/gcp-is-awesome/speed-test/test-1mb.dat" 2>/dev/null || echo "0")
SPEED_MBPS=$(echo "scale=1; $SPEED * 8 / 1000000" | bc 2>/dev/null || echo "0")
echo -e "       Débit : ${SPEED_MBPS} Mbps"

# ─── RÉSUMÉ ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  RÉSUMÉ : ${GREEN}✓ $PASS OK${NC}  ${RED}✗ $FAIL échecs${NC}  ${YELLOW}⚠ $WARN warnings${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}✅ Pipeline OK.${NC}"
else
    echo -e "${RED}❌ $FAIL problème(s) critique(s).${NC}"
fi

exit $FAIL
