#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — watch-resilient.sh
# Launcher résilient unifié : self-healing, multi-backend, watchdog.
#
# Ce qui le rend résilient :
#   1. Pre-flight check : valide tout avant de lancer
#   2. Multi-backend    : yt-dlp → streamlink → fallback manuel
#   3. Watchdog         : redémarre mpv si crash/freeze
#   4. Exponential backoff : retry intelligent
#   5. Graceful cleanup : lock, logs, stats, exit propre
#   6. Signal handlers  : Ctrl-C = cleanup propre
#
# Compatible: macOS (Intel + Apple Silicon), Linux (X11 + Wayland), WSL2
# Usage: ./watch-resilient.sh <URL_YOUTUBE_LIVE> [--mode ultra|standard|direct]
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/platform.sh"
source "$SCRIPT_DIR/lib/ux.sh"

# ─── CONSTANTS ───────────────────────────────────────────────────────────────
readonly LOCK_FILE="$YLU_LOCK_FILE"
readonly LOG_DIR="$YLU_LOG_DIR"
readonly SESSION_ID="$$-$(date +%s)"
readonly MAX_RETRIES=10
readonly WATCHDOG_INTERVAL=3

mkdir -p "$LOG_DIR"

# ─── COLORS ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ─── GLOBALS ─────────────────────────────────────────────────────────────────
MPV_PID=""
WATCHDOG_PID=""
RETRY_COUNT=0
CURRENT_BACKEND=""
SHOULD_RESTART=true
CLEANUP_DONE=false
HLS_URL=""

# ─── USAGE ───────────────────────────────────────────────────────────────────
usage() {
    cat << EOF
Usage: $(basename "$0") <URL_YOUTUBE_LIVE> [--mode MODE]

  Launcher résilient pour YouTube Live. Gère automatiquement :
  - Multi-backend (yt-dlp / streamlink)
  - Redémarrage automatique si le stream coupe
  - Watchdog anti-freeze
  - Exponential backoff

  OS détecté : $YLU_OS ($YLU_ARCH)

Modes:
  ultra      Latence minimale (segments 1s, cache off)
  standard   Équilibré (défaut)
  direct     yt-dlp direct (le plus rapide si le stream est stable)

Exemples:
  $0 "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
  $0 "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --mode ultra
EOF
    exit 0
}

# ─── LOGGING ─────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local timestamp
    timestamp=$(date '+%H:%M:%S')
    echo -e "[${timestamp}] [${level}] $*" | tee -a "$LOG_DIR/session-${SESSION_ID}.log"
}

log_info()  { log "${GREEN}INFO${NC}" "$@"; }
log_warn()  { log "${YELLOW}WARN${NC}" "$@"; }
log_error() { log "${RED}ERROR${NC}" "$@"; }
log_fatal() { log_error "$@"; exit 1; }

# ─── CLEANUP ─────────────────────────────────────────────────────────────────
cleanup() {
    if $CLEANUP_DONE; then return; fi
    CLEANUP_DONE=true

    log_info "Cleanup..."

    if [ -n "$WATCHDOG_PID" ] && kill -0 "$WATCHDOG_PID" 2>/dev/null; then
        kill "$WATCHDOG_PID" 2>/dev/null || true
        wait "$WATCHDOG_PID" 2>/dev/null || true
    fi

    if [ -n "$MPV_PID" ] && kill -0 "$MPV_PID" 2>/dev/null; then
        kill -TERM "$MPV_PID" 2>/dev/null || true
        sleep 1
        kill -KILL "$MPV_PID" 2>/dev/null || true
    fi

    rm -f "$LOCK_FILE"
    log_info "Session terminée."
}

# ─── SETUP TRAP (appelé seulement quand le stream est lancé) ──────────────────
setup_trap() {
    trap cleanup EXIT INT TERM
}

# ─── LOCK ────────────────────────────────────────────────────────────────────
acquire_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local existing_pid
        existing_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        if kill -0 "$existing_pid" 2>/dev/null; then
            log_fatal "Une autre instance tourne déjà (PID: $existing_pid). Supprime $LOCK_FILE si c'est un stale lock."
        else
            log_warn "Stale lock trouvé (PID $existing_pid), suppression..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo "$SESSION_ID" > "$LOCK_FILE"
    log_info "Lock acquis: $LOCK_FILE"
}

# ─── PRE-FLIGHT ──────────────────────────────────────────────────────────────
preflight() {
    log_info "━━━ Pre-flight check ━━━"

    local missing=()
    for tool in mpv curl; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    if ! command -v yt-dlp >/dev/null 2>&1 && ! command -v streamlink >/dev/null 2>&1; then
        missing+=("yt-dlp ou streamlink")
    fi
    if [ ${#missing[@]} -gt 0 ]; then
        log_fatal "Dépendances manquantes: ${missing[*]}"
    fi
    log_info "  ✓ Dépendances OK"

    if ! curl -s --max-time 5 https://youtube.com >/dev/null 2>&1; then
        log_fatal "Pas d'accès à youtube.com"
    fi
    log_info "  ✓ Réseau OK"

    if command -v yt-dlp >/dev/null 2>&1; then
        local is_live
        is_live=$(yt-dlp --print is_live "$URL" 2>/dev/null || echo "unknown")
        case "$is_live" in
            True)  log_info "  ✓ Stream live détecté" ;;
            False) log_warn "  ⚠ Le stream ne semble pas être en live" ;;
            *)     log_warn "  ? Impossible de déterminer si le stream est live" ;;
        esac
    fi
}

