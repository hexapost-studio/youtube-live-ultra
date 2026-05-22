#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — lib/platform.sh
# shellcheck disable=SC2034  # Variables exported for use by sourcing scripts
# =============================================================================
# Détection OS unifiée + helpers portables pour tous les scripts.
# Source ce fichier dans tous les scripts pour garantir la portabilité.
#
# Usage:
#   source "$(dirname "$0")/lib/platform.sh"   # depuis la racine
#   source "$(dirname "$0")/../lib/platform.sh" # depuis scripts/
# =============================================================================

# ─── Détection OS ────────────────────────────────────────────────────────────
export YLU_OS=""
export YLU_OS_FAMILY=""
export YLU_ARCH=""
export YLU_IS_MAC=false
export YLU_IS_LINUX=false
export YLU_IS_WSL=false
export YLU_IS_BSD=false
export YLU_IS_APPLE_SILICON=false
export YLU_IS_X86=false
export YLU_IS_ARM=false

_detect_os() {
    local uname_s
    uname_s=$(uname -s)
    YLU_ARCH=$(uname -m)

    case "$uname_s" in
        Darwin)
            YLU_OS="macos"
            YLU_OS_FAMILY="bsd"
            YLU_IS_MAC=true
            ;;
        Linux)
            YLU_OS="linux"
            YLU_OS_FAMILY="linux"
            YLU_IS_LINUX=true
            # Détecter WSL
            if grep -qi microsoft /proc/version 2>/dev/null; then
                YLU_IS_WSL=true
                YLU_OS="wsl"
            fi
            ;;
        *BSD|DragonFly)
            YLU_OS="bsd"
            YLU_OS_FAMILY="bsd"
            YLU_IS_BSD=true
            ;;
        MINGW*|MSYS*|CYGWIN*)
            YLU_OS="windows"
            YLU_OS_FAMILY="windows"
            ;;
        *)
            YLU_OS="unknown"
            YLU_OS_FAMILY="unknown"
            ;;
    esac

    # Architecture
    case "$YLU_ARCH" in
        arm64|aarch64) YLU_IS_ARM=true ;;
        x86_64|amd64|i*86) YLU_IS_X86=true ;;
    esac

    # Apple Silicon
    if $YLU_IS_MAC && [[ "$YLU_ARCH" == "arm64" ]]; then
        YLU_IS_APPLE_SILICON=true
    fi
}

_detect_os

# ─── Commandes portables ─────────────────────────────────────────────────────
# Au lieu d'appeler directement ifconfig/ip/networksetup, utiliser ces helpers.

# Récupérer la latence (ping portable)
# Usage: ping_latency <host> [count]
ping_latency() {
    local host="$1"
    local count="${2:-3}"
    # macOS et Linux supportent tous les deux -c et -q
    ping -c "$count" -q "$host" 2>/dev/null | tail -1 | awk -F '/' '{print $5}'
}

# Résoudre un hostname en IP
# Usage: resolve_host <hostname>
resolve_host() {
    if command -v dig >/dev/null 2>&1; then
        dig +short "$1" A 2>/dev/null | grep -E '^[0-9]' || true
    elif command -v host >/dev/null 2>&1; then
        host "$1" 2>/dev/null | grep "has address" | awk '{print $NF}' || true
    elif command -v getent >/dev/null 2>&1; then
        getent hosts "$1" 2>/dev/null | awk '{print $1}' || true
    elif command -v nslookup >/dev/null 2>&1; then
        nslookup "$1" 2>/dev/null | grep "Address:" | tail -1 | awk '{print $2}' || true
    fi
}

# Récupérer l'interface réseau par défaut
# Usage: default_iface
default_iface() {
    if $YLU_IS_MAC; then
        route -n get default 2>/dev/null | grep interface | awk '{print $2}'
    elif $YLU_IS_LINUX; then
        ip route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+' | head -1
    else
        route -n 2>/dev/null | grep '^0.0.0.0' | awk '{print $NF}' | head -1
    fi
}

# Vérifier si l'interface est WiFi
# Usage: is_wifi <iface>
is_wifi() {
    local iface="$1"
    if $YLU_IS_MAC; then
        networksetup -listallhardwareports 2>/dev/null | grep -A1 "$iface" | grep -qi "wi-fi"
    elif $YLU_IS_LINUX; then
        iw dev "$iface" info >/dev/null 2>&1
    else
        return 1
    fi
}

# Nombre de CPU cores
cpu_cores() {
    if $YLU_IS_MAC; then
        sysctl -n hw.ncpu 2>/dev/null
    elif $YLU_IS_LINUX; then
        nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo
    else
        echo "unknown"
    fi
}

