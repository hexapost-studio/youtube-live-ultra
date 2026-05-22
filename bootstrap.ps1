# =============================================================================
# youtube-live-ultra — bootstrap.ps1
# Script d'amorçage Windows : détecte WSL2 et guide l'installation.
#
# Usage (PowerShell en admin) :
#   Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#   .\bootstrap.ps1
# =============================================================================

Write-Host "================================================================" -ForegroundColor Green
Write-Host "  youtube-live-ultra — Windows Bootstrap" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""

# ─── Étape 1 : Détecter WSL ──────────────────────────────────────────────────
Write-Host "[1/3] Detection de WSL..." -ForegroundColor Cyan

$wslInstalled = $false
try {
    $wslVersion = wsl --version 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ WSL detecte :" -ForegroundColor Green
        wsl --version
        $wslInstalled = $true
    }
} catch {
    Write-Host "  WSL non detecte" -ForegroundColor Yellow
}

if (-not $wslInstalled) {
    Write-Host ""
    Write-Host "[2/3] Installation de WSL2..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  youtube-live-ultra necessite WSL2 pour fonctionner sur Windows."
    Write-Host "  WSL2 est le sous-systeme Linux officiel de Microsoft."
    Write-Host "  Installation : ouvre PowerShell en ADMIN et execute :"
    Write-Host ""
    Write-Host "    wsl --install" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Redemarre ensuite et relance ce script."
    Write-Host ""
    Write-Host "  Plus d'infos : https://learn.microsoft.com/fr-fr/windows/wsl/install"
    exit 1
}

# ─── Étape 2 : Vérifier WSL2 ─────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Verification WSL2..." -ForegroundColor Cyan

$wslStatus = wsl --status 2>&1
if ($wslStatus -match "version:\s*2") {
    Write-Host "  ✓ WSL2 actif" -ForegroundColor Green
} else {
    Write-Host "  ⚠ WSL detecte mais pas en version 2. Mise a niveau :" -ForegroundColor Yellow
    Write-Host "    wsl --set-default-version 2" -ForegroundColor Yellow
}

# ─── Étape 3 : Installer youtube-live-ultra dans WSL ──────────────────────────
Write-Host ""
Write-Host "[3/3] Installation de youtube-live-ultra dans WSL..." -ForegroundColor Cyan
Write-Host ""

Write-Host "  Ouvre un terminal WSL (tape 'wsl' dans PowerShell) puis :" -ForegroundColor White
Write-Host ""
Write-Host "    # Installer les dependances" -ForegroundColor Yellow
Write-Host "    sudo apt update && sudo apt install -y streamlink mpv yt-dlp curl" -ForegroundColor White
Write-Host ""
Write-Host "    # Cloner le projet" -ForegroundColor Yellow
Write-Host "    git clone https://github.com/hexapost-studio/youtube-live-ultra.git ~/youtube-live-ultra" -ForegroundColor White
Write-Host "    cd ~/youtube-live-ultra" -ForegroundColor White
Write-Host ""
Write-Host "    # Verifier l'installation" -ForegroundColor Yellow
Write-Host "    make check" -ForegroundColor White
Write-Host ""
Write-Host "    # Lancer un live !" -ForegroundColor Yellow
Write-Host "    ./watch-resilient.sh 'https://www.youtube.com/watch?v=XXXXXXXXXXX' --mode ultra" -ForegroundColor White
Write-Host ""

Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Note: WSL2 prend en charge l'acceleration GPU (VAAPI)" -ForegroundColor Cyan
Write-Host "  via le driver D3D12 -> Mesa. Les performances sont proches" -ForegroundColor Cyan
Write-Host "  du natif Linux pour le decodage video." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
