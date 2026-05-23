# Vision produit

## Principe

**Tu n'installes que ce dont tu as besoin.** Chaque tier est autonome.
Pas de dépendances inutiles, pas de "bloat".

---

## Les 4 tiers

```
Tier 1 : CLI Pure (~50 MB)
│  watch.sh, watch-ultra.sh, watch-ytdlp.sh
│  Deps: streamlink, mpv, yt-dlp
│  Pour : « Je veux juste regarder un live en basse latence. »
│
├─ Tier 2 : Résilience (+5 MB)
│  watch-resilient.sh, health-check.sh, optimize-network.sh
│  Deps: + socat, bc
│  Pour : « Mon stream ne doit JAMAIS couper. »
│
├─ Tier 3 : Dashboard Web (+15 MB)
│  watch-dashboard.sh, dashboard/
│  Deps: + python3 (stdlib, 0 pip)
│  Pour : « Je veux les stats, le chat, un UI. »
│
└─ Tier 4 : TUI (+0 MB si Tier 3 installé)
   watch-tui.sh
   Deps: python3 (déjà dans Tier 3)
   Pour : « Je suis en SSH, pas de navigateur. »
```

---

## Quel tier pour qui ?

| Profil | Tier | Pourquoi |
|--------|------|----------|
| Regarder un live de temps en temps | 1 | Simple, léger |
| Streamer/trader (fiabilité critique) | 2 | Watchdog, triple fallback |
| Streamer qui veut les stats | 3 | Dashboard web avec latence live |
| Admin serveur distant | 4 | TUI dans le terminal |
| Power user | 2+3+4 | Tout |

---

## Installation

```bash
# Mode interactif (questions)
./install.sh

# Ou choisir directement
./install.sh --cli         # Tier 1 seulement
./install.sh --dashboard   # Tiers 1+2+3
./install.sh --tui         # Tiers 1+2+4
./install.sh --all         # Tout

# Minimal absolu (pas de questions)
./install.sh --cli --no-interact
```

---

## Ce qu'on n'installera jamais

- Pas de Docker (overkill pour un player video)
- Pas de base de données (pas d'état à persister)
- Pas de framework JS lourd (React, Vue) — le dashboard est HTML vanilla
- Pas de Node.js — Python stdlib suffit
- Pas de Go/Rust — l'orchestration n'est pas le bottleneck
