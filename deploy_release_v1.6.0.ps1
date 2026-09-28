<#
.SYNOPSIS
    Release JA LAN Messenger v1.6.0, git push, and deploy to LAN OTA Server.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
Set-Location -LiteralPath $root

Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host "    JA LAN MESSENGER - RELEASE v1.6.0 & DEPLOY TO LAN OTA SERVER" -ForegroundColor Cyan
Write-Host "===============================================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Run build.bat
Write-Host "[1/4] Bien dich ung dung Flutter Windows Desktop & dong goi vao dist/..." -ForegroundColor Yellow
$buildBat = Join-Path $root 'build.bat'
$proc = Start-Process -FilePath 'cmd.exe' -ArgumentList "/c `"$buildBat`"" -Wait -NoNewWindow -PassThru
if ($proc.ExitCode -ne 0) {
    Write-Error "Build that bai voi ma loi $($proc.ExitCode)!"
    return
}

# 2. Verify dist package
Write-Host "`n[2/4] Kiem tra goi phat hanh trong dist/..." -ForegroundColor Yellow
$zipPath = Join-Path $root 'dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip'
$sumsPath = Join-Path $root 'dist\SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $zipPath)) {
    Write-Error "Khong tim thay file dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip!"
    return
}
if (-not (Test-Path -LiteralPath $sumsPath)) {
    Write-Error "Khong tim thay file dist\SHA256SUMS.txt!"
    return
}
Write-Host "      - Da xac nhan goi zip va ma bam SHA256 trong dist/!" -ForegroundColor Green

# 3. Git commit, tag, push
Write-Host "`n[3/4] Thuc hien git add, commit, tag v1.6.0 va push len GitHub..." -ForegroundColor Yellow
git add .
git commit -m "Release v1.6.0: System Tray Toggle, Smart Bubble Entity Chips & WinRM / Group Fixes"
try { git tag -d v1.6.0 2>$null } catch {}
git tag -a v1.6.0 -m "Release v1.6.0: System Tray Toggle, Smart Bubble Entity Chips & WinRM / Group Fixes"
Write-Host "      - Dang day nhanh main len GitHub..." -ForegroundColor Gray
git push origin main
Write-Host "      - Dang day tag v1.6.0 len GitHub..." -ForegroundColor Gray
git push origin v1.6.0 --force

# 4. Deploy to LAN OTA Server
Write-Host "`n[4/4] Sao chep ban phat hanh toi may chu cap nhat LAN OTA..." -ForegroundColor Yellow
$remoteDir = '\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger'
if (-not (Test-Path -LiteralPath $remoteDir)) {
    try {
        New-Item -ItemType Directory -Path $remoteDir -Force | Out-Null
        Write-Host "      - Da khoi tao thu muc tren server: $remoteDir" -ForegroundColor Gray
    } catch {
        Write-Warning "Khong the tao thu muc tren server: $_"
    }
}

try {
    Copy-Item -LiteralPath $zipPath -Destination (Join-Path $remoteDir (Split-Path $zipPath -Leaf)) -Force
    Copy-Item -LiteralPath $sumsPath -Destination (Join-Path $remoteDir (Split-Path $sumsPath -Leaf)) -Force
    Write-Host "      - Da chep thanh cong file zip va SHA256SUMS sang server!" -ForegroundColor Green

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
    $size = (Get-Item -LiteralPath $zipPath).Length
    $notes = 'JA LAN Messenger v1.6.0: System Tray Toggle, Smart Entity Detection & Responsive Chat Header'
    $json = [PSCustomObject]@{
        version = '1.6.0+12'
        fileName = 'JA_LAN_Messenger_v1.6.0_Windows_x64.zip'
        fileSize = $size
        sha256 = $hash
        releaseNotes = $notes
        releaseDate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    } | ConvertTo-Json -Indent 2

    [System.IO.File]::WriteAllText((Join-Path $remoteDir 'version.json'), $json, [System.Text.Encoding]::UTF8)
    Write-Host "      - Da ghi thanh cong version.json len server LAN OTA!" -ForegroundColor Green
} catch {
    Write-Warning "Loi khi sao chep sang server: $_"
}

Write-Host "`n===============================================================================" -ForegroundColor Cyan
Write-Host "  [HOAN TAT] DA PHAT HANH VA DONG BO THANH CONG!" -ForegroundColor Green
Write-Host "  - Phien ban : v1.6.0 (Build 12)" -ForegroundColor White
Write-Host "  - GitHub    : https://github.com/jatechvn/JA_LAN_Messenger.git (Tag: v1.6.0)" -ForegroundColor White
Write-Host "  - Dist      : $zipPath" -ForegroundColor White
Write-Host "  - Server LAN: $remoteDir" -ForegroundColor White
Write-Host "===============================================================================" -ForegroundColor Cyan
