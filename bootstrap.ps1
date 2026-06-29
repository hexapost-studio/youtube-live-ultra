<#
.SYNOPSIS
  youtube-live-ultra — installeur Windows natif (ylu.exe), facile et resilient.
.DESCRIPTION
  Chemin facile  : telecharge ylu.exe depuis la derniere GitHub Release + installe
                   les dependances (mpv via Scoop/Choco, streamlink, yt-dlp).
  Resilient      : si la Release est indisponible, compile depuis les sources
                   (installe Go au besoin). mpv est tente via plusieurs methodes.
.PARAMETER Wsl
  Affiche la methode de repli WSL2 (scripts Bash) et quitte.
.PARAMETER Build
  Force la compilation depuis les sources (ignore la Release).
.EXAMPLE
  .\bootstrap.ps1
.EXAMPLE
  .\bootstrap.ps1 -Build
.EXAMPLE
  .\bootstrap.ps1 -Wsl
#>
param(
    [switch]$Wsl,
    [switch]$Build,
    [string]$Repo = 'hexapost-studio/youtube-live-ultra'
)

$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host "  $m"   -ForegroundColor White }
function Ok($m)   { Write-Host "  OK $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  ! $m"  -ForegroundColor Yellow }
function Step($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Have($cmd) { return [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

Write-Host "================================================================" -ForegroundColor Green
Write-Host "  youtube-live-ultra — Windows (ylu.exe natif)" -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green

# ─── Repli WSL2 ──────────────────────────────────────────────────────────────
if ($Wsl) {
    Step "[WSL2] Methode de repli (scripts Bash)"
    Info "1) wsl --install            (PowerShell admin, puis redemarrer)"
    Info "2) sudo apt update && sudo apt install -y streamlink mpv yt-dlp curl"
    Info "3) git clone https://github.com/$Repo.git ~/youtube-live-ultra"
    Info "4) cd ~/youtube-live-ultra && ./watch-resilient.sh '<URL>' --mode ultra"
    exit 0
}

$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$hasWinget = Have winget
$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }

# ─── 1. Dependances runtime ──────────────────────────────────────────────────
Step "[1/3] Dependances runtime (mpv, streamlink, yt-dlp)"

function Install-Scoop {
    if (Have scoop) { return }
    Warn "Installation de Scoop (gestionnaire non-admin)..."
    try {
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
        Invoke-RestMethod -Uri 'https://get.scoop.sh' | Invoke-Expression
    } catch { Warn "Echec installation Scoop : $($_.Exception.Message)" }
}

function Ensure-ScoopExtras {
    if (-not (Have scoop)) { return }
    if ((scoop bucket list 2>$null) -notmatch 'extras') { scoop bucket add extras | Out-Null }
}

# mpv n'a pas de paquet winget fournissant 'mpv.exe' (mpv.net -> mpvnet.exe).
# On privilegie Scoop/Choco qui exposent le vrai binaire 'mpv'.
function Ensure-Mpv {
    if (Have mpv) { Ok "mpv deja present"; return }
    Info "Installation de mpv..."
    if (Have scoop)      { Ensure-ScoopExtras; scoop install mpv | Out-Null }
    elseif (Have choco)  { choco install mpv -y | Out-Null }
    else                 { Install-Scoop; if (Have scoop) { Ensure-ScoopExtras; scoop install mpv | Out-Null } }

    if (Have mpv)         { Ok "mpv installe" }
    elseif (Have mpvnet)  { Warn "mpv.net detecte mais 'mpv' absent du PATH. Installe le vrai mpv : scoop install mpv" }
    else                  { Warn "mpv introuvable. Voir https://mpv.io/installation/ (ou 'scoop install mpv')" }
}

# winget en premier ; Scoop en repli (les deux exposent le binaire attendu).
function Ensure-Tool($name, $wingetId, $scoopId) {
    if (Have $name) { Ok "$name deja present"; return }
    Info "Installation de $name..."
    if ($hasWinget) {
        winget install --id $wingetId -e --accept-source-agreements --accept-package-agreements | Out-Null
    }
    if (-not (Have $name) -and (Have scoop)) { scoop install $scoopId | Out-Null }
    if (Have $name) { Ok "$name installe" } else { Warn "$name introuvable apres tentative ($wingetId)" }
}

Ensure-Mpv
Ensure-Tool 'streamlink' 'Streamlink.Streamlink' 'streamlink'
Ensure-Tool 'yt-dlp'     'yt-dlp.yt-dlp'         'yt-dlp'

# Rafraichir le PATH de la session (les installeurs modifient le PATH persistant)
$env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
            [System.Environment]::GetEnvironmentVariable('Path', 'User')

# ─── 2. Obtenir ylu.exe ──────────────────────────────────────────────────────
Step "[2/3] Recuperation de ylu.exe (architecture : $arch)"

$target = Join-Path $scriptDir 'ylu.exe'

function Get-FromRelease {
    $asset = "ylu-windows-$arch.exe"
    try {
        $rel = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                                 -Headers @{ 'User-Agent' = 'ylu-bootstrap' }
        $url = ($rel.assets | Where-Object { $_.name -eq $asset } | Select-Object -First 1).browser_download_url
        if (-not $url) { Warn "Asset $asset absent de la derniere release."; return $false }
        Info "Telechargement de $asset ..."
        Invoke-WebRequest -Uri $url -OutFile $target -UseBasicParsing
        return (Test-Path $target)
    } catch {
        Warn "Pas de release telechargeable ($($_.Exception.Message))."
        return $false
    }
}

function Build-FromSource {
    if (-not (Test-Path (Join-Path $scriptDir 'go.mod'))) {
        Warn "Sources Go absentes ici. Clone la branche go :"
        Warn "  git clone -b go https://github.com/$Repo.git"
        return $false
    }
    if (-not (Have go)) {
        Info "Go absent — installation via winget..."
        if ($hasWinget) {
            winget install --id GoLang.Go -e --accept-source-agreements --accept-package-agreements | Out-Null
            Warn "Go installe. RELANCE ce script dans un NOUVEAU terminal pour finir le build."
            exit 0
        } else { Warn "Installe Go : https://go.dev/dl/ puis relance."; return $false }
    }
    Push-Location $scriptDir
    try { go build -trimpath -o ylu.exe . ; return ($LASTEXITCODE -eq 0) }
    finally { Pop-Location }
}

if ($Build) {
    Info "Mode -Build : compilation depuis les sources."
    $got = Build-FromSource
} else {
    $got = Get-FromRelease
    if (-not $got) { Info "Repli : compilation depuis les sources..."; $got = Build-FromSource }
}

if (-not $got) {
    Warn "Impossible d'obtenir ylu.exe (ni release, ni build). Voir messages ci-dessus."
    exit 1
}
Ok "ylu.exe pret : $target"

# ─── 3. Verification ─────────────────────────────────────────────────────────
Step "[3/3] Verification"
& $target check

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "  Pret. Lancer un live :" -ForegroundColor Green
Write-Host "    .\ylu.exe watch --mode ultra `"https://www.youtube.com/watch?v=XXXXXXXXXXX`"" -ForegroundColor White
Write-Host "  GPU Windows : d3d11va (auto). IPC mpv : named pipe (resilient/dashboard/tui)." -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Green
