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

## v2.0 — Go rewrite (conditionnel)

**⚠️ Pas avant d'avoir 100+ utilisateurs actifs.**

Le portage Go est dans la roadmap parce que 1933 lignes de Bash approchent
le plafond de maintenabilité. Mais un rewrite complet coûte cher et les gains
sont marginaux pour un outil qui passe 99.9% du temps en I/O réseau et GPU.

Go aurait du sens si :
- [ ] 100+ utilisateurs rapportent des bugs (nécessite une communauté)
- [ ] On veut un `.exe` Windows natif (Go cross-compile)
- [ ] On veut embarquer le dashboard HTML dans le binaire
- [ ] On veut une API gRPC pour du contrôle distant
- [ ] La complexité du Bash dépasse 3000 lignes

En attendant, `ylu` (Python stdlib, 350 lignes) couvre déjà 80% des cas.
Priorité v1.1 → v1.3 : features et robustesse, pas de rewrite.

Le port Go vit sur la branche [`go`](https://github.com/hexapost-studio/youtube-live-ultra/tree/go)
— aucune modification de `main` avant que les conditions soient remplies.

## Idées futures
- [ ] Intégration OBS (source basse latence)
- [ ] YouTube live chat interactif (envoi de messages)
- [ ] Multi-stream (plusieurs lives côte à côte)
- [ ] Modèle économique ? (jamais de pub, jamais de tracking)
