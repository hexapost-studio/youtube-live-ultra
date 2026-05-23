#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — install.sh
# Installeur interactif : choisis les composants que tu veux.
#
# Usage:
#   ./install.sh              → Mode interactif (questions)
#   ./install.sh --all        → Installation complète
#   ./install.sh --cli        → CLI uniquement (minimal)
#   ./install.sh --dashboard  → CLI + Dashboard Web
#   ./install.sh --tui        → CLI + TUI
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

# ─── DÉTECTION PACKAGE MANAGER ───────────────────────────────────────────────
detect_pkg_manager() {
    if $YLU_IS_MAC; then
        if command -v brew >/dev/null 2>&1; then
            PKG="brew install"
        else
            echo -e "${C_RED}Homebrew non trouvé. Installe : https://brew.sh${C_NC}"
            exit 1
        fi
    elif $YLU_IS_LINUX; then
        if command -v apt-get >/dev/null 2>&1; then
            PKG="sudo apt-get install -y"
        elif command -v pacman >/dev/null 2>&1; then
            PKG="sudo pacman -S --noconfirm"
        elif command -v dnf >/dev/null 2>&1; then
            PKG="sudo dnf install -y"
        else
            echo -e "${C_RED}Aucun package manager trouvé${C_NC}"
            exit 1
        fi
    elif $YLU_IS_WSL; then
        PKG="sudo apt-get install -y"
    else
        echo -e "${C_RED}OS non supporté : $YLU_OS${C_NC}"
        exit 1
    fi
}

# ─── DÉPENDANCES PAR TIER ────────────────────────────────────────────────────
DEPS_CLI="streamlink mpv yt-dlp curl"
DEPS_RESILIENCE="socat bc"                    # socat pour mpv IPC
DEPS_DASHBOARD="python3"                       # flask installé via pip
DEPS_TUI="dialog"                              # pour le TUI

check_dep() {
    local name="$1"
    case "$name" in
        streamlink) command -v streamlink >/dev/null 2>&1 ;;
        mpv)        command -v mpv >/dev/null 2>&1 ;;
        yt-dlp)     command -v yt-dlp >/dev/null 2>&1 ;;
        curl)       command -v curl >/dev/null 2>&1 ;;
        socat)      command -v socat >/dev/null 2>&1 ;;
        bc)         command -v bc >/dev/null 2>&1 ;;
        python3)    command -v python3 >/dev/null 2>&1 ;;
        dialog)     command -v dialog >/dev/null 2>&1 ;;
    esac
}

install_dep() {
    local name="$1"
    if ! check_dep "$name"; then
        echo -e "  ${C_YELLOW}Installation de $name...${C_NC}"
        $PKG "$name" 2>&1 | tail -1
    else
        echo -e "  ${C_GREEN}✓${C_NC} $name déjà installé"
    fi
}

install_pip() {
    local name="$1"
    if ! python3 -c "import ${name//-/_}" 2>/dev/null; then
        echo -e "  ${C_YELLOW}Installation de $name (pip)...${C_NC}"
        pip3 install "$name" 2>&1 | tail -1
    else
        echo -e "  ${C_GREEN}✓${C_NC} $name déjà installé"
    fi
}

# ─── INSTALLATION COMPOSANTS ─────────────────────────────────────────────────

install_cli() {
    print_header "📦 YouTube Live Ultra — CLI" "Installation minimale"
    echo ""
    echo -e "${C_CYAN}Dépendances :${C_NC}"
    for dep in $DEPS_CLI; do
        install_dep "$dep"
    done
    echo ""
    echo -e "${C_GREEN}✓ CLI installé.${C_NC}"
    echo "  Lance : ./watch.sh <URL>"
}

install_resilience() {
    echo ""
    echo -e "${C_CYAN}Dépendances résilience :${C_NC}"
    for dep in $DEPS_RESILIENCE; do
        install_dep "$dep"
    done
    echo ""
    echo -e "${C_GREEN}✓ Résilience installée.${C_NC}"
    echo "  Lance : ./watch-resilient.sh <URL> --mode ultra"
}

