#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — lib/ux.sh
# Patterns UX partagés : couleurs, spinner, help, version.
# Usage: source "$SCRIPT_DIR/lib/ux.sh"
# =============================================================================
# shellcheck disable=SC2034  # Variables exported for use by sourcing scripts

# ─── VERSION ─────────────────────────────────────────────────────────────────
YLU_VERSION="1.0.0"

# ─── COULEURS ────────────────────────────────────────────────────────────────
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_NC='\033[0m'

# ─── ICÔNES ──────────────────────────────────────────────────────────────────
ICON_OK="✓"
ICON_ERR="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_ROCKET="🚀"
ICON_WATCH="👀"
ICON_SHIELD="🛡️"

# ─── SPINNER ─────────────────────────────────────────────────────────────────
# Usage: spinner "Message..." &>/dev/null &  SPIN_PID=$!; ...long_task...; kill $SPIN_PID
spinner() {
    local msg="$1"
    local chars="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    while true; do
        for (( i=0; i<${#chars}; i++ )); do
            printf "\r  ${C_CYAN}%s${C_NC} %s" "${chars:$i:1}" "$msg"
            sleep 0.1
        done
    done
}

# ─── PROGRESS ────────────────────────────────────────────────────────────────
# Usage: progress "Étape 1/3" "Description..."
progress() {
    echo -e "  ${C_CYAN}→${C_NC} ${C_BOLD}$1${C_NC} $2"
}

success() {
    echo -e "  ${C_GREEN}${ICON_OK}${C_NC} $1"
}

fail() {
    echo -e "  ${C_RED}${ICON_ERR}${C_NC} $1"
}

warn_ux() {
    echo -e "  ${C_YELLOW}${ICON_WARN}${C_NC} $1"
}

# ─── HELP STANDARD ───────────────────────────────────────────────────────────
# Appeler depuis usage(): show_help "watch" "standard" "watch-ultra.sh"
show_help() {
    local script_name="$1"
    local mode="$2"
    local extra="${3:-}"

    echo -e "${C_BOLD}Usage:${C_NC} $script_name <URL_YOUTUBE_LIVE>"
    echo ""
    echo -e "  ${C_BOLD}Mode :${C_NC} $mode"
    if [ -n "$extra" ]; then
        echo "  $extra"
    fi
    echo ""
    echo -e "  ${C_DIM}OS détecté : $YLU_OS ($YLU_ARCH)${C_NC}"

    if [ -f "$SCRIPT_DIR/VERSION" ]; then
        echo -e "  ${C_DIM}Version    : $(cat "$SCRIPT_DIR/VERSION")${C_NC}"
    fi
    echo ""
    echo -e "${C_BOLD}Exemples :${C_NC}"
    echo "  $script_name https://www.youtube.com/watch?v=XXXXXXXXXXX"
    echo "  $script_name https://youtu.be/XXXXXXXXXXX"
    echo ""
    echo -e "${C_BOLD}Options :${C_NC}"
    echo "  -h, --help     Affiche cette aide"
    echo "  --version      Affiche la version"
    echo ""
    echo -e "${C_DIM}Pour une résilience maximale : watch-resilient.sh${C_NC}"
}

# ─── VERSION ─────────────────────────────────────────────────────────────────
show_version() {
    echo "youtube-live-ultra v$YLU_VERSION"
    echo "OS: $YLU_OS ($YLU_ARCH)"
    echo "GPU: $(mpv_hwdec_args)"
}

# ─── HEADER ──────────────────────────────────────────────────────────────────
print_header() {
    local title="$1"
    local subtitle="${2:-}"
    echo -e "${C_GREEN}╔══════════════════════════════════════════════════════════╗${C_NC}"
    printf "${C_GREEN}║${C_NC}  %-54s ${C_GREEN}║${C_NC}\n" "$title"
    if [ -n "$subtitle" ]; then
        printf "${C_GREEN}║${C_NC}  ${C_DIM}%-54s${C_NC} ${C_GREEN}║${C_NC}\n" "$subtitle"
    fi
    echo -e "${C_GREEN}╚══════════════════════════════════════════════════════════╝${C_NC}"
}

# ─── PARSER ARGUMENTS ────────────────────────────────────────────────────────
# Usage: parse_common_args "$@"  → définit URL et gère --help/--version
parse_common_args() {
    URL=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            --version)    show_version; exit 0 ;;
            *)            URL="$1"; shift ;;
        esac
    done
}
