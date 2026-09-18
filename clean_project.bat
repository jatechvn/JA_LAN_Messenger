@echo off
setlocal enabledelayedexpansion
title Don Dep Du An - Flutter Cleanup
echo ============================================================
echo   CHUONG TRINH DON DEP CAC DU AN FLUTTER / DART
echo ============================================================
echo Cong cu nay se tu dong quet va xoa toan bo cac thu muc rac sau build,
echo bo nho dem va thu muc thu vien ^(.pub-cache^) de thu nho dung luong du an.
echo(

set "found_project=0"

:: 1. Kiem tra xem thu muc hien tai co phai la du an khong
if exist "%~dp0pubspec.yaml" (
    set "found_project=1"
    echo Phat hien thu muc hien tai la mot du an.
)

:: 2. Quet cac thu muc con
for /d %%d in ("%~dp0*") do (
    if exist "%%d\pubspec.yaml" (
        set "found_project=1"
        echo Phat hien du an con: %%~nxd
    )
)

if "!found_project!"=="0" (
    echo Khong tim thay bat ky du an Flutter/Dart nao o day.
    pause
    exit /b
)

echo(
set "confirm=N"
set /p "confirm=Ban co chac chan muon don dep cac du an tren khong? [Y/N]: "
if /i not "!confirm!"=="y" (
    echo Huy bo don dep.
    pause
    exit /b
)

echo(
echo Dang bat dau don dep...

:: Don dep thu muc hien tai neu la du an
if exist "%~dp0pubspec.yaml" (
    echo ------------------------------------------------------------
    echo Dang don dep du an hien tai...
    call :clean_folder "%~dp0"
)

:: Don dep cac thu muc con neu la du an
for /d %%d in ("%~dp0*") do (
    if exist "%%d\pubspec.yaml" (
        echo ------------------------------------------------------------
        echo Dang don dep du an con: %%~nxd...
        call :clean_folder "%%d"
    )
)

echo(
echo ============================================================
echo   DON DEP HOAN TAT!
echo ============================================================
echo Tat ca cac du an da duoc dua ve dung luong toi thieu.
echo De chay lai bat ky du an nao, chi can chay file run.bat trong do.
echo(
pause
endlocal
exit /b

:clean_folder
set "target=%~1"
if exist "%target%\build" (
    echo  - Xoa build\
    rmdir /s /q "%target%\build"
)
if exist "%target%\.dart_tool" (
    echo  - Xoa .dart_tool\
    rmdir /s /q "%target%\.dart_tool"
)
if exist "%target%\.pub-cache" (
    echo  - Xoa .pub-cache\
    rmdir /s /q "%target%\.pub-cache"
)
if exist "%target%\.idea" (
    echo  - Xoa .idea\
    rmdir /s /q "%target%\.idea"
)
if exist "%target%\windows\flutter\ephemeral" (
    echo  - Xoa windows\flutter\ephemeral\ ~260MB
    rmdir /s /q "%target%\windows\flutter\ephemeral"
)
if exist "%target%\.flutter-plugins" (
    del /f /q "%target%\.flutter-plugins" 2>nul
    echo  - Xoa .flutter-plugins
)
if exist "%target%\.flutter-plugins-dependencies" (
    del /f /q "%target%\.flutter-plugins-dependencies" 2>nul
    echo  - Xoa .flutter-plugins-dependencies
)
if exist "%target%\*.iml" (
    del /f /q "%target%\*.iml" 2>nul
    echo  - Xoa cac file .iml
)
goto :eof
