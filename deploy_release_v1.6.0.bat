@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"

title Release JA LAN Messenger v1.6.0 ^& Deploy to LAN OTA
echo ===============================================================================
echo     JA LAN MESSENGER - RELEASE v1.6.0 ^^& DEPLOY TO LAN OTA SERVER
echo ===============================================================================
echo.

:: 1. Bien dich ung dung va dong goi vao dist/
echo [1/4] Bien dich ung dung Flutter Windows Desktop ^^& dong goi vao dist/...
call "%~dp0build.bat"
if errorlevel 1 (
    echo.
    echo ===============================================================================
    echo   [ERROR] Qua trinh build hoac dong goi that bai!
    echo ===============================================================================
    pause
    exit /b 1
)

:: 2. Kiem tra file phat hanh trong dist/
echo.
echo [2/4] Kiem tra goi phat hanh trong dist/...
if not exist "%~dp0dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip" (
    echo [ERROR] Khong tim thay file dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip!
    pause
    exit /b 1
)
if not exist "%~dp0dist\SHA256SUMS.txt" (
    echo [ERROR] Khong tim thay file dist\SHA256SUMS.txt!
    pause
    exit /b 1
)
echo       - Da xac nhan goi zip va ma bam SHA256 trong dist/!

:: 3. Git commit, tag, push
echo.
echo [3/4] Thuc hien git add, commit, tag v1.6.0 va push len GitHub...
git add .
git commit -m "Release v1.6.0: System Tray Toggle, Smart Bubble Entity Chips & WinRM / Group Fixes"
git tag -d v1.6.0 2>nul
git tag -a v1.6.0 -m "Release v1.6.0: System Tray Toggle, Smart Bubble Entity Chips & WinRM / Group Fixes"
echo       - Dang day nhanh main len GitHub...
git push origin main
echo       - Dang day tag v1.6.0 len GitHub...
git push origin v1.6.0 --force

:: 4. Deploy sang Server cap nhat LAN OTA
echo.
echo [4/4] Sao chep ban phat hanh toi may chu cap nhat LAN OTA...
set "REMOTE_DIR=\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger"
if not exist "%REMOTE_DIR%" (
    echo       - Thu muc dich chua ton tai tren server, dang khoi tao...
    mkdir "%REMOTE_DIR%" 2>nul
)

echo       - Chep goi zip v1.6.0 sang server...
copy /y "%~dp0dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip" "%REMOTE_DIR%\" >nul
if errorlevel 1 (
    echo [WARNING] Khong the sao chep sang %REMOTE_DIR%. Vui long kiem tra ket noi mang LAN/quyen truy cap.
) else (
    echo       - Da chep xong file zip sang server.
)

echo       - Chep SHA256SUMS.txt sang server...
copy /y "%~dp0dist\SHA256SUMS.txt" "%REMOTE_DIR%\" >nul

echo       - Tao va dong bo version.json sang server LAN OTA...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$zipPath = '%~dp0dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip'; " ^
    "if (Test-Path -LiteralPath $zipPath) { " ^
    "    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash; " ^
    "    $size = (Get-Item -LiteralPath $zipPath).Length; " ^
    "    $notes = 'JA LAN Messenger v1.6.0: System Tray Toggle, Smart Entity Detection & Responsive Chat Header'; " ^
    "    $json = [PSCustomObject]@{ " ^
    "        version = '1.6.0+12'; " ^
    "        fileName = 'JA_LAN_Messenger_v1.6.0_Windows_x64.zip'; " ^
    "        fileSize = $size; " ^
    "        sha256 = $hash; " ^
    "        releaseNotes = $notes; " ^
    "        releaseDate = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss'); " ^
    "    } | ConvertTo-Json; " ^
    "    $targetDir = '%REMOTE_DIR%'; " ^
    "    if (Test-Path -LiteralPath $targetDir) { " ^
    "        [System.IO.File]::WriteAllText((Join-Path $targetDir 'version.json'), $json, [System.Text.Encoding]::UTF8); " ^
    "        Write-Host '      [SUCCESS] version.json da duoc ghi thanh cong vao server LAN OTA!'; " ^
    "    } else { " ^
    "        Write-Host '      [WARNING] Khong tim thay targetDir de ghi version.json.'; " ^
    "    } " ^
    "} else { " ^
    "    Write-Host '      [ERROR] Khong tim thay file zip!'; " ^
    "}"

echo.
echo ===============================================================================
echo   [HOAN TAT] DA PHAT HANH VA DONG BO THANH CONG!
echo   - Phien ban : v1.6.0 (Build 12)
echo   - GitHub    : https://github.com/jatechvn/JA_LAN_Messenger.git (Tag: v1.6.0)
echo   - Dist      : %~dp0dist\JA_LAN_Messenger_v1.6.0_Windows_x64.zip
echo   - Server LAN: %REMOTE_DIR%
echo ===============================================================================
echo.
echo Nhan phim bat ky de ket thuc...
pause >nul
exit /b 0
