@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
if "%~1"=="--staged" goto run
set "UNINSTALL_HELPER=%~dp0uninstall.ps1"
set "UNINSTALL_ORIGIN=%~dp0"
set "UNINSTALL_MODE=%~1"
set "UNINSTALL_DRIVER=%TEMP%\JA_Uninstall_%RANDOM%_%RANDOM%.bat"
copy /y "%~f0" "%UNINSTALL_DRIVER%" >nul
if errorlevel 1 exit /b 1
:: Transfer batch execution to TEMP without CALL, so deletion cannot disrupt it.
"%UNINSTALL_DRIVER%" --staged
exit /b 1
:run
cd /d "%TEMP%"
if errorlevel 1 exit /b 1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%UNINSTALL_HELPER%" -Mode "%UNINSTALL_MODE%"
exit /b %errorlevel%
