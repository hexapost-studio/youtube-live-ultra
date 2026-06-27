# =============================================================================
# youtube-live-ultra — bootstrap.ps1
# Amorçage Windows NATIF : installe les dépendances et construit ylu.exe (Go).
# Plus besoin de WSL2 — la version Go compile en binaire Windows natif.
#
# Usage (PowerShell) :
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\bootstrap.ps1
#
# Repli WSL2 (ancienne méthode, scripts Bash) :
#   .\bootstrap.ps1 -Wsl
# =============================================================================

param(
    [switch]$Wsl
)

Write-Host "================================================================" -ForegroundColor Green
Write-Host "  youtube-live-ultra — Windows Bootstrap (natif)" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# ─── Repli WSL2 explicite ────────────────────────────────────────────────────
if ($Wsl) {
    Write-Host "[WSL2] Méthode de repli (scripts Bash)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  1) Installer WSL2 :   wsl --install   (PowerShell admin, puis redémarrer)"
    Write-Host "  2) Dans WSL :         sudo apt update && sudo apt install -y streamlink mpv yt-dlp curl"
    Write-Host "  3) Cloner :           git clone https://github.com/hexapost-studio/youtube-live-ultra.git ~/youtube-live-ultra"
    Write-Host "  4) Lancer :           cd ~/youtube-live-ultra && ./watch-resilient.sh '<URL>' --mode ultra"
    Write-Host ""
    Write-Host "  Doc : https://learn.microsoft.com/fr-fr/windows/wsl/install"
    exit 0
}

# ─── Étape 1 : winget ────────────────────────────────────────────────────────
Write-Host "[1/4] Verification de winget..." -ForegroundColor Cyan
$hasWinget = $null -ne (Get-Command winget -ErrorAction SilentlyContinue)
if ($hasWinget) {
    Write-Host "  OK winget present" -ForegroundColor Green
} else {
    Write-Host "  winget absent. Installe 'App Installer' depuis le Microsoft Store," -ForegroundColor Yellow
    Write-Host "  ou installe manuellement mpv / streamlink / yt-dlp / go." -ForegroundColor Yellow
}

# ─── Étape 2 : Dependances runtime (mpv, streamlink, yt-dlp) ──────────────────
Write-Host ""
Write-Host "[2/4] Installation des dependances runtime..." -ForegroundColor Cyan

function Ensure-Tool($name, $wingetId) {
    if (Get-Command $name -ErrorAction SilentlyContinue) {
        Write-Host "  OK $name deja present" -ForegroundColor Green
        return
    }
    if ($hasWinget) {
        Write-Host "  Installation de $name ($wingetId)..." -ForegroundColor White
        winget install --id $wingetId --accept-source-agreements --accept-package-agreements -e | Out-Null
    } else {
        Write-Host "  $name manquant — installe-le manuellement ($wingetId)" -ForegroundColor Yellow
    }
}

Ensure-Tool "mpv"        "mpv.net"
Ensure-Tool "streamlink" "streamlink.streamlink"
Ensure-Tool "yt-dlp"     "yt-dlp.yt-dlp"

# ─── Étape 3 : Go + build du binaire natif ───────────────────────────────────
Write-Host ""
Write-Host "[3/4] Construction de ylu.exe (Go)..." -ForegroundColor Cyan

if (-not (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Host "  Go absent — installation..." -ForegroundColor White
    if ($hasWinget) {
        winget install --id GoLang.Go --accept-source-agreements --accept-package-agreements -e | Out-Null
        Write-Host "  Go installe. RELANCE ce script (nouveau terminal) pour finir le build." -ForegroundColor Yellow
        exit 0
    } else {
        Write-Host "  Installe Go : https://go.dev/dl/  puis relance ce script." -ForegroundColor Yellow
        exit 1
    }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $scriptDir
try {
    go build -o ylu.exe .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  OK ylu.exe construit dans $scriptDir" -ForegroundColor Green
    } else {
        Write-Host "  Echec du build (voir erreurs ci-dessus)." -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}

# ─── Étape 4 : Verification ──────────────────────────────────────────────────
Write-Host ""
Write-Host "[4/4] Verification..." -ForegroundColor Cyan
& "$scriptDir\ylu.exe" check

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Pret. Lancer un live :" -ForegroundColor Green
Write-Host "    .\ylu.exe watch --mode ultra `"https://www.youtube.com/watch?v=XXXXXXXXXXX`"" -ForegroundColor White
Write-Host ""
Write-Host "  Decodage GPU Windows : d3d11va (--vo=gpu-next), detecte automatiquement." -ForegroundColor Cyan
Write-Host "  IPC mpv via named pipe (resilient / dashboard / tui)." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
