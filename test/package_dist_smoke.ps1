$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('ja-package-test-' + [guid]::NewGuid())
$release=Join-Path $root 'build\windows\x64\runner\Release'
New-Item -ItemType Directory -Path (Join-Path $release 'data'),(Join-Path $root 'dist') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Value 'version: 1.2.0+3'
Add-Type -TypeDefinition '[assembly:System.Reflection.AssemblyInformationalVersion("1.2.0+3")] public class PackageFixture { public static void Main() {} }' -OutputAssembly (Join-Path $release 'ja_lan_messenger.exe') -OutputType WindowsApplication
foreach ($name in @('flutter_windows.dll','desktop_drop_plugin.dll','data\app.so','data\icudtl.dat','update_config.json','user_preferences.json')) { Set-Content -LiteralPath (Join-Path $release $name) -Value 'fixture' }
foreach ($name in @('install.bat','uninstall.bat','uninstall.ps1')) { Set-Content -LiteralPath (Join-Path $root $name) -Value 'fixture' }
Set-Content -LiteralPath (Join-Path $root 'dist\keep.txt') -Value 'existing output'
$packager=Join-Path (Split-Path $PSScriptRoot -Parent) 'windows\packaging\package_dist.ps1'
& $packager -ProjectRoot $root
if (-not (Test-Path -LiteralPath (Join-Path $release 'update_config.json'))) { throw 'Source modified' }
if (Test-Path -LiteralPath (Join-Path $root 'dist\update_config.json')) { throw 'Runtime configuration leaked' }
$stageDirs = Get-ChildItem -LiteralPath $root -Directory -Filter '.package-stage-*'
if ($stageDirs.Count -gt 0) { throw 'Staging directory was not cleaned up' }
$prevDirs = Get-ChildItem -LiteralPath $root -Directory -Filter 'dist.previous-*'
if ($prevDirs.Count -gt 0) { throw 'Previous dist directory was not cleaned up' }
$zip=Get-ChildItem -LiteralPath (Join-Path $root 'dist') -Filter '*.zip'
$before=(Get-FileHash -LiteralPath $zip.FullName).Hash
Set-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Value 'version: 1.3.0+4'
$failed=$false
try { & $packager -ProjectRoot $root } catch { $failed=$true }
if (-not $failed -or (Get-FileHash -LiteralPath $zip.FullName).Hash -ne $before) { throw 'Stale build failed to preserve output' }
Write-Host "PASS: packaging, ZIP verification, runtime exclusion, retained output, stale version rejection. $root"
