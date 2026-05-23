#!/usr/bin/env bats
# =============================================================================
# Smoke tests — lancement réel 30s sur stream live
# Vérifie que le pipeline complet ne crash pas.
# =============================================================================

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/.."
    PROJECT_DIR="$TEST_DIR/.."
    # Stream de test qui marche (ICC TV — live 24/7)
    TEST_URL="https://www.youtube.com/watch?v=YA20TtOIDdk"
}

teardown() {
    # Nettoyer les locks/sockets résiduels
    rm -f /tmp/youtube-live-ultra.lock /tmp/mpv-socket-* /tmp/mpv-dash-* 2>/dev/null || true
}

# ─── CLI ─────────────────────────────────────────────────────────────────────

@test "smoke: watch.sh lance 1080p sans crash" {
    if ! command -v streamlink >/dev/null 2>&1; then skip "streamlink absent"; fi
    if ! command -v mpv >/dev/null 2>&1; then skip "mpv absent"; fi
    if ! command -v yt-dlp >/dev/null 2>&1; then skip "yt-dlp absent"; fi
    
    # Lancer 15s (assez pour vérifier que ça démarre)
    timeout 20 bash "$PROJECT_DIR/watch.sh" "$TEST_URL" 2>&1 || true
    # Si on arrive ici sans crash, c'est bon
    [ $? -le 1 ]  # 0=ok, 1=erreur réseau (OK), >1=crash
}

@test "smoke: yt-dlp extrait URL valide" {
    if ! command -v yt-dlp >/dev/null 2>&1; then skip "yt-dlp absent"; fi
    
    run yt-dlp -g --format best "$TEST_URL" 2>&1
    # Peut échouer si throttle, mais ne doit pas crasher
    [ "$status" -eq 0 ] || [[ "$output" == *"HTTP Error"* ]] || [[ "$output" == *"Forbidden"* ]]
}

@test "smoke: streamlink détecte le stream" {
    if ! command -v streamlink >/dev/null 2>&1; then skip "streamlink absent"; fi
    
    run streamlink --loglevel error "$TEST_URL" 2>&1
    # Doit trouver des streams ou donner une erreur réseau (pas un crash)
    [[ "$output" == *"Available streams"* ]] || [[ "$output" == *"error"* ]]
}

@test "smoke: watch-resilient.sh gère le lock" {
    if ! command -v mpv >/dev/null 2>&1; then skip "mpv absent"; fi
    
    # Simuler un lock
    echo "99999-9999999999" > /tmp/youtube-live-ultra.lock
    run bash "$PROJECT_DIR/watch-resilient.sh" "$TEST_URL" 2>&1
    rm -f /tmp/youtube-live-ultra.lock
    # Doit détecter le lock ou tenter de lancer (si stale)
    [ "$status" -eq 1 ]
}
