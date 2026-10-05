@echo off
chcp 65001 >nul
setlocal EnableExtensions DisableDelayedExpansion
set "SILENT_MODE=0"
if /i "%~1"=="/silent" set "SILENT_MODE=1"
if /i "%~1"=="/s" set "SILENT_MODE=1"
title Install JA LAN Messenger

echo ========================================================
echo       INSTALL JA LAN MESSENGER FOR WINDOWS
echo ========================================================
echo.

set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"

set "SOURCE_DIR="
if exist "%SCRIPT_DIR%\ja_lan_messenger.exe" (
    set "SOURCE_DIR=%SCRIPT_DIR%"
) else if exist "%SCRIPT_DIR%\build\windows\x64\runner\Release\ja_lan_messenger.exe" (
    set "SOURCE_DIR=%SCRIPT_DIR%\build\windows\x64\runner\Release"
) else if exist "%SCRIPT_DIR%\dist\ja_lan_messenger.exe" (
    set "SOURCE_DIR=%SCRIPT_DIR%\dist"
)

if not defined SOURCE_DIR (
    echo [ERROR] Cannot find ja_lan_messenger.exe.
    echo Place install.bat next to ja_lan_messenger.exe
    echo or run build.bat to build the application first.
    echo.
    if "%SILENT_MODE%"=="0" pause
    exit /b 1
)

echo [1/5] Checking running application...
set "TARGET_DIR=%LOCALAPPDATA%\Programs\JA_LAN_Messenger"
if /i "%SOURCE_DIR%"=="%TARGET_DIR%" goto install_error
if not exist "%SOURCE_DIR%\flutter_windows.dll" goto install_error
if not exist "%SOURCE_DIR%\data\icudtl.dat" goto install_error
if not exist "%SOURCE_DIR%\data\app.so" goto install_error
if not exist "%SCRIPT_DIR%\uninstall.ps1" goto install_error
:: Never force-stop another portable instance or interrupt unsaved history.
powershell -NoProfile -Command "$exe = Join-Path $env:TARGET_DIR 'ja_lan_messenger.exe'; if (Get-Process ja_lan_messenger -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) { Write-Host 'Close the installed app before continuing.'; exit 1 }"
if errorlevel 1 goto install_error
if exist "%TARGET_DIR%\unins000.exe" goto install_error

set "TARGET_DIR=%LOCALAPPDATA%\Programs\JA_LAN_Messenger"
echo [2/5] Preparing installation directory:
echo       "%TARGET_DIR%"
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
if not exist "%TARGET_DIR%\" (
    echo [ERROR] Cannot create installation directory: "%TARGET_DIR%"
    if "%SILENT_MODE%"=="0" pause
    exit /b 1
)

echo [3/5] Copying application files...
:: Preserve runtime configuration; back up program files before replacement.
if exist "%TARGET_DIR%\ja_lan_messenger.exe" (
    powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $backup=Join-Path $env:TEMP ('JA_LAN_Install_Backup_' + [guid]::NewGuid()); & robocopy $env:TARGET_DIR $backup /E /R:1 /W:1 /XD logs conversations backups /XF user_preferences.json update_config.json known_devices.json network_preferences.json config.json *.ini *.log *.key *.pem *.pfx *.p12 > $null; if ($LASTEXITCODE -ge 8) { exit 1 }; Write-Host ('Backup: ' + $backup); exit 0"
    if errorlevel 1 goto install_error
)
robocopy "%SOURCE_DIR%" "%TARGET_DIR%" /E /R:1 /W:1 /XD logs conversations backups /XF user_preferences.json update_config.json known_devices.json network_preferences.json config.json config.ini *.log *.key *.pem *.pfx *.p12 >nul
if errorlevel 8 (
    echo [ERROR] Failed to copy application files!
    if "%SILENT_MODE%"=="0" pause
    exit /b 1
)
copy /y "%SCRIPT_DIR%\uninstall.ps1" "%TARGET_DIR%\uninstall.ps1" >nul
if errorlevel 1 goto install_error

if exist "%SCRIPT_DIR%\uninstall.bat" (
    copy /y "%SCRIPT_DIR%\uninstall.bat" "%TARGET_DIR%\uninstall.bat" >nul
)

echo [4/5] Creating Desktop and Start Menu shortcuts...

