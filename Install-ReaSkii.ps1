param([string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'))
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$theme = Join-Path $root 'ReaSkii.ReaperThemeZip'
if (-not (Test-Path -LiteralPath $theme)) { $theme = Join-Path $root 'dist\ReaSkii.ReaperThemeZip' }
$adjuster = Join-Path $root 'ReaSkii_Adjuster.lua'
if (-not (Test-Path -LiteralPath $adjuster)) { $adjuster = Join-Path $root 'scripts\ReaSkii_Adjuster.lua' }
if (-not (Test-Path -LiteralPath (Join-Path $ResourcePath 'reaper.ini'))) { throw 'REAPER resource directory not found. Pass -ResourcePath explicitly.' }
$files = @(
    @{Source=$theme; Target=(Join-Path $ResourcePath 'ColorThemes\ReaSkii.ReaperThemeZip')},
    # REAPER resolves adjuster_script by filename inside Scripts/Cockos.
    @{Source=$adjuster; Target=(Join-Path $ResourcePath 'Scripts\Cockos\ReaSkii_Adjuster.lua')}
)
# Preflight every destination before copying either file; never overwrite a differing installation.
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f.Source -PathType Leaf)) { throw "Missing package file: $($f.Source)" }
    $f.Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Source).Hash
    if ((Test-Path -LiteralPath $f.Target) -and (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash -ne $f.Hash) {
        throw "Existing installation differs, preserve it before updating: $($f.Target)"
    }
}
foreach ($f in $files) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $f.Target) -Force | Out-Null
    if (-not (Test-Path -LiteralPath $f.Target)) { [IO.File]::Copy($f.Source, $f.Target, $false) }
    $actual = Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target
    if ($actual.Hash -ne $f.Hash) { throw "Installed hash mismatch: $($f.Target)" }
    [pscustomobject]@{Path=$f.Target;SHA256=$actual.Hash}
}
Write-Output 'Installed without activating the theme. Select Options > Themes > ReaSkii when ready.'
Write-Output 'The original reARK X theme, projects and REAPER settings were not modified.'