# RAM totale en MB
total_ram_mb() {
    if $YLU_IS_MAC; then
        sysctl -n hw.memsize 2>/dev/null | awk '{print int($1/1024/1024)}'
    elif $YLU_IS_LINUX; then
        free -m 2>/dev/null | awk '/Mem:/ {print $2}'
    elif $YLU_IS_WSL; then
        free -m 2>/dev/null | awk '/Mem:/ {print $2}'
    else
        echo "0"
    fi
}

# Espace disque libre en MB
disk_free_mb() {
    local path="${1:-.}"
    df -m "$path" 2>/dev/null | tail -1 | awk '{print $4}'
}

# Récupérer l'IP publique (portable)
public_ip() {
    curl -s --max-time 3 https://ifconfig.me 2>/dev/null \
        || curl -s --max-time 3 https://api.ipify.org 2>/dev/null \
        || curl -s --max-time 3 https://icanhazip.com 2>/dev/null \
        || echo "unknown"
}

# Process renice (portable)
renice_process() {
    local priority="${1:--10}"
    if command -v renice >/dev/null 2>&1; then
        renice -n "$priority" -p $$ >/dev/null 2>&1 || true
    fi
}

# ─── Matériel : accélération vidéo ───────────────────────────────────────────
# Retourne les options mpv pour l'accélération matérielle
# Usage: mpv_hwdec_args
mpv_hwdec_args() {
    if $YLU_IS_APPLE_SILICON; then
        echo "--hwdec=videotoolbox --vo=gpu-next --gpu-api=metal --gpu-context=cocoa"
    elif $YLU_IS_MAC; then
        echo "--hwdec=videotoolbox --vo=libmpv"
    elif $YLU_IS_LINUX; then
        # Détecter VAAPI ou VDPAU
        if command -v vainfo >/dev/null 2>&1 && vainfo >/dev/null 2>&1; then
            echo "--hwdec=vaapi --vo=gpu-next --gpu-api=vulkan"
        elif command -v vdpauinfo >/dev/null 2>&1 && vdpauinfo >/dev/null 2>&1; then
            echo "--hwdec=vdpau --vo=gpu-next --gpu-api=vulkan"
        elif [ -e /dev/dri/renderD128 ]; then
            echo "--hwdec=vaapi --vo=gpu-next --gpu-api=vulkan"
        else
            echo "--hwdec=auto-safe --vo=gpu-next"
        fi
    elif $YLU_IS_WSL; then
        # WSL2 avec D3D12 → VAAPI via mesa
        echo "--hwdec=auto-safe --vo=gpu-next"
    else
        echo "--hwdec=auto-safe --vo=gpu-next"
    fi
}

# ─── Fichiers temporaires portables ──────────────────────────────────────────
# Usage: tmp_dir
tmp_dir() {
    if $YLU_IS_MAC; then
        echo "${TMPDIR:-/tmp}"
    else
        echo "${TMPDIR:-/tmp}"
    fi
}

# ─── sed portable ────────────────────────────────────────────────────────────
# macOS sed nécessite -i '' pour in-place, Linux sed nécessite -i
# Usage: sed_portable 's/old/new/' file
sed_portable() {
    if $YLU_IS_MAC; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ─── Chemins (XDG compliant) ─────────────────────────────────────────────────
# Config: ~/.config/youtube-live-ultra/
# Cache:  ~/.cache/youtube-live-ultra/
# Logs:   ~/.cache/youtube-live-ultra/logs/  (XDG: cache for non-essential data)
# Lock:   /tmp/youtube-live-ultra.lock        (must be world-writable)

_YLU_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
_YLU_XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

export YLU_CONFIG_DIR="${_YLU_XDG_CONFIG_HOME}/youtube-live-ultra"
export YLU_CACHE_DIR="${_YLU_XDG_CACHE_HOME}/youtube-live-ultra"
export YLU_LOG_DIR="${YLU_CACHE_DIR}/logs"
export YLU_LOCK_FILE="/tmp/youtube-live-ultra.lock"

# ─── Bannière debug ──────────────────────────────────────────────────────────
print_platform_info() {
    echo "OS:      $YLU_OS ($YLU_OS_FAMILY)"
    echo "Arch:    $YLU_ARCH"
    echo "CPU:     $(cpu_cores) cores"
    echo "RAM:     $(total_ram_mb) MB"
    echo "WSL:     $YLU_IS_WSL"
    echo "GPU:     $(mpv_hwdec_args)"
}

# Si le script est exécuté directement (pas sourcé), afficher les infos
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    print_platform_info
fi
