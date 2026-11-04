param([Parameter(Mandatory=$true)][string]$Sandbox,[string]$PackageRoot,[string]$PackageZip)
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
$register = Join-Path $resource 'Scripts/ReaSkii/ReaSkii_RegisterTools.lua'
Check ((Get-FileHash -LiteralPath $register).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repo 'scripts/ReaSkii_RegisterTools.lua')).Hash) 'register tool installed'
$toolCount = 0
foreach ($group in @('midi','device')) {
 foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $repo "scripts/$group") -Filter '*.lua' -File)) {
  $toolCount++
  $installed = Join-Path $resource "Scripts/ReaSkii/$group/$($file.Name)"
  Check ((Test-Path -LiteralPath $installed -PathType Leaf) -and ((Get-FileHash -LiteralPath $installed).Hash -eq (Get-FileHash -LiteralPath $file.FullName).Hash)) "tool installed: $group/$($file.Name)"
 }
}
Check ($toolCount -ge 2) "tool groups are not empty ($toolCount scripts)"
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
# Running from a repository checkout with no built package must name the build step, not fail obscurely.
$checkout=Join-Path $Sandbox ('checkout-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $checkout 'scripts') -Force | Out-Null
Copy-Item -LiteralPath $installer -Destination $checkout
[IO.File]::WriteAllText((Join-Path $checkout 'build.py'),'# build')
foreach ($group in @('midi','device')) { Copy-Item -LiteralPath (Join-Path $repo "scripts/$group") -Destination (Join-Path $checkout 'scripts') -Recurse -Force }
$message=$null
try { & (Join-Path $checkout 'Install-ReaSkii.ps1') -ResourcePath $resource } catch { $message=$_.Exception.Message }
Check ($message -match 'python3 build\.py') 'checkout without a built package points to build.py'
# Manifest integrity: a packaged file that the manifest does not list must be refused before any write.
$zip=if ($PackageZip) {$PackageZip} else {@(Get-ChildItem -LiteralPath (Join-Path $repo 'dist') -Filter 'ReaSkii-v*.zip' -File | Sort-Object Name | Select-Object -Last 1)[0].FullName}
Check (Test-Path -LiteralPath $zip -PathType Leaf) "built package available for manifest checks ($zip)"
$pkg=Join-Path $Sandbox ('pkg-' + [guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $zip -DestinationPath $pkg
$manifestPath=Join-Path $pkg 'manifest.json'
$manifest=Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
$dropped=@($manifest.sha256.PSObject.Properties.Name | Where-Object {$_ -like 'scripts/midi/*'})[0]
Check ([bool]$dropped) 'package manifest lists MIDI tool scripts'
$manifest.sha256.PSObject.Properties.Remove($dropped)
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath
$target=Join-Path $Sandbox ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $target | Out-Null
[IO.File]::WriteAllText((Join-Path $target 'reaper.ini'),'[REAPER]')
MustThrow { & (Join-Path $pkg 'Install-ReaSkii.ps1') -ResourcePath $target -Update } "file missing from manifest refused ($dropped)"
Check (-not (Test-Path -LiteralPath (Join-Path $target 'ColorThemes/ReaSkii.ReaperThemeZip'))) 'manifest refusal causes no partial installation'
Write-Output 'DONE: parser and installer sandbox checks passed (PowerShell host, not Windows REAPER runtime)'
