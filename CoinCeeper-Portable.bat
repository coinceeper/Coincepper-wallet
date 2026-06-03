@echo off
chcp 65001 > nul
title CoinCeeper - Portable Dev Mode
echo =============================================
echo   CoinCeeper - حالت پرتابل (توسعه سريع)
echo =============================================
echo.
echo   [1] اجراي سريع (EXE Debug موجود)
echo   [2] Hot Reload (flutter run -d windows)
echo   [3] بيلد Debug و اجرا
echo   [4] خروج
echo.
set /p CHOICE="انتخاب (1-4): "

if "%CHOICE%"=="1" goto quick
if "%CHOICE%"=="2" goto hot
if "%CHOICE%"=="3" goto build
if "%CHOICE%"=="4" goto end
goto end

:quick
powershell -ExecutionPolicy Bypass -File "scripts\dev_run_portable.ps1"
goto end

:hot
powershell -ExecutionPolicy Bypass -File "scripts\dev_run_portable.ps1" -HotReload
goto end

:build
powershell -ExecutionPolicy Bypass -File "scripts\dev_run_portable.ps1" -Build
goto end

:end
pause
