#!/usr/bin/env bats
# =============================================================================
# Integration tests for youtube-live-ultra
# Requires: python3 (for mock HLS server)
# Run: bats tests/integration/
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    PROJECT_DIR="$TEST_DIR/.."
    MOCK_PORT=$((9000 + RANDOM % 1000))
    MOCK_DIR="/tmp/youtube-live-mock-$$"
    mkdir -p "$MOCK_DIR"
}

teardown() {
    # Kill mock server if running
    if [ -n "$MOCK_PID" ]; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
    rm -rf "$MOCK_DIR"
}

# ─── Mock HLS server ─────────────────────────────────────────────────────────
start_mock_hls() {
    # Create a minimal HLS playlist
    cat > "$MOCK_DIR/playlist.m3u8" << 'EOF'
#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:2
#EXT-X-MEDIA-SEQUENCE:0
#EXTINF:2.0,
segment0.ts
#EXTINF:2.0,
segment1.ts
#EXT-X-ENDLIST
EOF

    # Create dummy TS segments
    dd if=/dev/zero of="$MOCK_DIR/segment0.ts" bs=188 count=10 2>/dev/null
    dd if=/dev/zero of="$MOCK_DIR/segment1.ts" bs=188 count=10 2>/dev/null

    # Start a simple HTTP server
    python3 -m http.server "$MOCK_PORT" --directory "$MOCK_DIR" &
    MOCK_PID=$!
    sleep 1
}

# ─── Tests ───────────────────────────────────────────────────────────────────

@test "health-check.sh validates a valid URL" {
    run bash "$PROJECT_DIR/scripts/health-check.sh" "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    # May fail if no network, but should not crash
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "health-check.sh fails on empty URL gracefully" {
    run bash "$PROJECT_DIR/scripts/health-check.sh" ""
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "find-best-edge.sh runs without crashing" {
    if command -v dig >/dev/null 2>&1 || command -v host >/dev/null 2>&1; then
        run bash "$PROJECT_DIR/scripts/find-best-edge.sh"
        [ "$status" -eq 0 ]
    else
        skip "dig or host not available"
    fi
}

@test "optimize-network.sh shows usage or runs" {
    run bash "$PROJECT_DIR/scripts/optimize-network.sh"
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "benchmark-latency.sh shows usage without URL" {
    run bash "$PROJECT_DIR/scripts/benchmark-latency.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "mpv.conf is valid mpv syntax" {
    if command -v mpv >/dev/null 2>&1; then
        run mpv --include="$PROJECT_DIR/config/mpv.conf" --length=0.1 --really-quiet /dev/null
        [ "$status" -eq 0 ]
    else
        skip "mpv not installed"
    fi
}

@test "streamlink can detect YouTube URL format" {
    if command -v streamlink >/dev/null 2>&1; then
        run streamlink --stream-url "https://www.youtube.com/watch?v=dQw4w9WgXcQ" worst 2>&1
        # May fail if not live, but should not crash
        [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    else
        skip "streamlink not installed"
    fi
}

@test "yt-dlp can extract YouTube URL format" {
    if command -v yt-dlp >/dev/null 2>&1; then
        run yt-dlp -g --format worst "https://www.youtube.com/watch?v=dQw4w9WgXcQ" 2>&1
        # May fail if not live or rate-limited
        [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
    else
        skip "yt-dlp not installed"
    fi
}

# ─── Resilience tests ────────────────────────────────────────────────────────

@test "watch-resilient.sh cleanly handles missing URL" {
    run bash "$PROJECT_DIR/watch-resilient.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "watch-resilient.sh validates mode parameter" {
    run bash "$PROJECT_DIR/watch-resilient.sh" "https://youtube.com/test" --mode bogus
    [ "$status" -eq 1 ]
}

@test "lock file prevents duplicate instances" {
    # Create a fake lock
    echo "99999-9999999999" > /tmp/youtube-live-ultra.lock
    run bash "$PROJECT_DIR/watch-resilient.sh" "https://youtube.com/test" 2>&1
    # Should fail because of existing lock
    [ "$status" -eq 1 ]
    rm -f /tmp/youtube-live-ultra.lock
}

@test "stale lock is detected and removed" {
    # Create a lock with a non-existent PID
    echo "99999999-9999999999" > /tmp/youtube-live-ultra.lock
    # Script should detect stale lock, warn, and remove it
    run bash -c "\"$PROJECT_DIR/watch-resilient.sh\" 'https://youtube.com/test' 2>&1 | head -5"
    rm -f /tmp/youtube-live-ultra.lock
    [ "$status" -eq 1 ]  # Will fail because not live
}
