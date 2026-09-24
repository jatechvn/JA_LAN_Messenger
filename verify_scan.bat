@echo off
setlocal
chcp 65001 >nul
title JA LAN Messenger - Network Scan & Discovery Verifier

echo ======================================================================
echo    JA LAN Messenger - Network Scan ^& Discovery Verification Tool
echo ======================================================================
echo.

where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo [ERROR] PowerShell khong duoc tim thay tren he thong!
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_scan.ps1" %*

echo.
echo ======================================================================
echo    Kiem tra hoan tat. Nhan phim bat ky de thoat...
echo ======================================================================
pause >nul
