# Installs the ReaSkii MIDI tools only: no theme, no adjuster, no theme settings.
# Usage, with REAPER closed:
#   irm https://raw.githubusercontent.com/arthurkowskii/ReaSkii/main/Get-ReaSkiiTools.ps1 | iex
# The main bootstrap is downloaded first so this file never duplicates its logic.
$ErrorActionPreference = 'Stop'
$source = 'https://raw.githubusercontent.com/arthurkowskii/ReaSkii/main/Get-ReaSkii.ps1'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('Get-ReaSkii-' + [guid]::NewGuid().ToString('N') + '.ps1')
try {
    Invoke-WebRequest -Uri $source -OutFile $temp -UseBasicParsing
    & $temp -ToolsOnly
} finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
}
