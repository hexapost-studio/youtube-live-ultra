# Contributing

## Quick start

```bash
git clone https://github.com/hexapost-studio/youtube-live-ultra.git
cd youtube-live-ultra
make check   # lint + tests
```

## Structure

```
ylu                  → CLI unifiée Python (v1.1+)
lib/                 → Bash libraries (platform.sh, ux.sh)
watch*.sh            → Bash launchers (legacy, remplacés par ylu)
dashboard/           → Python dashboard + TUI (stdlib only)
scripts/             → Helpers (health check, optimize, benchmark)
tests/               → bats-core + pytest
```

## Code style

- **Bash** : shellcheck clean, `set -euo pipefail`, 4-space indent
- **Python** : stdlib only, no pip deps, type hints welcome
- **Commits** : [Conventional Commits](https://www.conventionalcommits.org/)

## Before submitting

```bash
make lint        # shellcheck
make test        # bats
python3 -m py_compile dashboard/*.py ylu
```

## Adding a new feature

1. Does it belong in a new tier or an existing one? See `PRODUCT.md`.
2. Does it add new dependencies? If yes, justify in the PR.
3. Does it work on macOS + Linux + WSL2?

## Philosophy

- **No bloat.** 4 tiers, pick what you need.
- **No tracking.** Zero analytics, zero telemetry.
- **No accounts.** No login, no OAuth, no cloud.
- **Stdlib first.** Python/Bash stdlib before any external dependency.
- **mpv is the engine.** We orchestrate, mpv renders.