# ─── BACKEND : RÉSOLUTION URL HLS ────────────────────────────────────────────
resolve_hls_url() {
    local url="$1"

    # Essai 1 : streamlink (ring buffer + meilleure résilience)
    if command -v streamlink >/dev/null 2>&1; then
        log_info "  Essai backend: streamlink..."
        HLS_URL=$(streamlink --stream-url "$url" best 2>/dev/null | head -1)
        if [ -n "$HLS_URL" ] && [[ "$HLS_URL" == http* ]]; then
            CURRENT_BACKEND="streamlink"
            log_info "  ✓ streamlink OK"
            return 0
        fi
    fi

    # Essai 2 : yt-dlp (plus rapide si streamlink bloqué)
    if command -v yt-dlp >/dev/null 2>&1; then
        log_info "  Essai backend: yt-dlp..."
        HLS_URL=$(yt-dlp -g --format "best" --no-playlist "$url" 2>/dev/null | head -1)
        if [ -n "$HLS_URL" ] && [[ "$HLS_URL" == http* ]]; then
            CURRENT_BACKEND="yt-dlp"
            log_info "  ✓ yt-dlp OK"
            return 0
        fi
    fi

    log_error "  ✗ Aucun backend n'a pu extraire l'URL HLS"
    return 1
}

# ─── MPV ARGS ────────────────────────────────────────────────────────────────
get_mpv_args() {
    local mode="$1"
    local hw_args
    hw_args=$(mpv_hwdec_args)

    local args=(
        --profile=low-latency
        --keep-open=no
        --force-window=yes
        --osc=no
        --really-quiet
    )

    case "$mode" in
        ultra|direct)
            args+=(
                --cache=no
                --demuxer-max-bytes=500K
                --demuxer-readahead-secs=0.05
                --video-latency-hacks=yes
                --framedrop=vo+decoder
                --video-sync=display-resample
                --vd-lavc-threads=6
                --audio-buffer=0.1
                --video-reversal-buffer=0
                --hls-live-edge=1
                --cache-secs=0
            )
            ;;
        standard|*)
            args+=(
                --cache=yes
                --demuxer-max-bytes=2M
                --demuxer-readahead-secs=0.2
                --video-latency-hacks=yes
                --framedrop=vo
                --video-sync=audio
                --vd-lavc-threads=4
                --audio-buffer=0.2
            )
            ;;
    esac

    read -ra HW_ARGS <<< "$hw_args"
    args+=("${HW_ARGS[@]}")

    echo "${args[@]}"
}

# ─── WATCHDOG (avec IPC health checks) ────────────────────────────────────────
# Surveille mpv via : (1) PID, (2) JSON IPC health checks (time-pos, cache)
watchdog() {
    local mpv_pid="$1"
    local ipc_socket="$2"

    log_info "Watchdog démarré (PID: $mpv_pid, IPC: $ipc_socket)"

    local last_time_pos=""
    local frozen_count=0

    while $SHOULD_RESTART; do
        sleep "$WATCHDOG_INTERVAL"

        # Check 1 : Processus vivant ?
        if ! kill -0 "$mpv_pid" 2>/dev/null; then
            wait "$mpv_pid" 2>/dev/null
            local exit_code=$?
            log_warn "mpv est mort (exit: $exit_code)"

            if [ "$exit_code" -eq 0 ]; then
                log_info "Arrêt normal. Fin du watchdog."
                SHOULD_RESTART=false
                return 0
            fi

            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ "$RETRY_COUNT" -gt "$MAX_RETRIES" ]; then
                log_fatal "Trop de redémarrages ($MAX_RETRIES). Abandon."
            fi

            restart_stream
            return $?
        fi

        # Check 2 : IPC health — mpv répond-il ? Le temps avance-t-il ?
        if [ -S "$ipc_socket" ]; then
            local time_pos
            time_pos=$(echo '{ "command": ["get_property", "time-pos"] }' | \
                socat - UNIX-CONNECT:"$ipc_socket" 2>/dev/null | \
                grep -o '"data":[0-9.]*' | cut -d: -f2 || echo "")

            if [ -n "$time_pos" ] && [ -n "$last_time_pos" ]; then
                if [ "$time_pos" = "$last_time_pos" ]; then
                    frozen_count=$((frozen_count + 1))
                    log_warn "mpv frozen? time-pos stagnant ($time_pos) — ${frozen_count}x"

                    if [ "$frozen_count" -ge 3 ]; then
                        log_error "mpv gelé depuis $((frozen_count * WATCHDOG_INTERVAL))s — restart"
                        kill -TERM "$mpv_pid" 2>/dev/null || true
                        sleep 1
                        kill -KILL "$mpv_pid" 2>/dev/null || true
                        RETRY_COUNT=$((RETRY_COUNT + 1))
                        restart_stream
                        return $?
                    fi
                else
                    frozen_count=0
                fi
            fi
            last_time_pos="$time_pos"

            # Check 3 : Cache qui gonfle (buffer underrun → restart)
            local cache_dur
            cache_dur=$(echo '{ "command": ["get_property", "demuxer-cache-duration"] }' | \
                socat - UNIX-CONNECT:"$ipc_socket" 2>/dev/null | \
                grep -o '"data":[0-9.]*' | cut -d: -f2 || echo "0")

            if [ -n "$cache_dur" ] && [ "$(echo "$cache_dur > 10" | bc -l 2>/dev/null || echo 0)" = "1" ]; then
                log_warn "Cache en hausse (${cache_dur}s) — possible buffer underrun"
            fi
        fi
    done
}

