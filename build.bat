@echo off
setlocal EnableExtensions DisableDelayedExpansion
cd /d "%~dp0"
if errorlevel 1 (
    echo [ERROR] Khong the mo thu muc du an.
    pause
    exit /b 1
)
title Build JA LAN Messenger (Release)
echo ========================================================
echo   BUILD JA LAN MESSENGER - RELEASE WINDOWS DESKTOP
echo ========================================================
echo.

:: 1. Dong tien trinh dang chay neu co de tranh loi khoa file
echo [1/5] Kiem tra va dong tien trinh cu dang chay neu co...
taskkill /IM ja_lan_messenger.exe /F 2>nul

:: 2. Bien dich ung dung o che do Release
echo [2/5] Bien dich ung dung Flutter Windows Desktop (Release mode)...
call flutter build windows --release
set "BUILD_EXIT_CODE=%ERRORLEVEL%"
if not "%BUILD_EXIT_CODE%"=="0" (
    echo.
    echo ========================================================
    echo   [ERROR] Build that bai! Vui long kiem tra loi o tren.
    echo ========================================================
    pause
    exit /b %BUILD_EXIT_CODE%
)

set "TARGET_DIR=%~dp0build\windows\x64\runner\Release"
if not exist "%TARGET_DIR%\" (
    echo [ERROR] Khong tim thay thu muc Release: %TARGET_DIR%
    pause
    exit /b 1
)

:: 3. Sao chep file debug.bat va tai nguyen phu tro vao thu muc Release
echo [3/5] Dong bo file debug.bat va tai nguyen vao thu muc Release...
if exist "%~dp0debug.bat" (
    copy /y "%~dp0debug.bat" "%TARGET_DIR%\debug.bat" >nul
    echo       - Da chep debug.bat vao thu muc Release.
)
if exist "%~dp0ABOUT.txt" copy /y "%~dp0ABOUT.txt" "%TARGET_DIR%\" >nul
if exist "%~dp0README.md" copy /y "%~dp0README.md" "%TARGET_DIR%\" >nul
if exist "%~dp0CHANGELOG.md" copy /y "%~dp0CHANGELOG.md" "%TARGET_DIR%\" >nul
if exist "%~dp0USERGUIDE.md" copy /y "%~dp0USERGUIDE.md" "%TARGET_DIR%\" >nul
if exist "%~dp0LICENSE" copy /y "%~dp0LICENSE" "%TARGET_DIR%\" >nul

:: 4. Tao Shortcut den thu muc Release ngay tai goc du an
echo [4/5] Tao shortcut .Release - Shortcut.lnk tai goc du an...
set "SHORTCUT_PATH=%~dp0.Release - Shortcut.lnk"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut($env:SHORTCUT_PATH); $s.TargetPath = $env:TARGET_DIR; $s.Save()" >nul 2>&1

:: 5. Tu dong mo thu muc Release va Active len tren cung man hinh
echo [5/5] Mo thu muc Release va active len tren cung (Foreground Window)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$dir = '%TARGET_DIR%'; explorer.exe $dir; Start-Sleep -Milliseconds 500; $ws = New-Object -ComObject WScript.Shell; $sh = New-Object -ComObject Shell.Application; $activated = $false; foreach ($w in $sh.Windows()) { try { if ($w.Document.Folder.Self.Path -eq $dir) { [void]$ws.AppActivate($w.HWND); $activated = $true; break } } catch {} }; if (-not $activated) { [void]$ws.AppActivate('Release') }"

echo.
echo ========================================================
echo   [HOAN TAT] BUILD THANH CONG VA DA ACTIVE THU MUC
echo   - Thu muc: %TARGET_DIR%
echo   - Runner debug: %TARGET_DIR%\debug.bat
echo ========================================================
echo Nhan phim bat ky de dong cua so nay (tu dong dong sau 5s)...
timeout /t 5 >nul 2>&1 || pause >nul
exit /b 0