:: Desktop may be redirected to OneDrive; resolve its Windows known folder.
set "START_MENU_DIR=%APPDATA%\Microsoft\Windows\Start Menu\Programs\JA LAN Messenger"
if not exist "%START_MENU_DIR%" mkdir "%START_MENU_DIR%"
set "START_MENU_APP_LNK=%START_MENU_DIR%\JA LAN Messenger.lnk"
set "START_MENU_UNINST_LNK=%START_MENU_DIR%\Uninstall JA LAN Messenger.lnk"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $ws = New-Object -ComObject WScript.Shell; " ^
  "$exe = Join-Path $env:TARGET_DIR 'ja_lan_messenger.exe'; " ^
  "$uninst = Join-Path $env:TARGET_DIR 'uninstall.bat'; " ^
  "$d = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'JA LAN Messenger.lnk')); " ^
  "$d.TargetPath = $exe; " ^
  "$d.WorkingDirectory = $env:TARGET_DIR; " ^
  "$d.IconLocation = $exe + ',0'; " ^
  "$d.Description = 'JA LAN Messenger - Peer-to-peer LAN messaging'; " ^
  "$d.Save(); " ^
  "$m = $ws.CreateShortcut($env:START_MENU_APP_LNK); " ^
  "$m.TargetPath = $exe; " ^
  "$m.WorkingDirectory = $env:TARGET_DIR; " ^
  "$m.IconLocation = $exe + ',0'; " ^
  "$m.Description = 'JA LAN Messenger - Peer-to-peer LAN messaging'; " ^
  "$m.Save(); " ^
  "$u = $ws.CreateShortcut($env:START_MENU_UNINST_LNK); " ^
  "$u.TargetPath = 'cmd.exe'; " ^
  "$q = [char]34; $u.Arguments = '/c ' + $q + $q + $uninst + $q + $q; " ^
  "$u.WorkingDirectory = $env:TARGET_DIR; " ^
  "$u.IconLocation = [System.IO.Path]::Combine($env:SystemRoot, 'System32', 'shell32.dll') + ',-240'; " ^
  "$u.Description = 'Uninstall JA LAN Messenger'; " ^
  "$u.Save();"
if errorlevel 1 goto install_error

echo [5/5] Registering application in Windows Control Panel...
set "REG_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\JA_LAN_Messenger"

reg add "%REG_KEY%" /v "DisplayName" /t REG_SZ /d "JA LAN Messenger" /f >nul
reg add "%REG_KEY%" /v "DisplayVersion" /t REG_SZ /d "1.8.1" /f >nul
reg add "%REG_KEY%" /v "Publisher" /t REG_SZ /d "JA Tech" /f >nul
reg add "%REG_KEY%" /v "DisplayIcon" /t REG_SZ /d "%TARGET_DIR%\ja_lan_messenger.exe,0" /f >nul
reg add "%REG_KEY%" /v "InstallLocation" /t REG_SZ /d "%TARGET_DIR%" /f >nul
reg add "%REG_KEY%" /v "HelpLink" /t REG_SZ /d "https://github.com/jatechvn/JA_LAN_Messenger" /f >nul
reg add "%REG_KEY%" /v "URLInfoAbout" /t REG_SZ /d "https://github.com/jatechvn/JA_LAN_Messenger" /f >nul
reg add "%REG_KEY%" /v "NoModify" /t REG_DWORD /d 1 /f >nul
reg add "%REG_KEY%" /v "NoRepair" /t REG_DWORD /d 1 /f >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$dir = $env:TARGET_DIR; " ^
  "$bytes = (Get-ChildItem -Path $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum; " ^
  "$kb = if ($bytes) { [math]::Round($bytes / 1024) } else { 0 }; " ^
  "$date = (Get-Date).ToString('yyyyMMdd'); " ^
  "Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JA_LAN_Messenger' -Name 'EstimatedSize' -Value $kb -Type DWord -ErrorAction SilentlyContinue; " ^
  "Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JA_LAN_Messenger' -Name 'InstallDate' -Value $date -Type String -ErrorAction SilentlyContinue" >nul 2>&1

powershell -NoProfile -Command "$ErrorActionPreference='Stop'; $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\JA_LAN_Messenger'; $q=[char]34; $bat=Join-Path $env:TARGET_DIR 'uninstall.bat'; Set-ItemProperty $key UninstallString ('cmd.exe /c '+$q+$q+$bat+$q+$q); Set-ItemProperty $key QuietUninstallString ('cmd.exe /c '+$q+$q+$bat+$q+' /silent'+$q); $ver=(Get-Item -LiteralPath (Join-Path $env:TARGET_DIR 'ja_lan_messenger.exe')).VersionInfo.ProductVersion; if ($ver) { Set-ItemProperty $key DisplayVersion $ver }; if ((Get-ItemProperty $key).InstallLocation -ne $env:TARGET_DIR) { throw 'Install registration failed' }"
if errorlevel 1 goto install_error
echo.
echo ========================================================
echo   [DONE] JA LAN MESSENGER INSTALLED SUCCESSFULLY!
echo ========================================================
echo - Installation directory: %TARGET_DIR%
echo - Desktop shortcut: JA LAN Messenger.lnk
echo - Menu Start: Programs \ JA LAN Messenger
echo - Uninstall from: Control Panel ^& Windows Settings
echo.

if /i "%~1"=="/silent" exit /b 0
if /i "%~1"=="/s" exit /b 0

set /p RUN_APP="Launch JA LAN Messenger now? (Y/N, default Y): "
if "%RUN_APP%"=="" set "RUN_APP=Y"
if /i "%RUN_APP%"=="yes" set "RUN_APP=Y"
if /i "%RUN_APP%"=="y" (
    start "" "%TARGET_DIR%\ja_lan_messenger.exe"
)
exit /b 0

:install_error
echo [ERROR] Installation failed. Check package, permissions and running app.
if "%SILENT_MODE%"=="0" pause
exit /b 1
