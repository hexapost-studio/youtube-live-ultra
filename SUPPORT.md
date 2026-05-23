# Support

## Documentation

- [README.md](README.md) — Guide complet
- [PRODUCT.md](PRODUCT.md) — Vision produit et tiers
- [ROADMAP.md](ROADMAP.md) — Versions futures
- [AUDIT.md](AUDIT.md) — Audit technique

## Getting help

**Quick questions / bugs :**
[GitHub Issues](https://github.com/hexapost-studio/youtube-live-ultra/issues)

**Security vulnerabilities :**
See [SECURITY.md](SECURITY.md) — do NOT open a public issue.

**Before opening an issue :**
1. Run `ylu check <URL>` and include the output
2. Run `ylu --version` and include the result
3. Describe your OS (`uname -a`)
4. If mpv fails, include mpv error output

## Common issues

### "No playable streams found"
YouTube may be throttling your IP. Try:
```bash
ylu watch "URL" --mode direct   # Uses yt-dlp with Android client
```

### "Failed to start player: mpv"
Install mpv: `brew install mpv` (macOS) or `sudo apt install mpv` (Linux)

### "gpu-api: metal is not supported"
Your mpv build doesn't support Metal. The tool auto-detects vulkan as fallback.
Update mpv: `brew upgrade mpv`

### Dashboard shows no chat
The stream may not have live chat enabled, or yt-dlp needs updating:
```bash
brew upgrade yt-dlp
```

## Community

No official community yet. Star the repo, open issues, submit PRs.
