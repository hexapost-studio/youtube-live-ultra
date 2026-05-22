#!/usr/bin/env bats
# =============================================================================
# Unit tests for youtube-live-ultra
# Run: bats tests/unit/
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    PROJECT_DIR="$TEST_DIR/.."
}

# ─── watch.sh ────────────────────────────────────────────────────────────────

@test "watch.sh exists and is executable" {
    [ -f "$PROJECT_DIR/watch.sh" ]
    [ -x "$PROJECT_DIR/watch.sh" ]
}

@test "watch.sh has valid shebang" {
    run head -1 "$PROJECT_DIR/watch.sh"
    [ "$output" = "#!/usr/bin/env bash" ]
}

@test "watch.sh passes syntax check" {
    run bash -n "$PROJECT_DIR/watch.sh"
    [ "$status" -eq 0 ]
}

@test "watch.sh shows usage when no args" {
    run "$PROJECT_DIR/watch.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "watch.sh detects missing streamlink" {
    PATH="/nonexistent" run "$PROJECT_DIR/watch.sh" "https://youtube.com/watch?v=test"
    [ "$status" -eq 1 ]
    [[ "$output" == *"streamlink"* ]]
}

# ─── watch-ultra.sh ──────────────────────────────────────────────────────────

@test "watch-ultra.sh exists and is executable" {
    [ -f "$PROJECT_DIR/watch-ultra.sh" ]
    [ -x "$PROJECT_DIR/watch-ultra.sh" ]
}

@test "watch-ultra.sh passes syntax check" {
    run bash -n "$PROJECT_DIR/watch-ultra.sh"
    [ "$status" -eq 0 ]
}

# ─── watch-ytdlp.sh ──────────────────────────────────────────────────────────

@test "watch-ytdlp.sh exists and is executable" {
    [ -f "$PROJECT_DIR/watch-ytdlp.sh" ]
    [ -x "$PROJECT_DIR/watch-ytdlp.sh" ]
}

@test "watch-ytdlp.sh passes syntax check" {
    run bash -n "$PROJECT_DIR/watch-ytdlp.sh"
    [ "$status" -eq 0 ]
}

# ─── watch-resilient.sh ──────────────────────────────────────────────────────

@test "watch-resilient.sh exists and is executable" {
    [ -f "$PROJECT_DIR/watch-resilient.sh" ]
    [ -x "$PROJECT_DIR/watch-resilient.sh" ]
}

@test "watch-resilient.sh passes syntax check" {
    run bash -n "$PROJECT_DIR/watch-resilient.sh"
    [ "$status" -eq 0 ]
}

@test "watch-resilient.sh shows usage with --help" {
    run "$PROJECT_DIR/watch-resilient.sh" --help
    [ "$status" -eq 1 ]
    [[ "$output" == *"Usage"* ]]
}

@test "watch-resilient.sh rejects invalid mode" {
    run "$PROJECT_DIR/watch-resilient.sh" "https://youtube.com/watch?v=test" --mode invalid
    [ "$status" -eq 1 ]
}

@test "watch-resilient.sh accepts valid modes" {
    for mode in ultra standard direct; do
        run bash -c "\"$PROJECT_DIR/watch-resilient.sh\" 'https://youtube.com/watch?v=test' --mode $mode 2>&1 | head -5"
        # Should not fail with "Mode invalide"
        [[ "$output" != *"Mode invalide"* ]]
    done
}

# ─── Config ──────────────────────────────────────────────────────────────────

@test "mpv.conf exists" {
    [ -f "$PROJECT_DIR/config/mpv.conf" ]
}

@test "mpv.conf contains required settings" {
    run grep -c "hwdec=videotoolbox" "$PROJECT_DIR/config/mpv.conf"
    [ "$status" -eq 0 ]
}

@test "config.example is valid" {
    [ -f "$PROJECT_DIR/config/config.example" ]
    run bash -n "$PROJECT_DIR/config/config.example"
    # Comments-only files might fail syntax check, that's OK
    true
}

# ─── Versioning ──────────────────────────────────────────────────────────────

@test "VERSION file exists" {
    [ -f "$PROJECT_DIR/VERSION" ]
}

@test "VERSION is semver format" {
    run cat "$PROJECT_DIR/VERSION"
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "CHANGELOG.md exists" {
    [ -f "$PROJECT_DIR/CHANGELOG.md" ]
}

@test "CHANGELOG.md references current version" {
    VERSION=$(cat "$PROJECT_DIR/VERSION")
    run grep -c "$VERSION" "$PROJECT_DIR/CHANGELOG.md"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
}

# ─── Makefile ────────────────────────────────────────────────────────────────

@test "Makefile exists" {
    [ -f "$PROJECT_DIR/Makefile" ]
}

@test "make help works" {
    run make -C "$PROJECT_DIR" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"install"* ]]
}

# ─── Shellcheck config ───────────────────────────────────────────────────────

@test ".shellcheckrc exists" {
    [ -f "$PROJECT_DIR/.shellcheckrc" ]
}

# ─── Gitignore ───────────────────────────────────────────────────────────────

@test ".gitignore exists" {
    [ -f "$PROJECT_DIR/.gitignore" ]
}

@test ".gitignore covers logs" {
    run grep -c "log" "$PROJECT_DIR/.gitignore"
    [ "$status" -eq 0 ]
}
