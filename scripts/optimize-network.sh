#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — optimize-network.sh
# Recommandations réseau pour minimiser la latence vers YouTube CDN.
# À exécuter AVANT de lancer un live.
#
# Note: Le TCP tuning manuel est INEFFICACE sur les OS modernes (auto-tuning).
#       Les vrais leviers sont : DNS rapide, Ethernet > WiFi, pas d'apps concurrentes.
#
# Compatible: macOS, Linux, WSL2
# Usage: ./scripts/optimize-network.sh
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/../lib/platform.sh"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           🌐  DIAGNOSTIC RÉSEAU LIVE YOUTUBE            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}OS détecté : $YLU_OS ($YLU_ARCH)${NC}"
echo ""

# ─── 1. DNS ──────────────────────────────────────────────────────────────────
echo -e "${CYAN}[1/4] DNS : quel résolveur est le plus rapide ?${NC}"

fastest_dns=""
fastest_time=9999

for dns in "1.1.1.1" "8.8.8.8" "9.9.9.9"; do
    time=$(ping_latency "$dns" 1 2>/dev/null || echo "9999")
    time=$(echo "$time" | cut -d. -f1)
    printf "  %-18s → %sms" "$dns" "$time"
    if [ "$time" != "9999" ] && [ "$time" != "" ] && [ "$time" -lt "$fastest_time" ] 2>/dev/null; then
        fastest_time=$time
        fastest_dns=$dns
        echo -e " ${GREEN}✓${NC}"
    else
        echo ""
    fi
done

echo ""
if [ -n "$fastest_dns" ]; then
    echo -e "${GREEN}  → DNS le plus rapide : $fastest_dns (${fastest_time}ms)${NC}"
    echo -e "  Configure ton routeur ou DHCP pour utiliser ce DNS."
else
    echo -e "${YELLOW}  Aucun DNS atteignable${NC}"
fi

# ─── 2. LATENCE CDN ──────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[2/4] Latence vers les CDN YouTube...${NC}"

for endpoint in "youtube.com" "googlevideo.com"; do
    latency=$(ping_latency "$endpoint" 3)
    printf "  %-20s → %sms\n" "$endpoint" "$latency"
done

echo ""
echo -e "${YELLOW}  ℹ️  Google CDN utilise GeoDNS + Anycast. Ton trafic est déjà routé${NC}"
echo -e "${YELLOW}     automatiquement vers l'edge le plus proche. Ne PAS modifier /etc/hosts.${NC}"

# ─── 3. INTERFACE ────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[3/4] Interface réseau...${NC}"

iface=$(default_iface)
echo "  Interface : ${iface:-inconnue}"

if [ -n "$iface" ] && is_wifi "$iface" 2>/dev/null; then
    echo -e "  ${YELLOW}⚠ WiFi détecté → +5-30ms de jitter vs Ethernet${NC}"
    echo -e "  ${YELLOW}  Pour du live, branche un câble Ethernet si possible.${NC}"

    # AWDL sur macOS (interférences AirDrop/AirPlay)
    if $YLU_IS_MAC && [ "$(id -u)" -eq 0 ] 2>/dev/null; then
        if ifconfig awdl0 >/dev/null 2>&1; then
            ifconfig awdl0 down 2>/dev/null \
                && echo -e "  ${GREEN}AWDL désactivé (AirDrop/AirPlay)${NC}" \
                || true
        fi
    elif $YLU_IS_MAC; then
        echo -e "  ${YELLOW}sudo ./scripts/optimize-network.sh pour désactiver AWDL${NC}"
    fi

    # WiFi Power Save sur Linux
    if $YLU_IS_LINUX && [ "$(id -u)" -eq 0 ] 2>/dev/null && command -v iw >/dev/null 2>&1; then
        iw dev "$iface" set power_save off 2>/dev/null \
            && echo -e "  ${GREEN}WiFi Power Save désactivé${NC}" \
            || true
    fi
else
    echo -e "  ${GREEN}✓ Interface filaire — latence optimale${NC}"
fi

# ─── 4. APPLICATIONS ─────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}[4/4] Applications consommatrices de bande passante...${NC}"

HEAVY_APPS=""
for app in "chrome" "firefox" "docker" "slack" "discord" "spotify" "dropbox"; do
    if pgrep -i "$app" >/dev/null 2>&1; then
        HEAVY_APPS="$HEAVY_APPS $app"
    fi
done
if [ -n "$HEAVY_APPS" ]; then
    echo -e "  ${YELLOW}⚠ Apps détectées :$HEAVY_APPS${NC}"
    echo -e "  ${YELLOW}  Ferme-les pour libérer la bande passante.${NC}"
else
    echo -e "  ${GREEN}✓ Pas d'apps concurrentes${NC}"
fi

# ─── RÉSUMÉ ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Résumé — pour la latence la plus basse :${NC}"
echo "  1. DNS rapide (${fastest_dns:-1.1.1.1})"
echo "  2. Ethernet > WiFi"
echo "  3. Fermer les apps lourdes"
echo "  4. Lance : ./watch-resilient.sh <URL> --mode ultra"
echo -e "${GREEN}════════════════════════════════════════════════════════════${NC}"
