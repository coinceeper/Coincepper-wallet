@echo off
chcp 65001 > nul
title CoinCeeper - Quick Launch

echo =============================================
echo   CoinCeeper - اجراي سريع
echo =============================================
echo.

cd /d "%~dp0"

if exist "build\windows\x64\runner\Debug\CoinCeeper.exe" (
    echo [OK] در حال اجراي CoinCeeper (Debug)...
    start "" "build\windows\x64\runner\Debug\CoinCeeper.exe"
    exit /b 0
)

if exist "build\windows\x64\runner\Release\CoinCeeper.exe" (
    echo [OK] در حال اجراي CoinCeeper (Release)...
    start "" "build\windows\x64\runner\Release\CoinCeeper.exe"
    exit /b 0
)

echo [INFO] EXE يافت نشد. در حال بيلد Debug...
powershell -ExecutionPolicy Bypass -Command "& '.\scripts\dev_run_portable.ps1' -Build"
pause
