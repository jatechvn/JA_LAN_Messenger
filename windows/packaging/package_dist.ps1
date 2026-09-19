<#
.SYNOPSIS
    Packages the compiled Flutter Windows Release output into the dist/ directory
    following the JA-Tech dart-build-pro standard.
#>
[CmdletBinding()]
param (
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
    if (-not $scriptDir) { $scriptDir = $PSScriptRoot }
    $root = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
} else {
    $root = (Resolve-Path $ProjectRoot).Path
}
$pubspecPath = Join-Path $root "pubspec.yaml"
if (-not (Test-Path $pubspecPath)) {
    throw "Cannot find pubspec.yaml at $pubspecPath"
}

# 1. Parse Version
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match '(?m)^version:\s*([0-9]+\.[0-9]+\.[0-9]+)') {
    $version = $Matches[1]
} else {
    throw "Unable to extract semantic version from pubspec.yaml"
}
Write-Host "[PACKAGE] Target Application Version: $version" -ForegroundColor Cyan

# 2. Paths
$relDir = Join-Path $root "build\windows\x64\runner\Release"
$distDir = Join-Path $root "dist"
$packDir = Join-Path $root "dist_pack"
$pkgName = "JA_LAN_Messenger_v$($version)_Windows_x64"

if (-not (Test-Path (Join-Path $relDir "ja_lan_messenger.exe"))) {
    throw "Release binary not found at $relDir\ja_lan_messenger.exe. Please build first!"
}

# 3. Clean runtime leftovers from Release
foreach ($junk in @("config.json", "config.ini", "app_preferences.json")) {
    $jPath = Join-Path $relDir $junk
    if (Test-Path $jPath) { Remove-Item -Force $jPath }
}
$logPath = Join-Path $relDir "logs"
if (Test-Path $logPath) { Remove-Item -Recurse -Force $logPath }

# 4. Sync auxiliary scripts and docs into Release directory
$docFiles = @(
    "debug.bat", "install.bat", "uninstall.bat", "uninstall.ps1",
    "ABOUT.txt", "README.md", "CHANGELOG.md", "USERGUIDE.md",
    "RELEASE_NOTES.md", "LICENSE"
)
foreach ($doc in $docFiles) {
    $src = Join-Path $root $doc
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination $relDir -Force
    }
}

# 5. Clean dist directory completely
Write-Host "[PACKAGE] Refreshing dist/ directory..." -ForegroundColor Cyan
if (-not (Test-Path $distDir)) {
    New-Item -ItemType Directory -Path $distDir -Force | Out-Null
} else {
    Get-ChildItem -Path $distDir -Force | Remove-Item -Recurse -Force
}

# 6. Copy Release directory contents to dist
Write-Host "[PACKAGE] Copying compiled files and assets from Release to dist/..." -ForegroundColor Cyan
Copy-Item -Path (Join-Path $relDir "*") -Destination $distDir -Recurse -Force

# 7. Package ZIP wrapped in Parent Folder
Write-Host "[PACKAGE] Packaging ZIP with parent folder: $pkgName..." -ForegroundColor Cyan
if (Test-Path $packDir) { Remove-Item -Recurse -Force $packDir }
$nestedTarget = Join-Path $packDir $pkgName
New-Item -ItemType Directory -Path $nestedTarget -Force | Out-Null

Copy-Item -Path (Join-Path $distDir "*") -Destination $nestedTarget -Recurse -Force -Exclude "*.zip"

$zipFile = Join-Path $distDir "$pkgName.zip"
if (Test-Path $zipFile) { Remove-Item -Force $zipFile }
Compress-Archive -Path (Join-Path $packDir "*") -DestinationPath $zipFile -Force
Remove-Item -Recurse -Force $packDir

# 8. Checksum calculation
$hash = (Get-FileHash -Path $zipFile -Algorithm SHA256).Hash
$checksumPath = Join-Path $distDir "SHA256SUMS.txt"
Set-Content -Path $checksumPath -Value "$hash *$pkgName.zip"

Write-Host "========================================================" -ForegroundColor Green
Write-Host "[SUCCESS] Packaging completed successfully!" -ForegroundColor Green
Write-Host "  - Dist folder : $distDir"
Write-Host "  - Zip package : $zipFile"
Write-Host "  - Package size: $((Get-Item $zipFile).Length) bytes"
Write-Host "  - SHA256      : $hash"
Write-Host "========================================================" -ForegroundColor Green
