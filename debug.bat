@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"
title JA LAN Messenger (Debug Mode)

:: 1. Neu debug.bat duoc chay trong thu muc Release / dist (co san ja_lan_messenger.exe)
for %%i in (*.exe) do (
    echo [DEBUG] Dang khoi chay %%i o che do --debug...
    start "" "%%i" --debug
    exit /b 0
)

:: 2. Neu chay tu thu muc goc du an, tim toi file exe Release da bien dich
set "REL_EXE=%~dp0build\windows\x64\runner\Release\ja_lan_messenger.exe"
if exist "%REL_EXE%" (
    echo [DEBUG] Dang khoi chay ban build Release: %REL_EXE% --debug...
    start "" "%REL_EXE%" --debug
    exit /b 0
)

:: 3. Neu chua co ban build Release, chay truc tiep bang Flutter
echo [INFO] Chua tim thay ban build Release. Dang khoi chay ung dung qua Flutter SDK...
call flutter run -d windows --debug
exit /b %ERRORLEVEL%
