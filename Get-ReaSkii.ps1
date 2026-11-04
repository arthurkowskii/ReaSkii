param(
    [string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'),
    [string]$Package = '',
    [switch]$ToolsOnly,
    [switch]$Keep
)
# Fetches the latest published ReaSkii package and runs its installer with -Update.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\Get-ReaSkii.ps1
#        powershell -NoProfile -ExecutionPolicy Bypass -File .\Get-ReaSkii.ps1 -ToolsOnly
# -ToolsOnly installs the MIDI tools without the theme, the adjuster or any theme setting.
# $Package also accepts a local .zip path, for an offline install from a USB key.
$ErrorActionPreference = 'Stop'
if (Get-Process -Name reaper -ErrorAction SilentlyContinue) { throw 'Close REAPER before updating ReaSkii.' }
if (-not (Test-Path -LiteralPath (Join-Path $ResourcePath 'reaper.ini') -PathType Leaf)) {
    throw 'REAPER resource directory not found. Pass -ResourcePath explicitly.'
}
$asset = if ($ToolsOnly) { 'ReaSkiiTools.zip' } else { 'ReaSkii.zip' }
if (-not $Package) { $Package = "https://github.com/arthurkowskii/ReaSkii/releases/latest/download/$asset" }

$work = Join-Path ([IO.Path]::GetTempPath()) ('reaskii-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    $archive = Join-Path $work $asset
    if (Test-Path -LiteralPath $Package -PathType Leaf) {
        Copy-Item -LiteralPath $Package -Destination $archive
    } else {
        try {
            Invoke-WebRequest -Uri $Package -OutFile $archive -UseBasicParsing
        } catch {
            throw "Téléchargement impossible depuis $Package. Vérifie qu'une release publiée contient l'asset $asset. Détail : $($_.Exception.Message)"
        }
    }
    Expand-Archive -LiteralPath $archive -DestinationPath $work -Force
    $manifestPath = Join-Path $work 'manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Package has no manifest.json' }
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    if ($manifest.PSObject.Properties['theme_version']) {
        Write-Output ("ReaSkii {0} (theme {1})" -f $manifest.version, $manifest.theme_version)
    } else {
        Write-Output ("ReaSkii tools {0}" -f $manifest.version)
    }
    $installer = if ($ToolsOnly) { 'Install-ReaSkiiTools.ps1' } else { 'Install-ReaSkii.ps1' }
    & (Join-Path $work $installer) -ResourcePath $ResourcePath -Update
} finally {
    if (-not $Keep) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
