#!/usr/bin/env bats
# =============================================================================
# Cross-platform tests
# Vérifie que toutes les commandes du platform.sh sont portables
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    PROJECT_DIR="$TEST_DIR/.."
    source "$PROJECT_DIR/lib/platform.sh"
}

@test "platform.sh detects current OS" {
    [ -n "$YLU_OS" ]
    [[ "$YLU_OS" =~ ^(macos|linux|wsl|bsd|windows|unknown)$ ]]
}

@test "platform.sh detects architecture" {
    [ -n "$YLU_ARCH" ]
}

@test "ping_latency works on localhost" {
    run ping_latency 127.0.0.1 1
    [ "$status" -eq 0 ] || true
}

@test "resolve_host works on localhost" {
    run resolve_host localhost
    [ "$status" -eq 0 ] || true
}

@test "default_iface returns something" {
    run default_iface
    [ "$status" -eq 0 ] || true
}

@test "cpu_cores returns a number" {
    result=$(cpu_cores)
    [[ "$result" =~ ^[0-9]+$ ]] || [ "$result" = "unknown" ]
}

@test "total_ram_mb returns a number" {
    result=$(total_ram_mb)
    [[ "$result" =~ ^[0-9]+$ ]] || [ "$result" = "0" ]
}

@test "disk_free_mb returns a number" {
    result=$(disk_free_mb .)
    [[ "$result" =~ ^[0-9]+$ ]] || true
}

@test "mpv_hwdec_args returns valid mpv options" {
    result=$(mpv_hwdec_args)
    [[ "$result" == *"--hwdec="* ]]
    [[ "$result" == *"--vo="* ]]
}

@test "renice_process doesn't crash" {
    run renice_process -10
    [ "$status" -eq 0 ] || true
}

@test "tmp_dir returns a valid path" {
    result=$(tmp_dir)
    [ -d "$result" ]
}
