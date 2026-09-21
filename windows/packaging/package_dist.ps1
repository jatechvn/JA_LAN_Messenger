<# Build in a fresh staging directory; retain previous dist and never alter Release. #>
[CmdletBinding()]
param([string]$ProjectRoot = '')
$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Join-Path $PSScriptRoot '..\..' }
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$pubspec = Get-Content -LiteralPath (Join-Path $root 'pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)(?:\+(\d+))?\s*$') { throw 'Invalid package version' }
$version = $Matches[1]
$build = $Matches[2]
$release = Join-Path $root 'build\windows\x64\runner\Release'
$dist = Join-Path $root 'dist'
foreach ($required in @('ja_lan_messenger.exe','flutter_windows.dll','data\app.so','data\icudtl.dat','desktop_drop_plugin.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $release $required) -PathType Leaf)) { throw "Missing runtime: $required" }
}
$binaryVersion = (Get-Item -LiteralPath (Join-Path $release 'ja_lan_messenger.exe')).VersionInfo.ProductVersion
$expected = if ($build) { "$version+$build" } else { $version }
if ($binaryVersion -ne $expected) { throw "Stale Release binary: $binaryVersion; expected $expected" }
foreach ($path in @($release, $dist)) {
    if (Test-Path -LiteralPath $path) {
        $item = Get-Item -LiteralPath $path -Force
        for ($parent = $item; $parent; $parent = $parent.Parent) {
            if ($parent.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked packaging path refused: $path" }
        }
    }
}
$id = [guid]::NewGuid().ToString('N')
$stage = Join-Path $root ('.package-stage-' + $id)
$packageName = "JA_LAN_Messenger_v${version}_Windows_x64"
$payload = Join-Path $stage $packageName
$output = Join-Path $stage 'output'
New-Item -ItemType Directory -Path $payload,$output | Out-Null
# Only distribute runtime binaries/assets and explicitly named project documents.
$runtime = @(Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Name -eq 'ja_lan_messenger.exe' -or $_.Extension -eq '.dll' })
if (Get-ChildItem -LiteralPath (Join-Path $release 'data') -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }) { throw 'Linked assets refused' }
$runtime += @(Get-ChildItem -LiteralPath (Join-Path $release 'data') -Recurse -File -Force)
foreach ($file in $runtime) {
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked payload refused' }
    $relative = $file.FullName.Substring($release.Length).TrimStart('\')
    $destination = Join-Path $payload $relative
    New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $destination
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) { throw "Copy mismatch: $relative" }
}
foreach ($name in @('debug.bat','install.bat','uninstall.bat','uninstall.ps1','ABOUT.txt','README.md','CHANGELOG.md','USERGUIDE.md','RELEASE_NOTES.md','LICENSE')) {
    $source = Join-Path $root $name
    if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination (Join-Path $payload $name) }
    elseif ($name -in @('install.bat','uninstall.bat','uninstall.ps1')) { throw "Missing installer helper: $name" }
}
$zip = Join-Path $output ($packageName + '.zip')
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($payload, $zip, [IO.Compression.CompressionLevel]::Optimal, $true)
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $files = @(Get-ChildItem -LiteralPath $payload -Recurse -File -Force)
    if (@($archive.Entries | Where-Object { $_.Name }).Count -ne $files.Count) { throw 'ZIP file count mismatch' }
    foreach ($file in $files) {
        $entryName = $packageName + '/' + $file.FullName.Substring($payload.Length + 1).Replace('\','/')
        $entry = @($archive.Entries | Where-Object { $_.FullName.Replace('\','/') -eq $entryName }) | Select-Object -First 1
        if (-not $entry) { throw "Missing ZIP entry: $entryName" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-','') }
        finally { $stream.Dispose(); $sha.Dispose() }
        if ($hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) { throw "ZIP mismatch: $entryName" }
    }
} finally { $archive.Dispose() }
foreach ($item in Get-ChildItem -LiteralPath $payload -Force) { Copy-Item -LiteralPath $item.FullName -Destination $output -Recurse }
$hash = (Get-FileHash -LiteralPath $zip).Hash
Set-Content -LiteralPath (Join-Path $output 'SHA256SUMS.txt') -Value "$hash *$packageName.zip" -Encoding ascii
# Publish only a validated complete output. Keep old output untouched on failure.
$previous = Join-Path $root ('dist.previous-' + $id)
if (Test-Path -LiteralPath $dist) { Move-Item -LiteralPath $dist -Destination $previous }
try { Move-Item -LiteralPath $output -Destination $dist }
catch {
    if ((Test-Path -LiteralPath $previous) -and -not (Test-Path -LiteralPath $dist)) { Move-Item -LiteralPath $previous -Destination $dist }
    throw
}
Write-Host "[SUCCESS] $dist ($expected). ZIP contents and SHA256 verified."
if (Test-Path -LiteralPath $previous) { Write-Host "Previous output retained: $previous" }
Write-Host "Staging retained: $stage"
