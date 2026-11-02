param(
    [string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'),
    [switch]$Update
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $ResourcePath 'reaper.ini') -PathType Leaf)) {
    throw 'REAPER resource directory not found. Pass -ResourcePath explicitly.'
}
if (Get-Process -Name reaper -ErrorAction SilentlyContinue) { throw 'Close REAPER before installing or updating ReaSkii.' }
$files = @()
foreach ($name in @('ReaSkii.ReaperThemeZip','ReaSkii_Adjuster.lua','ReaSkii_Defaults.lua','ReaSkii_ApplyDefaults.lua')) {
    $source = Join-Path $root $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        $source = Join-Path (Join-Path $root $(if ($name -like '*.lua') {'scripts'} else {'dist'})) $name
    }
    $folder = if ($name -like '*.lua') {'Scripts\Cockos'} else {'ColorThemes'}
    $files += @{Source=$source; Target=(Join-Path (Join-Path $ResourcePath $folder) $name); Name=$name; Changed=$false; Existed=$false}
}
# Preflight the entire payload before modifying anything.
$manifestPath = Join-Path $root 'manifest.json'
$manifest = if (Test-Path -LiteralPath $manifestPath) { Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } else { $null }
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f.Source -PathType Leaf)) { throw "Missing package file: $($f.Source)" }
    $f.Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Source).Hash
    if ($null -ne $manifest -and $manifest.sha256.($f.Name) -ne $f.Hash.ToLowerInvariant()) { throw "Package hash mismatch: $($f.Name)" }
    if ((Test-Path -LiteralPath $f.Target) -and -not (Test-Path -LiteralPath $f.Target -PathType Leaf)) { throw "Destination is not a file: $($f.Target)" }
    $f.Existed = Test-Path -LiteralPath $f.Target -PathType Leaf
    $f.Changed = (-not $f.Existed) -or (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash -ne $f.Hash
    if ($f.Existed -and $f.Changed -and -not $Update) { throw "Existing installation differs. Run with -Update for a backed-up upgrade: $($f.Target)" }
}
$backup = Join-Path $ResourcePath ('ReaSkii-backups\install-' + [guid]::NewGuid().ToString('N'))
$changed = @($files | Where-Object {$_.Changed})
if ($changed.Count) {
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($f in $changed) {
        if ($f.Existed) {
            $f.Backup = Join-Path $backup $f.Name
            [IO.File]::Copy($f.Target, $f.Backup, $false)
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $f.Backup).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash) { throw "Backup mismatch: $($f.Target)" }
        }
    }
    $settings = Join-Path $ResourcePath 'reaper-themeconfig.ini'
    if (Test-Path -LiteralPath $settings -PathType Leaf) { [IO.File]::Copy($settings, (Join-Path $backup 'reaper-themeconfig.ini'), $false) }
    $written = @()
    try {
        foreach ($f in $changed) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $f.Target) -Force | Out-Null
            $written += $f
            [IO.File]::Copy($f.Source, $f.Target, $true)
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash -ne $f.Hash) { throw "Installed hash mismatch: $($f.Target)" }
        }
    } catch {
        $failure = $_
        foreach ($f in $written) {
            if ($f.Existed) { [IO.File]::Copy($f.Backup, $f.Target, $true) }
            elseif (Test-Path -LiteralPath $f.Target) { Remove-Item -LiteralPath $f.Target }
        }
        throw $failure
    }
    Write-Output "Backup: $backup"
}
foreach ($f in $files) { [pscustomobject]@{Path=$f.Target; SHA256=(Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash} }
Write-Output 'Installed without activating the theme. Select Options > Themes > ReaSkii, then open Theme adjuster.'
Write-Output 'The adjuster applies new defaults once, with another restore backup. No project or original reARK/Reapertips theme was modified.'
