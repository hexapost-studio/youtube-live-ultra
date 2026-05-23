# Roadmap

## v1.0 ✅ (actuelle)
- [x] CLI basse latence (4 modes : standard, ultra, direct, résilient)
- [x] Watchdog IPC (détection freeze + buffer underrun)
- [x] Triple fallback (streamlink → yt-dlp → mpv --ytdl)
- [x] Dashboard web (stats live, chat YouTube, contrôles)
- [x] TUI curses
- [x] Installation modulaire (4 tiers)
- [x] Cross-platform (macOS, Linux, WSL2)
- [x] Tests + CI + shellcheck

## v1.1 — Polish & robustesse
- [ ] `ylu` CLI Python unifiée (remplace tous les scripts Bash)
- [ ] Tests comportementaux (mock mpv IPC, dashboard HTTP)
- [ ] CI multi-OS (macOS runner, Windows/WSL2)
- [ ] Content-Security-Policy sur dashboard
- [ ] `man ylu` + autocomplétion shell

## v1.2 — Features
- [ ] Mode audio-only (yt-dlp -f bestaudio)
- [ ] Enregistrement local (--record)
- [ ] Notification desktop (début de live)
- [ ] Historique des URLs regardées
- [ ] Détection automatique du mode optimal (ultra si <20ms ping, sinon standard)

## v1.3 — Performance
- [ ] QUIC/HTTP3 proxy vers CDN Google
- [ ] Multi-edge download (3 CDN edges en parallèle)
- [ ] Neural upscale 720p→1080p (CoreML/Metal)

## v2.0 — Go rewrite
- [ ] Binaire unique (go build)
- [ ] Dashboard HTML embeddé
- [ ] Zero dépendances runtime
- [ ] Cross-compilation triviale
- [ ] API gRPC pour contrôle distant

## Idées futures
- [ ] Intégration OBS (source basse latence)
- [ ] YouTube live chat interactif (envoi de messages)
- [ ] Multi-stream (plusieurs lives côte à côte)
- [ ] Modèle économique ? (jamais de pub, jamais de tracking)
