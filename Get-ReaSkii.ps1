param(
    [string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'),
    [string]$Package = 'https://github.com/arthurkowskii/ReaSkii/releases/latest/download/ReaSkii.zip',
    [switch]$Keep
)
# Fetches the latest published ReaSkii package and runs its installer with -Update.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\Get-ReaSkii.ps1
# $Package also accepts a local .zip path, for an offline install from a USB key.
$ErrorActionPreference = 'Stop'
if (Get-Process -Name reaper -ErrorAction SilentlyContinue) { throw 'Close REAPER before updating ReaSkii.' }
if (-not (Test-Path -LiteralPath (Join-Path $ResourcePath 'reaper.ini') -PathType Leaf)) {
    throw 'REAPER resource directory not found. Pass -ResourcePath explicitly.'
}

$work = Join-Path ([IO.Path]::GetTempPath()) ('reaskii-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $archive = Join-Path $work 'ReaSkii.zip'
    if (Test-Path -LiteralPath $Package -PathType Leaf) {
        Copy-Item -LiteralPath $Package -Destination $archive
    } else {
        try {
            Invoke-WebRequest -Uri $Package -OutFile $archive -UseBasicParsing
        } catch {
            throw "Téléchargement impossible depuis $Package. Vérifie qu'une release publiée contient l'asset ReaSkii.zip. Détail : $($_.Exception.Message)"
        }
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $work -Force
    $manifestPath = Join-Path $work 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Package has no manifest.json' }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    Write-Output ("ReaSkii {0} (theme {1})" -f $manifest.version, $manifest.theme_version)
    & (Join-Path $work 'Install-ReaSkii.ps1') -ResourcePath $ResourcePath -Update
} finally {
    if (-not $Keep) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
