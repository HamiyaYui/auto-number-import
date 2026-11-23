@echo off
setlocal EnableExtensions
title Auto-Number Import

cd /d "%~dp0"

if not exist "%~dp0AutoNumberImport.ps1" (
    echo.
    echo  [ERROR] AutoNumberImport.ps1 is missing.
    echo  Keep this .bat together with AutoNumberImport.ps1 in the same folder.
    echo.
    pause
    exit /b 1
)

where powershell.exe >nul 2>nul
if errorlevel 1 (
    echo.
    echo  [ERROR] Windows PowerShell was not found on this system.
    echo.
    pause
    exit /b 1
)

powershell.exe -NoProfile -NoLogo -ExecutionPolicy Bypass -File "%~dp0AutoNumberImport.ps1"
set "RC=%ERRORLEVEL%"

if not "%RC%"=="0" (
    echo.
    echo  Script stopped with exit code %RC%.
    echo  Please copy the message above and report it.
    echo.
    pause
)

endlocal & exit /b %RC%