install_dashboard() {
    echo ""
    echo -e "${C_CYAN}Dépendances dashboard :${C_NC}"
    for dep in $DEPS_DASHBOARD; do
        install_dep "$dep"
    done
    install_pip "flask"
    install_pip "flask-sock"
    echo ""
    echo -e "${C_GREEN}✓ Dashboard installé.${C_NC}"
    echo "  Lance : ./watch-dashboard.sh <URL>"
    echo "  Ouvre : http://localhost:9191"
}

install_tui() {
    echo ""
    echo -e "${C_CYAN}Dépendances TUI :${C_NC}"
    for dep in $DEPS_TUI; do
        install_dep "$dep"
    done
    echo ""
    echo -e "${C_GREEN}✓ TUI installé.${C_NC}"
    echo "  Lance : ./watch-tui.sh <URL>"
}

# ─── MENU INTERACTIF ─────────────────────────────────────────────────────────

interactive_menu() {
    print_header "📦 YouTube Live Ultra — Installeur" "v$YLU_VERSION · $YLU_OS ($YLU_ARCH)"
    echo ""
    echo "  Choisis les composants à installer :"
    echo ""
    echo "  [1] 🎬 CLI Pure         (~50 MB)  watch.sh + watch-ultra.sh"
    echo "  [2] 🛡️  + Résilience     (+5 MB)   watch-resilient.sh, watchdog IPC"
    echo "  [3] 🌐 + Dashboard Web   (+15 MB)  Stats, chat, contrôles (localhost:9191)"
    echo "  [4] 🖥️  + TUI             (+3 MB)   Interface terminal interactive"
    echo "  [5] 🚀 TOUT installer    (~70 MB)  Complet"
    echo "  [0] Quitter"
    echo ""
    read -r -p "  Ton choix [1-5] : " choice

    case "$choice" in
        1) install_cli ;;
        2) install_cli; install_resilience ;;
        3) install_cli; install_resilience; install_dashboard ;;
        4) install_cli; install_resilience; install_tui ;;
        5) install_cli; install_resilience; install_dashboard; install_tui ;;
        0) echo "  Au revoir !"; exit 0 ;;
        *) echo -e "  ${C_RED}Choix invalide${C_NC}"; interactive_menu ;;
    esac
}

# ─── INSTALLATION SYSTÈME ────────────────────────────────────────────────────

install_system() {
    local bindir="${PREFIX:-/usr/local/bin}"
    echo ""
    echo -e "${C_CYAN}Installation système dans $bindir ...${C_NC}"
    
    mkdir -p "$bindir"
    for script in watch.sh watch-ultra.sh watch-ytdlp.sh watch-resilient.sh watch-dashboard.sh; do
        if [ -f "$SCRIPT_DIR/$script" ]; then
            cp "$SCRIPT_DIR/$script" "$bindir/youtube-live-$(basename "$script")"
            chmod 755 "$bindir/youtube-live-$(basename "$script")"
            echo -e "  ${C_GREEN}✓${C_NC} $bindir/youtube-live-$(basename "$script")"
        fi
    done
    
    mkdir -p "$YLU_CONFIG_DIR"
    cp "$SCRIPT_DIR/config/mpv.conf" "$YLU_CONFIG_DIR/mpv.conf" 2>/dev/null || true
    echo -e "  ${C_GREEN}✓${C_NC} Config: $YLU_CONFIG_DIR/"
    
    echo ""
    echo -e "${C_GREEN}✅ Installation système terminée.${C_NC}"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────

main() {
    detect_pkg_manager
    
    case "${1:-}" in
        --all)
            install_cli; install_resilience; install_dashboard
            install_system
            ;;
        --cli)
            install_cli
            ;;
        --dashboard)
            install_cli; install_resilience; install_dashboard
            install_system
            ;;
        --tui)
            install_cli; install_resilience; install_tui
            install_system
            ;;
        --system)
            install_system
            ;;
        *)
            interactive_menu
            ;;
    esac
    
    echo ""
    print_header "✅ Installation terminée" ""
    echo ""
    echo "  Pour commencer :"
    echo "    ./scripts/health-check.sh '<URL>'   # Vérifie le pipeline"
    echo "    ./watch-dashboard.sh '<URL>'        # Dashboard web"
    echo "    ./watch.sh '<URL>'                  # CLI pur"
    echo ""
}

main "$@"
