param([Parameter(Mandatory=$true)][string]$Sandbox,[string]$PackageRoot)
$ErrorActionPreference='Stop'
if ($Sandbox -notmatch 'reaskii-installer-qa') { throw 'Use an isolated reaskii-installer-qa sandbox' }
$repo=if ($PackageRoot) {$PackageRoot} else {Split-Path -Parent $PSScriptRoot}
function SourceFile($Name) {
 $direct=Join-Path $repo $Name
 if (Test-Path -LiteralPath $direct -PathType Leaf) { return $direct }
 $folder=if ($Name -like '*.lua') {'scripts'} else {'dist'}
 return Join-Path (Join-Path $repo $folder) $Name
}
$installer=Join-Path $repo 'Install-ReaSkii.ps1'
$tokens=$null;$errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($installer,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count) { throw ($errors | Out-String) }
function Check($Ok,$Label) { if (-not $Ok) { throw "FAIL: $Label" }; Write-Output "PASS: $Label" }
function MustThrow([scriptblock]$Action,$Label) { $caught=$false;try { & $Action | Out-Null } catch { $caught=$true };Check $caught $Label }
New-Item -ItemType Directory -Path $Sandbox -Force | Out-Null
$resource=Join-Path $Sandbox ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $resource | Out-Null
[IO.File]::WriteAllText((Join-Path $resource 'reaper.ini'),'[REAPER]')
[IO.File]::WriteAllText((Join-Path $resource 'reaper-themeconfig.ini'),'[Original-theme]keep=1')
$settingsHash=(Get-FileHash -LiteralPath (Join-Path $resource 'reaper-themeconfig.ini')).Hash
& $installer -ResourcePath $resource | Out-Null
$theme=Join-Path $resource 'ColorThemes/ReaSkii.ReaperThemeZip'
$expected=(Get-FileHash -LiteralPath (SourceFile 'ReaSkii.ReaperThemeZip')).Hash
Check ((Get-FileHash -LiteralPath $theme).Hash -eq $expected) 'fresh installation hash'
foreach ($name in @('ReaSkii_Adjuster.lua','ReaSkii_Defaults.lua','ReaSkii_ApplyDefaults.lua')) {
 Check ((Get-FileHash -LiteralPath (Join-Path $resource "Scripts/Cockos/$name")).Hash -eq (Get-FileHash -LiteralPath (SourceFile $name)).Hash) "script installed: $name"
}
$before=@(Get-ChildItem -LiteralPath (Join-Path $resource 'ReaSkii-backups') -Directory).Count
& $installer -ResourcePath $resource | Out-Null
Check (@(Get-ChildItem -LiteralPath (Join-Path $resource 'ReaSkii-backups') -Directory).Count -eq $before) 'identical install is idempotent'
[IO.File]::WriteAllText($theme,'old installed version sentinel')
$oldHash=(Get-FileHash -LiteralPath $theme).Hash
MustThrow { & $installer -ResourcePath $resource } 'different install refused without -Update'
Check ((Get-FileHash -LiteralPath $theme).Hash -eq $oldHash) 'refusal preserves existing bytes'
& $installer -ResourcePath $resource -Update | Out-Null
Check ((Get-FileHash -LiteralPath $theme).Hash -eq $expected) 'explicit update installs current bytes'
$backups=@(Get-ChildItem -LiteralPath (Join-Path $resource 'ReaSkii-backups') -Filter 'ReaSkii.ReaperThemeZip' -Recurse)
Check (@($backups | Where-Object {(Get-FileHash -LiteralPath $_.FullName).Hash -eq $oldHash}).Count -eq 1) 'old version backed up byte-for-byte'
Check ((Get-FileHash -LiteralPath (Join-Path $resource 'reaper-themeconfig.ini')).Hash -eq $settingsHash) 'live settings untouched'
$bad=Join-Path $resource 'bad-package';New-Item -ItemType Directory -Path $bad | Out-Null
[IO.File]::Copy($installer,(Join-Path $bad 'Install-ReaSkii.ps1'))
[IO.File]::Copy($theme,(Join-Path $bad 'ReaSkii.ReaperThemeZip'))
MustThrow { & (Join-Path $bad 'Install-ReaSkii.ps1') -ResourcePath $resource -Update } 'incomplete package refused before writes'
Check ((Get-FileHash -LiteralPath $theme).Hash -eq $expected) 'incomplete package leaves installed theme unchanged'
$collision=Join-Path $resource 'collision';New-Item -ItemType Directory -Path (Join-Path $collision 'Scripts/Cockos/ReaSkii_Adjuster.lua') -Force | Out-Null
[IO.File]::WriteAllText((Join-Path $collision 'reaper.ini'),'[REAPER]')
MustThrow { & $installer -ResourcePath $collision -Update } 'directory collision refused in preflight'
Check (-not (Test-Path -LiteralPath (Join-Path $collision 'ColorThemes/ReaSkii.ReaperThemeZip'))) 'directory collision causes no partial installation'
Write-Output 'DONE: parser and installer sandbox checks passed (PowerShell host, not Windows REAPER runtime)'
