# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in youtube-live-ultra, please report it
**privately**. Do not open a public issue.

**Contact:** hexapost-studio@proton.me

Please include:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Possible mitigations

You will receive a response within 72 hours.

## Scope

- `ylu` CLI and all bundled scripts (watch*.sh, dashboard/, scripts/)
- The dashboard web server (localhost only by design)
- mpv IPC socket handling

## Out of scope

- Vulnerabilities in dependencies (streamlink, yt-dlp, mpv, ffmpeg)
  → Report those upstream
- YouTube CDN or API issues
- User misconfiguration

## Supported versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅ |

## Best practices for users

- The dashboard binds to `127.0.0.1` only — never expose it to the network
- Use `--sandbox` flag to isolate mpv
- Keep dependencies updated (`brew upgrade streamlink mpv yt-dlp`)
