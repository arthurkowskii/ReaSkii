param(
    [string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'),
    [switch]$Update,
    [switch]$ToolsOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path -LiteralPath (Join-Path $ResourcePath 'reaper.ini') -PathType Leaf)) {
    throw 'REAPER resource directory not found. Pass -ResourcePath explicitly.'
}
if (Get-Process -Name reaper -ErrorAction SilentlyContinue) { throw 'Close REAPER before installing or updating ReaSkii.' }

# A repository checkout is not a package: dist/ is not versioned, so nothing is built yet.
$manifestPath = Join-Path $root 'manifest.json'
$manifest = if (Test-Path -LiteralPath $manifestPath -PathType Leaf) { Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json } else { $null }
if ($null -eq $manifest -and (Test-Path -LiteralPath (Join-Path $root 'build.py') -PathType Leaf) -and
    -not (Test-Path -LiteralPath (Join-Path $root 'dist/ReaSkii.ReaperThemeZip') -PathType Leaf)) {
    throw "Ce dossier est un clone du dépôt sans paquet construit (dist/ n'est pas versionné). Lance 'python3 build.py', ou utilise le zip de la release."
}

# Key = package-relative path, which is also its key in manifest.json.
# Folder = destination under the REAPER resource directory.
# Repo = where to look when running from a repository checkout instead of the package.
# -ToolsOnly installs the MIDI tools and nothing else: no theme, no adjuster, no theme settings.
$tools = @(
    @{Key='ReaSkii_RegisterTools.lua'; Folder='Scripts\ReaSkii'; Repo='scripts'},
    @{Key='effects/ReaSkii/ReaSkii MIDI LFO.jsfx'; Folder='Effects\ReaSkii'; Repo=$null}
)
$specs = if ($ToolsOnly) {
    $tools
} else {
    @(
        @{Key='ReaSkii.ReaperThemeZip';    Folder='ColorThemes';     Repo='dist'},
        @{Key='ReaSkii_Adjuster.lua';      Folder='Scripts\Cockos';  Repo='scripts'},
        @{Key='ReaSkii_Defaults.lua';      Folder='Scripts\Cockos';  Repo='scripts'},
        @{Key='ReaSkii_ApplyDefaults.lua'; Folder='Scripts\Cockos';  Repo='scripts'}
    ) + $tools
}
foreach ($group in @('midi', 'device')) {
    $folder = Join-Path (Join-Path $root 'scripts') $group
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { throw "Missing package folder: scripts/$group" }
    foreach ($file in @(Get-ChildItem -LiteralPath $folder -Filter '*.lua' -File | Sort-Object Name)) {
        $specs += @{Key="scripts/$group/$($file.Name)"; Folder="Scripts\ReaSkii\$group"; Repo=$null}
    }
}
$files = @()
foreach ($spec in $specs) {
    $leaf = Split-Path -Leaf $spec.Key
    $source = Join-Path $root $spec.Key
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        if (-not $spec.Repo) { throw "Missing package file: $($spec.Key)" }
        $source = Join-Path (Join-Path $root $spec.Repo) $leaf
    }
    $files += @{Source=$source; Target=(Join-Path (Join-Path $ResourcePath $spec.Folder) $leaf); Key=$spec.Key; Changed=$false; Existed=$false}
}

# Preflight the entire payload before modifying anything.
foreach ($f in $files) {
    if (-not (Test-Path -LiteralPath $f.Source -PathType Leaf)) { throw "Missing package file: $($f.Source)" }
    $f.Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Source).Hash
    if ($null -ne $manifest) {
        $entry = $manifest.sha256.PSObject.Properties[$f.Key]
        if ($null -eq $entry) { throw "Package file not listed in the manifest: $($f.Key)" }
        if ($entry.Value -ne $f.Hash.ToLowerInvariant()) { throw "Package hash mismatch: $($f.Key)" }
    }
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
            $f.Backup = Join-Path $backup (Split-Path -Leaf $f.Key)
            [IO.File]::Copy($f.Target, $f.Backup, $false)
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $f.Backup).Hash -ne (Get-FileHash -Algorithm SHA256 -LiteralPath $f.Target).Hash) { throw "Backup mismatch: $($f.Target)" }
        }
    }
    $settings = Join-Path $ResourcePath 'reaper-themeconfig.ini'
    if (-not $ToolsOnly -and (Test-Path -LiteralPath $settings -PathType Leaf)) { [IO.File]::Copy($settings, (Join-Path $backup 'reaper-themeconfig.ini'), $false) }
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
if ($ToolsOnly) {
    Write-Output ("Installed {0} tool file(s), {1} updated. No theme, no adjuster, no theme settings touched." -f $files.Count, $changed.Count)
    Write-Output 'Run Scripts\ReaSkii\ReaSkii_RegisterTools.lua once from the Action List to declare the MIDI Panel and Device Rack actions.'
} else {
    Write-Output ("Installed {0} file(s), {1} updated." -f $files.Count, $changed.Count)
    Write-Output 'Installed without activating the theme. Select Options > Themes > ReaSkii, then open Theme adjuster.'
    Write-Output 'Tools: run Scripts\ReaSkii\ReaSkii_RegisterTools.lua once from the Action List to declare the MIDI Panel and Device Rack actions.'
    Write-Output 'The adjuster applies new defaults once, with another restore backup. No project or original reARK/Reapertips theme was modified.'
}
