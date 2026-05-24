# Quickstart — YouTube Live Ultra

> Regarder un live YouTube avec 3× moins de latence que Chrome, 5× moins de RAM.

## En 30 secondes

```bash
git clone https://github.com/hexapost-studio/youtube-live-ultra.git
cd youtube-live-ultra
./install.sh --cli
./watch.sh "https://www.youtube.com/watch?v=XXXXXXXXXXX"
```

## Toutes les commandes

| Commande | Usage | Mode |
|----------|-------|------|
| `./watch.sh <URL>` | Standard (~4-8s latence) | Streamlink + mpv |
| `./watch-ultra.sh <URL>` | Ultra (~2-5s latence) | Streamlink agressif |
| `./watch-ytdlp.sh <URL>` | Direct (~2-4s) | yt-dlp → mpv |
| `./watch-resilient.sh <URL>` | Résilient | Watchdog + auto-restart |
| `./watch-dashboard.sh <URL>` | Dashboard web | Stats + chat (localhost:9191) |
| `./watch-tui.sh <URL>` | TUI terminal | Curses (SSH/headless) |

**OU avec la CLI unifiée :**
```bash
python3 ylu watch <URL>                    # Standard
python3 ylu watch <URL> --mode ultra       # Ultra
python3 ylu watch <URL> --mode direct      # yt-dlp direct
python3 ylu watch <URL> --mode resilient   # Watchdog
python3 ylu watch <URL> --dry-run          # Tester sans lancer
python3 ylu dashboard <URL>                # Dashboard web
python3 ylu tui <URL>                      # TUI terminal
python3 ylu check <URL>                    # Health check
python3 ylu optimize                       # Diagnostic réseau
python3 ylu install                        # Installation interactive
```

## Options communes

| Flag | Effet |
|------|-------|
| `--help` | Aide |
| `--version` | Version + OS + GPU |
| `--dry-run` | Tester sans lancer mpv |
| `--verbose` | Afficher les étapes |
| `--sandbox` | Isoler mpv (sandbox-exec/firejail) |
| `NO_COLOR=1` | Désactiver les couleurs |

## Exemples concrets

```bash
# Regarder un live
./watch.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Live important — mode résilient avec watchdog
./watch-resilient.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ" --mode ultra

# Dashboard web — stats + chat dans le navigateur
./watch-dashboard.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
# → Ouvre http://localhost:9191

# TUI — pour serveur SSH sans navigateur
./watch-tui.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Vérifier le pipeline avant de lancer
./scripts/health-check.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"

# Optimiser le réseau
sudo ./scripts/optimize-network.sh

# Benchmark les 3 modes
./scripts/benchmark-latency.sh "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
```

## Installation par tiers

```bash
./install.sh           # Mode interactif
./install.sh --cli     # Minimum (50 MB)
./install.sh --dashboard  # + Dashboard web
./install.sh --all     # Tout (~70 MB)
```

## Touches mpv

| Touche | Action |
|--------|--------|
| `q` | Quitter |
| `f` | Plein écran |
| `9/0` | Volume |
| `[/]` | Vitesse |
| `Shift+I` | Stats détaillées |
| `Shift+Q` | Quitter + sauver position |
