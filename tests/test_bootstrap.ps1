param([Parameter(Mandatory=$true)][string]$Sandbox,[string]$PackageZip)
$ErrorActionPreference='Stop'
if ($Sandbox -notmatch 'reaskii-installer-qa') { throw 'Use an isolated reaskii-installer-qa sandbox' }
$repo=Split-Path -Parent $PSScriptRoot
function Check($Ok,$Label) { if (-not $Ok) { throw "FAIL: $Label" }; Write-Output "PASS: $Label" }
function MustThrow([scriptblock]$Action,$Label) { $caught=$false;try { & $Action | Out-Null } catch { $caught=$true };Check $caught $Label }
New-Item -ItemType Directory -Path $Sandbox -Force | Out-Null
$zip=if ($PackageZip) {$PackageZip} else {@(Get-ChildItem -LiteralPath (Join-Path $repo 'dist') -Filter 'ReaSkii-v*.zip' -File | Sort-Object Name | Select-Object -Last 1)[0].FullName}
$bootstrap=Join-Path $repo 'Get-ReaSkii.ps1'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($bootstrap,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw ($errors | Out-String) }

$resource=Join-Path $Sandbox ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resource | Out-Null
[IO.File]::WriteAllText((Join-Path $resource 'reaper.ini'),'[REAPER]')
$out=& $bootstrap -ResourcePath $resource -Package $zip
Check ((Get-FileHash -LiteralPath (Join-Path $resource 'ColorThemes/ReaSkii.ReaperThemeZip')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo 'dist/ReaSkii.ReaperThemeZip')).Hash) 'bootstrap installs the theme'
Check (Test-Path -LiteralPath (Join-Path $resource 'Scripts/ReaSkii/midi/ReaSkii_MIDI_Panel.lua') -PathType Leaf) 'bootstrap installs the MIDI panel'
Check (Test-Path -LiteralPath (Join-Path $resource 'Scripts/ReaSkii/device/ReaSkii_DeviceRack.lua') -PathType Leaf) 'bootstrap installs the device rack'
Check (Test-Path -LiteralPath (Join-Path $resource 'Scripts/ReaSkii/ReaSkii_RegisterTools.lua') -PathType Leaf) 'bootstrap installs the register tool'
Check ([bool](@($out) -match '^ReaSkii \d')) 'bootstrap reports the package version'

$out2=& $bootstrap -ResourcePath $resource -Package $zip
Check ([bool](@($out2) -match '0 updated')) 'bootstrap update is idempotent'

$bad=Join-Path $Sandbox ('bad-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $bad | Out-Null
[IO.File]::WriteAllText((Join-Path $bad 'dummy.txt'),'x')
$badZip=Join-Path $Sandbox ('no-manifest-' + [guid]::NewGuid().ToString('N') + '.zip')
Compress-Archive -Path (Join-Path $bad '*') -DestinationPath $badZip
MustThrow { & $bootstrap -ResourcePath $resource -Package $badZip } 'package without manifest refused'

$toolsZip=@(Get-ChildItem -LiteralPath (Join-Path $repo 'dist') -Filter 'ReaSkii-Tools-v*.zip' -File | Sort-Object Name | Select-Object -Last 1)[0].FullName
Check (Test-Path -LiteralPath $toolsZip -PathType Leaf) 'tools package available'
$toolsResource=Join-Path $Sandbox ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $toolsResource | Out-Null
[IO.File]::WriteAllText((Join-Path $toolsResource 'reaper.ini'),'[REAPER]')
$outTools=& $bootstrap -ResourcePath $toolsResource -Package $toolsZip -ToolsOnly
Check ([bool](@($outTools) -match '^ReaSkii tools \d')) 'bootstrap reports the tools package'
Check (Test-Path -LiteralPath (Join-Path $toolsResource 'Scripts/ReaSkii/midi/ReaSkii_MIDI_Panel.lua') -PathType Leaf) 'bootstrap tools-only installs the MIDI panel'
Check (Test-Path -LiteralPath (Join-Path $toolsResource 'Effects/ReaSkii/ReaSkii MIDI LFO.jsfx') -PathType Leaf) 'bootstrap tools-only installs the JSFX'
Check (-not (Test-Path -LiteralPath (Join-Path $toolsResource 'ColorThemes'))) 'bootstrap tools-only installs no theme'
Write-Output 'DONE: bootstrap checks passed (PowerShell host, not Windows REAPER runtime)'
