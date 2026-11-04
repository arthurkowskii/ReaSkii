param(
    [string]$ResourcePath = (Join-Path $env:APPDATA 'REAPER'),
    [switch]$Update
)
# Installs the ReaSkii MIDI tools only: no theme, no adjuster, no theme settings.
# Same preflight, hashes, backup and rollback as the full installer.
$ErrorActionPreference = 'Stop'
$installer = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'Install-ReaSkii.ps1'
if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw "Missing installer next to this file: $installer" }
& $installer -ResourcePath $ResourcePath -Update:$Update -ToolsOnly
