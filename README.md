# 🎬 YouTube Live Ultra

> Regarder un live YouTube avec **la latence la plus basse possible** tout en
> gardant **la résolution maximale disponible**.

[![CI](https://github.com/hexapost-studio/youtube-live-ultra/actions/workflows/ci.yml/badge.svg)](https://github.com/hexapost-studio/youtube-live-ultra/actions)
[![Version](https://img.shields.io/badge/version-1.0.0-blue)](https://github.com/hexapost-studio/youtube-live-ultra/releases)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Tu n'installes que ce dont tu as besoin.** 4 tiers indépendants, du CLI pur au dashboard web.

> [!IMPORTANT]
> **Deux implémentations dans ce dépôt :**
> - **`main`** (cette branche) — scripts **Bash/Python**, pour **macOS & Linux** (et Windows via WSL2).
> - **[`go`](https://github.com/hexapost-studio/youtube-live-ultra/tree/go)** — binaire unique **`ylu`** (Go), notamment le **Windows natif sans WSL2**.
>
> 🪟 **Sur Windows ?** Télécharge `ylu.exe` depuis les **[Releases](https://github.com/hexapost-studio/youtube-live-ultra/releases)** (ou lance `bootstrap.ps1`). Détails : [branche `go`](https://github.com/hexapost-studio/youtube-live-ultra/tree/go#-windows-natif-sans-wsl2).

---

## 🎯 Vision produit

```
Tier 1 : CLI Pure (~50 MB)       → « Juste regarder un live »
Tier 2 : + Résilience (+5 MB)    → « Ne jamais couper »
Tier 3 : + Dashboard (+15 MB)    → « Stats, chat, interface »
Tier 4 : + TUI (+0 MB)           → « SSH, pas de navigateur »
```

[Voir PRODUCT.md pour le détail](PRODUCT.md)

---

## ⚡ Installation

```bash
git clone https://github.com/hexapost-studio/youtube-live-ultra.git
cd youtube-live-ultra
./install.sh          # Mode interactif (choisis ton tier)
```

**Ou directement :**
```bash
./install.sh --cli         # Tier 1 : juste le minimum
./install.sh --dashboard   # Tiers 1+2+3 : tout sauf TUI
./install.sh --all         # Tout installer
```

**Via Homebrew (une seule commande) :**
```bash
brew install hexapost-studio/tap/youtube-live-ultra
youtube-live-watch "https://www.youtube.com/watch?v=XXXXXXXXXXX"
```

---

## 📂 Structure

```
youtube-live-ultra/
├── watch.sh                    # Mode STANDARD — streamlink + mpv (équilibré)
├── watch-ultra.sh              # Mode ULTRA — streamlink + mpv agressif
├── watch-ytdlp.sh              # Mode DIRECT — yt-dlp → mpv (sans streamlink)
├── watch-resilient.sh          # Mode RÉSILIENT — watchdog + multi-backend ★
├── config/
│   └── mpv.conf                # Configuration mpv optimisée Apple Silicon
├── scripts/
│   ├── health-check.sh         # Validation pré-live de tout le pipeline ★
│   ├── optimize-network.sh     # Tuning réseau pré-live (DNS, TCP, WiFi)
│   ├── find-best-edge.sh       # Détection du CDN edge Google le plus proche
│   └── benchmark-latency.sh    # Comparaison objective des 3 modes
└── README.md
```

---

## 🧠 Architecture : Comment ça marche

YouTube diffuse ses lives en **HLS** (HTTP Live Streaming). Le flux est découpé en
segments de 2 à 6 secondes. La latence perçue = temps que le player garde en
buffer + temps de téléchargement + temps de rendu.

Notre stack attaque chaque maillon de cette chaîne :

```
YouTube CDN ──HLS──▶ Streamlink ──pipe──▶ mpv ──▶ Écran
                      │                      │
                      ├─ hls-live-edge       ├─ cache nul/minimal
                      ├─ segment threads     ├─ hwdec videotoolbox
                      └─ ringbuffer          └─ framedrop + untimed
```

Variante yt-dlp direct :
```
YouTube CDN ──HLS──▶ mpv ──▶ Écran
                      │
                      ├─ hls-live-edge (géré par mpv)
                      ├─ cache nul/minimal
                      └─ hwdec videotoolbox
```

---

## 📊 État de l'art : où on se situe

### Ce que font les géants

| Plateforme | Protocole | Latence | Détail |
|-----------|-----------|---------|--------|
| **Twitch** (LL-HLS) | HLS custom | **~3s** | Segments 1s, backbone privé 100 PoPs |
| **Twitch** (Corée) | HLS custom | **~1.5s** | Optimisation régionale extrême |
| **Twitch Stages** | WebRTC | **<300ms** | Limité à 25K viewers |
| **YouTube** (ultra-low) | RTMP→CMAF | **<5s** | Nécessite encodeur RTMP côté streamer |
| **YouTube** (low) | HLS/DASH | **10-15s** | Mode par défaut |
| **YouTube** (normal) | HLS/DASH | **15-25s** | Qualité maximale |
| **Apple LL-HLS** (spéc) | HTTP/2 chunked CMAF | **2-6s** | Partiel segments + playlist delta |
| **LL-DASH** (spéc) | HTTP/1.1 chunked | **2-6s** | Service description + chunk delivery |
| **WebRTC** (théorique) | UDP/SCTP | **<1s** | Ne scale pas sans SFU/CDN |

### Notre position

| Mode | Script | Latence estimée | Stabilité |
|------|--------|----------------|-----------|
| Standard | `watch.sh` | **4-8s** | ★★★★★ |
| Ultra | `watch-ultra.sh` | **2-5s** | ★★★☆☆ |
| yt-dlp direct | `watch-ytdlp.sh` | **2-4s** | ★★★☆☆ |
| YouTube navigateur | (référence) | **15-25s** | ★★★★★ |

**Plafond théorique :** ~2 secondes. Imposé par la durée minimale des segments
HLS que YouTube sert. Pour descendre sous la seconde, il faudrait que YouTube
expose un endpoint WebRTC (ce qu'ils ne font pas publiquement).

### Papiers de référence

- **"Toward One-Second Latency: Evolution of Live Media Streaming"**
  Bentaleb, Begen, Zimmermann et al. — IEEE COMST 2025
  Survey complet de tous les protocoles et sources de latence.
  arXiv: [2310.03256](https://arxiv.org/abs/2310.03256)

- **"Camel: Frame-Level Bandwidth Estimation for Low-Latency Live Streaming"**
  Liu, Jia, Jiang, Zhang et al. — WWW 2026
  Contrôle de congestion frame-level sur plateforme WebRTC 250M users.
  arXiv: [2602.09500](https://arxiv.org/abs/2602.09500)

- **"Optimal Quality and Efficiency in Adaptive Live Streaming with JND-Aware Low Latency Encoding"**
  Menon, Zhu, Rajendran et al. — MHV 2024
  Optimisation encodeur HLS temps réel avec HEVC.
  arXiv: [2401.15343](https://arxiv.org/abs/2401.15343)

---

## 🔬 Toutes les tricks, couche par couche

### TIER 1 : Streamlink (extraction du flux)

| Paramètre | watch.sh | watch-ultra.sh | Effet |
|-----------|----------|----------------|-------|
| `--hls-live-edge` | 2 | 1 | Segments gardés en avance. 1 = latence min (~2-4s), 2 = plus stable |
| `--stream-segment-threads` | 3 | 4 | Téléchargements parallèles de segments HLS |
| `--ringbuffer-size` | 64M | 128M | Buffer mémoire circulaire entre streamlink et mpv |
| `--hls-live-restart` | non | oui | Redémarre automatiquement si le flux devient stale |
| `--stream-segment-timeout` | 10s | 5s | Timeout agressif = skip les segments lents au lieu d'attendre |

**Pourquoi hls-live-edge=1 est le max théorique :** HLS impose au moins 1
segment d'avance. Si le segment fait 2 secondes, ta latence minimale est de ~2s.
Impossible d'aller plus bas avec HLS sans changer de protocole (WebRTC).

### TIER 1B : yt-dlp direct (sans streamlink)

`watch-ytdlp.sh` contourne streamlink : `yt-dlp -g` extrait l'URL HLS brute et
la passe directement à mpv. mpv gère le HLS en interne avec son propre
`--hls-live-edge`.

**Gain :** -100 à -500ms (pas de couche Python streamlink, pas de ringbuffer).
**Risque :** Pas de retry automatique si le stream coupe.

### TIER 2 : mpv (lecture)

| Paramètre | Effet |
|-----------|-------|
| `--profile=low-latency` | Active le preset basse latence intégré de mpv |
| `--cache=no` / `--demuxer-max-bytes=500K` | Désactive/minimise le cache démultiplexeur |
| `--demuxer-readahead-secs=0.05` | Lecture anticipée quasi nulle |
| `--video-latency-hacks=yes` | Active tous les hacks internes de mpv |
| `--untimed=yes` | Joue les frames dès réception, ignore PTS |
| `--framedrop=vo+decoder` | Drop frames en retard (VO + décodeur) |
| `--video-sync=audio` | Cale la vidéo sur l'audio |
| `--vd-lavc-threads=6` | Décode 6 frames en parallèle (M2 = 8 cœurs) |
| `--audio-buffer=0.1` | Buffer audio minimal |
| `--osc=no` | Pas d'OSC — gagne des cycles CPU |
| `--hls-live-edge=1` | (yt-dlp mode) mpv gère HLS directement |

### TIER 3 : Hardware Decode (Apple Silicon)

| Paramètre | Rôle |
|-----------|------|
| `--hwdec=videotoolbox` | Décodage H.264/HEVC hardware Apple |
| `--vo=gpu-next` | Nouveau moteur de rendu GPU |
| `--gpu-api=metal` | API graphique native Apple |
| `--gpu-context=cocoa` | Contexte fenêtre natif macOS |

**Impact mesurable :** Software = 15-30% CPU + 30-80ms. VideoToolbox = 2-5% CPU + 5-15ms.

### TIER 4 : Réseau

| Technique | Détail |
|-----------|--------|
| **CDN edge le plus proche** | `find-best-edge.sh` teste tous les edges Google et trouve le plus rapide |
| **DNS rapide** | Cloudflare `1.1.1.1` ou Google `8.8.8.8` |
| **TCP receive buffer** | `net.inet.tcp.recvspace` à 4MB (macOS) |
| **Delayed ACK off** | `net.inet.tcp.delayed_ack=0` — désactive Nagle |
| **TCP BBR** (Linux) | Congestion control moderne |
| **WiFi Power Save OFF** | Évite les micro-veilles de la carte WiFi |
| **AWDL OFF** (macOS) | Désactive AirDrop/AirPlay (interférences toutes les ~500ms) |
| **Ethernet > WiFi** | Câble = 0-1ms jitter. WiFi = 5-30ms jitter |

### TIER 5 : Système

| Technique | Commande |
|-----------|----------|
| **Renice** | `sudo renice -n -15 -p <pid>` |
| **Notifications OFF** | Mode Ne Pas Déranger |
| **Fermer les apps lourdes** | Chrome, Docker, VS Code... |

---

## 📊 Les trois modes

### Mode Standard (`watch.sh`)
- **Latence :** ~4-8 secondes
- **Stabilité :** Excellente
- **Stack :** streamlink → mpv
- **Quand :** Tous les jours, usage normal

### Mode Ultra (`watch-ultra.sh`)
- **Latence :** ~2-5 secondes
- **Stabilité :** Sacrifiée — micro-freezes possibles
- **Stack :** streamlink → mpv (agressif)
- **Quand :** Sport, gaming, enchères

### Mode Direct (`watch-ytdlp.sh`)
- **Latence :** ~2-4 secondes (le plus bas)
- **Stabilité :** Pas de retry automatique
- **Stack :** yt-dlp → HLS URL → mpv (direct)
- **Quand :** Latence absolue, stream stable

### Mode Résilient (`watch-resilient.sh`) ★
- **Latence :** ~2-5 secondes
- **Stabilité :** Maximale — watchdog, multi-backend, auto-restart
- **Stack :** yt-dlp → streamlink (fallback) → mpv + watchdog
- **Quand :** Stream important, connexion instable, longue durée

---

## 🛡️ Stratégie de résilience

`watch-resilient.sh` intègre plusieurs mécanismes de self-healing :

### 1. Multi-backend fallback
Si yt-dlp échoue → streamlink prend le relais automatiquement.
Chaque backend a sa propre méthode d'extraction HLS.

### 2. Watchdog anti-crash
Un processus séparé surveille mpv en continu :
- Si mpv crash → redémarrage automatique
- Si mpv freeze 15s → kill + restart
- Exponential backoff : 2s → 4s → 8s → ... → max 60s
- Max 10 redémarrages avant abandon

### 3. Pre-flight health check
```bash
./scripts/health-check.sh "https://www.youtube.com/watch?v=XXXXX"
```
Vérifie en 7 étapes :
1. Dépendances (mpv, streamlink, yt-dlp, curl)
2. Réseau (DNS, ping YouTube, WiFi vs Ethernet)
3. Matériel (Apple Silicon, cœurs CPU, RAM)
4. Stream (est-il en live ? extractible par yt-dlp et streamlink ?)
5. Espace disque
6. Conflits (autre instance ? apps lourdes ?)
7. Bande passante (débit vers CDN Google)

### 4. Verrouillage (lock file)
Une seule instance à la fois (`/tmp/youtube-live-ultra.lock`).
Détection automatique des stale locks.

### 5. Nettoyage garanti
`trap EXIT` assure le cleanup (kill mpv, kill watchdog, rm lock)
même en cas de Ctrl-C ou crash du script.

### 6. Logging structuré
Toutes les sessions sont loggées dans `/tmp/youtube-live-ultra-logs/`
avec timestamps et niveaux (INFO/WARN/ERROR).

---

## 🔧 Commandes clavier mpv

| Touche | Action |
|--------|--------|
| `q` | Quitter |
| `f` | Plein écran |
| `9` / `0` | Volume -/+ |
| `[` / `]` | Vitesse -10% / +10% |
| `{` / `}` | Vitesse ÷2 / ×2 |
| `Backspace` | Vitesse normale |
| `Shift+I` puis `2` | Stats détaillées (drops, fps, latence décodeur) |
| `Shift+Q` | Quitter et sauver la position |

---

## 🧪 Mesurer ta latence réelle

### Méthode automatique
```bash
./scripts/benchmark-latency.sh "https://www.youtube.com/watch?v=XXXXX"
```
Lance les 3 modes séquentiellement (30s chacun) et compare les segments HLS.

### Méthode manuelle (la plus fiable)
1. Ouvre le live sur youtube.com dans un navigateur **à côté** du terminal
2. Lance un des scripts
3. Quand le streamer dit un mot ou fait un geste visible,
   **chronomètre la différence** entre les deux fenêtres
4. Répète 3 fois, fais la moyenne

### Latence réseau pure
```bash
# Ping vers le CDN edge le plus proche
./scripts/find-best-edge.sh

# Test de latence HLS (télécharge un segment et mesure)
time curl -s -o /dev/null "$(yt-dlp -g --format best <URL> | head -1)"
```

---

## 🚀 Aller encore plus loin

### Implémenté
- [x] yt-dlp direct (`watch-ytdlp.sh`)
- [x] Sélection CDN edge (`find-best-edge.sh`)
- [x] Benchmark comparatif (`benchmark-latency.sh`)

### Techniquement possible mais pas (encore) fait

1. **WebRTC client** : Si YouTube expose un endpoint WebRTC un jour, latence <1s.
   Aujourd'hui, seuls Twitch Stages et certaines plateformes chinoises (Douyin)
   utilisent WebRTC pour le broadcast grand public.

2. **CMAF chunked reader** : Si YouTube sert des chunks CMAF via HTTP/2 push,
   un lecteur CMAF-aware pourrait descendre à 1-2s. Pas d'API publique pour ça.

3. **Proxy CDN edge** : VPS dans la même région que l'edge Google le plus proche,
   tunnel SSH/WireGuard. Utile si tu es loin des edges Google.

4. **Frame-level congestion control** (inspiré du papier Camel) :
   Implémenter un contrôle de congestion frame-level dans un proxy local entre
   le CDN et mpv. Complexe mais gain potentiel sur les flux instables.

5. **Multi-CDN fallback** : Télécharger les segments depuis plusieurs edges en
   parallèle et prendre le premier arrivé. Nécessite de modifier streamlink.

6. **Kernel bypass networking** : DPDK/netmap — gain ~50-100µs (overkill).

---

## 📦 Dépendances

```bash
# macOS
brew install streamlink mpv yt-dlp

# Linux (Debian/Ubuntu)
sudo apt install streamlink mpv yt-dlp

# Linux (Arch)
sudo pacman -S streamlink mpv yt-dlp
```

Testé sur :
- macOS 14 (Sonoma) / Apple M2 Pro
- macOS 15 (Sequoia) / Apple M2

---

## ⚠️ Limitations

- **YouTube peut changer son implémentation HLS** sans préavis — streamlink
  suit généralement en 1-2 jours.
- **Les streams "ultra-low latency" YouTube** (paramétrés par le streamer)
  réduisent la durée des segments HLS. Sans ce réglage côté streamer, la latence
  minimale sera de ~6-8s même avec nos optimisations.
- **Géolocalisation** : si tu es loin du CDN YouTube le plus proche, la latence
  réseau dominera tout le reste. Utilise `find-best-edge.sh` pour mesurer.
- **Plancher HLS** : ~2 secondes. Pour descendre plus bas, il faut WebRTC ou
  CMAF chunked — non exposés publiquement par YouTube.
- **yt-dlp peut être bloqué** par YouTube périodiquement. Streamlink est plus
  résilient (plugin YouTube maintenu activement).

---

## 🏗️ Développement & Contribution

### Stack
- **Shell** (Bash 4+) — scripts principaux
- **bats-core** — test suite
- **Shellcheck** — linting
- **Make** — build system
- **GitHub Actions** — CI/CD

### Compatibilité OS

| OS | Statut | Accélération GPU |
|----|--------|-----------------|
| macOS 14+ (Apple Silicon) | ✅ Complet | VideoToolbox + Metal |
| macOS 13+ (Intel) | ✅ Complet | VideoToolbox |
| Linux (Ubuntu 22.04+, Arch) | ✅ Complet | VAAPI / VDPAU / Vulkan |
| Linux (autres distros) | ⚠️ Testé partiellement | auto-safe |
| WSL2 (Windows 10/11) | ✅ Supporté | VAAPI (via D3D12/Mesa) |
| FreeBSD | ⚠️ Non testé | auto-safe |
| Windows natif | ❌ Utilise WSL2 | via `bootstrap.ps1` |

### Commandes
```bash
make check      # Lint + tests
make lint       # Shellcheck uniquement
make test       # Tests uniquement (nécessite bats)
make install    # Installation système
make clean      # Nettoyage
make release    # Tag + push release
```

### CI Pipeline
À chaque push sur `main` :
1. **Lint** — shellcheck sur tous les scripts
2. **Syntax** — bash -n validation
3. **Test** — bats unit + integration
4. **Version** — validation semver + CHANGELOG

### Structure des tests
```
tests/
├── unit/
│   └── basic.bats         # Tests unitaires (syntaxe, usage, args)
└── integration/
    └── pipeline.bats       # Tests d'intégration (mock HLS, lock, live)
```

---

Projet par Aymeric — hexapost-studio