# ─── RESTART STREAM ──────────────────────────────────────────────────────────
restart_stream() {
    local backoff
    backoff=$(echo "scale=0; 2^($RETRY_COUNT-1)" | bc 2>/dev/null || echo "$RETRY_COUNT")
    [ "$backoff" -gt 60 ] && backoff=60

    log_warn "Redémarrage #$RETRY_COUNT dans ${backoff}s..."

    if [ "$RETRY_COUNT" -ge 3 ]; then
        log_info "Rotation de stratégie après $RETRY_COUNT échecs..."
        HLS_URL=""
    fi

    sleep "$backoff"

    if ! resolve_hls_url "$URL"; then
        log_error "Échec de résolution HLS"
        RETRY_COUNT=$((RETRY_COUNT + 1))
        restart_stream
        return
    fi

    launch_mpv "$MODE"
}

# ─── LAUNCH MPV ──────────────────────────────────────────────────────────────
launch_mpv() {
    local mode="$1"
    local mpv_args
    mpv_args=$(get_mpv_args "$mode")
    local ipc_socket="/tmp/mpv-socket-$$"

    log_info "Lancement mpv (backend: $CURRENT_BACKEND, mode: $mode)"
    log_info "  URL: $(echo "$HLS_URL" | cut -c1-80)..."

    # Lancer mpv avec serveur IPC pour le watchdog
    # shellcheck disable=SC2086
    mpv --input-ipc-server="$ipc_socket" $mpv_args "$HLS_URL" &
    MPV_PID=$!

    log_info "mpv PID: $MPV_PID, IPC: $ipc_socket"

    sleep 2
    if ! kill -0 "$MPV_PID" 2>/dev/null; then
        log_error "mpv n'a pas survécu au démarrage"
        rm -f "$ipc_socket"
        RETRY_COUNT=$((RETRY_COUNT + 1))
        restart_stream
        return
    fi

    watchdog "$MPV_PID" "$ipc_socket" &
    WATCHDOG_PID=$!

    wait "$MPV_PID" 2>/dev/null || true
    rm -f "$ipc_socket"
}

# ─── MAIN ────────────────────────────────────────────────────────────────────
main() {
    URL=""
    MODE="standard"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --mode) MODE="$2"; shift 2 ;;
            --help|-h) usage ;;
            *) URL="$1"; shift ;;
        esac
    done

    [ -z "$URL" ] && usage

    case "$MODE" in
        ultra|standard|direct) ;;
        *) log_fatal "Mode invalide: $MODE (ultra, standard, direct)" ;;
    esac

    print_header "${ICON_SHIELD}  YouTube Live — Mode Résilient" "Self-healing · Multi-backend · Watchdog IPC"

    setup_trap
    acquire_lock
    preflight

    echo ""
    log_info "━━━ Configuration ━━━"
    log_info "  URL   : $URL"
    log_info "  Mode  : $MODE"
    log_info "  OS    : $YLU_OS ($YLU_ARCH)"
    log_info "  GPU   : $(mpv_hwdec_args)"
    log_info "  Logs  : $LOG_DIR/session-${SESSION_ID}.log"
    echo ""

    log_info "━━━ Résolution du flux ━━━"
    if ! resolve_hls_url "$URL"; then
        log_fatal "Impossible de résoudre l'URL HLS"
    fi

    renice_process -15

    echo ""
    log_info "━━━ Lancement ━━━"
    echo ""
    echo -e "${YELLOW}  Touches : q=quitter  f=plein écran  Shift+I=stats${NC}"
    echo -e "${YELLOW}  Le watchdog redémarrera automatiquement en cas de crash.${NC}"
    echo ""

    launch_mpv "$MODE"
}

main "$@"
