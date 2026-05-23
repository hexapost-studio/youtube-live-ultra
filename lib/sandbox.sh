#!/usr/bin/env bash
# =============================================================================
# youtube-live-ultra — lib/sandbox.sh
# Isolation légère pour mpv : macOS (sandbox-exec), Linux (firejail/bwrap).
# Usage: source "$SCRIPT_DIR/lib/sandbox.sh"
# =============================================================================

# ─── DÉTECTION ───────────────────────────────────────────────────────────────
SANDBOX_AVAILABLE=false
SANDBOX_METHOD=""

_detect_sandbox() {
    if $YLU_IS_MAC; then
        if command -v sandbox-exec >/dev/null 2>&1; then
            SANDBOX_AVAILABLE=true
            SANDBOX_METHOD="sandbox-exec"
        fi
    elif $YLU_IS_LINUX; then
        if command -v firejail >/dev/null 2>&1; then
            SANDBOX_AVAILABLE=true
            SANDBOX_METHOD="firejail"
        elif command -v bwrap >/dev/null 2>&1; then
            SANDBOX_AVAILABLE=true
            SANDBOX_METHOD="bwrap"
        fi
    fi
}

_detect_sandbox

# ─── SANDBOX PROFILES ────────────────────────────────────────────────────────

# macOS sandbox-exec profile (minimal, allow network + GPU + audio + IPC)
_macos_sandbox_profile() {
    cat << 'SANDBOX_PROFILE'
(version 1)
(allow default)
(deny file-write*)
(allow file-write* (subpath "/tmp"))
(allow file-write* (subpath (param "IPC_SOCKET_DIR")))
(allow network*)
(allow process-exec (literal "/bin/bash"))
(allow process-exec (literal "/usr/bin/socat"))
(allow sysctl-read)
(allow mach-lookup)
(allow iokit-open)
(allow device-camera)
(allow device-microphone)
SANDBOX_PROFILE
}

# ─── WRAPPERS ────────────────────────────────────────────────────────────────

# Enveloppe une commande dans le sandbox approprié.
# Usage: sandbox_wrap [--ipc-socket PATH] command args...
sandbox_wrap() {
    local ipc_socket=""
    if [ "$1" = "--ipc-socket" ]; then
        ipc_socket="$2"
        shift 2
    fi

    if ! $SANDBOX_AVAILABLE; then
        # Pas de sandbox → exécution directe
        "$@"
        return $?
    fi

    case "$SANDBOX_METHOD" in
        sandbox-exec)
            local profile
            profile=$(_macos_sandbox_profile)
            sandbox-exec -p "$profile" \
                -D "IPC_SOCKET_DIR=$(dirname "${ipc_socket:-/tmp}")" \
                "$@"
            ;;
        firejail)
            firejail --quiet \
                --net=none \
                --noprofile \
                --caps.drop=all \
                --nonewprivs \
                --seccomp \
                --read-only=/ \
                --tmpfs=/tmp \
                ${ipc_socket:+--whitelist="$(dirname "$ipc_socket")"} \
                --allow-debuggers \
                "$@"
            ;;
        bwrap)
            bwrap \
                --ro-bind /usr /usr \
                --ro-bind /lib /lib \
                --ro-bind /lib64 /lib64 \
                --ro-bind /bin /bin \
                --ro-bind /etc /etc \
                --ro-bind /opt /opt \
                --dev /dev \
                --dev-bind /dev/dri /dev/dri \
                --tmpfs /tmp \
                --unshare-all \
                --share-net \
                --die-with-parent \
                ${ipc_socket:+--bind "$(dirname "$ipc_socket")" "$(dirname "$ipc_socket")"} \
                "$@"
            ;;
    esac
}

# Enveloppe mpv spécifiquement (gère l'IPC socket automatiquement)
# Usage: sandbox_mpv [mpv_args...] URL
sandbox_mpv() {
    local args=("$@")
    local ipc_socket=""
    
    # Extraire l'IPC socket si présente dans les args
    for i in "${!args[@]}"; do
        if [[ "${args[$i]}" == --input-ipc-server=* ]]; then
            ipc_socket="${args[$i]#--input-ipc-server=}"
            break
        fi
    done

    sandbox_wrap ${ipc_socket:+--ipc-socket "$ipc_socket"} mpv "${args[@]}"
}

# Version pour streamlink (qui appelle mpv en sous-processus)
# Usage: sandbox_streamlink [streamlink_args...]
sandbox_streamlink() {
    if ! $SANDBOX_AVAILABLE; then
        streamlink "$@"
        return $?
    fi

    case "$SANDBOX_METHOD" in
        sandbox-exec)
            local profile
            profile=$(_macos_sandbox_profile)
            sandbox-exec -p "$profile" streamlink "$@"
            ;;
        firejail)
            firejail --quiet --net=none --noprofile --caps.drop=all \
                --nonewprivs --seccomp --tmpfs=/tmp streamlink "$@"
            ;;
        bwrap)
            bwrap --ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /lib64 /lib64 \
                --ro-bind /bin /bin --ro-bind /etc /etc --ro-bind /opt /opt \
                --dev /dev --dev-bind /dev/dri /dev/dri --tmpfs /tmp \
                --unshare-all --share-net --die-with-parent streamlink "$@"
            ;;
    esac
}

# ─── INFO ────────────────────────────────────────────────────────────────────
sandbox_status() {
    if $SANDBOX_AVAILABLE; then
        echo "Sandbox: $SANDBOX_METHOD ✓"
    else
        echo "Sandbox: non disponible (installe firejail ou bwrap sur Linux)"
    fi
}
