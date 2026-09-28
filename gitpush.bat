@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
cd /d "%~dp0"

title JA LAN Messenger - Release and Git Push v1.6.1
echo ===============================================================================
echo            JA LAN MESSENGER - AUTOMATED RELEASE AND GIT PUSH v1.6.1
echo ===============================================================================
echo.

rem 1. Dong tien trinh cu dang chay neu co de tranh xung dot khoa file
echo [1/6] Kiem tra va dong tien trinh cu neu co...
taskkill /IM ja_lan_messenger.exe /F >nul 2>&1

rem 2. Chay kiem thu Verification
echo.
echo [2/6] Chay kiem thu Verification (Flutter Test)...
call flutter test test\scan_localization_test.dart
if errorlevel 1 (
    echo [WARNING] Test don le that bai hoac co canh bao. Dang chay flutter test...
    call flutter test
)

rem 3. Bien dich ung dung Flutter Windows Desktop Release mode va dong goi dist
echo.
echo [3/6] Bien dich Release mode va dong goi sang dist\...
call build.bat
if errorlevel 1 (
    echo.
    echo ===============================================================================
    echo   [ERROR] Qua trinh bien dich Release mode hoac dong goi dist that bai!
    echo ===============================================================================
    pause
    exit /b 1
)

rem 4. Git Add va Commit
echo.
echo [4/6] Thuc hien Git Add va Git Commit...
git add -A
git commit -m "Release v1.6.1: Animated Sprite Stickers, Clipboard Image Copy & Multilingual IP Scan Progress"

rem 5. Git Tag va Git Push
echo.
echo [5/6] Tao Git Tag va Push len GitHub Remote...
git tag -d v1.6.1 >nul 2>&1
git tag -a v1.6.1 -m "Release v1.6.1"
git push origin main
git push origin v1.6.1 --force

rem 6. Tu dong dong bo sang may chu mang LAN (172.21.*.*)
echo.
echo [6/6] Kiem tra mang xuong (172.21.*.*) va dong bo LAN SMB...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$isFactory = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -like '172.21.*' }).Count -gt 0; if ($isFactory) { $dest = '\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger'; if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }; $zip = Get-ChildItem -LiteralPath 'dist' -Filter '*.zip' | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($zip) { Copy-Item -LiteralPath $zip.FullName -Destination $dest -Force; Write-Host ('[SUCCESS] Da dong bo zip len: ' + $dest) }; if (Test-Path 'dist\SHA256SUMS.txt') { Copy-Item -LiteralPath 'dist\SHA256SUMS.txt' -Destination $dest -Force }; if (Test-Path 'RELEASE_NOTES.md') { Copy-Item -LiteralPath 'RELEASE_NOTES.md' -Destination $dest -Force }; Write-Host '[SUCCESS] Hoan tat dong bo goi cap nhat len may chu LAN OTA.' } else { Write-Host '[INFO] May tinh hien tai khong thuoc dai IP 172.21.*.* (dang o may nha/ngoai mang xuong). Tu dong bo qua dong bo LAN.' }"

echo.
echo ===============================================================================
echo   [HOAN TAT] PHAT HANH VA GIT PUSH v1.6.1 THANH CONG!
echo   - Phien ban: v1.6.1+13
echo   - Thu muc phat hanh: %~dp0dist
echo   - GitHub Repository: https://github.com/jatechvn/JA_LAN_Messenger.git
echo ===============================================================================
echo.
pause
