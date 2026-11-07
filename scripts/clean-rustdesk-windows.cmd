@echo off
setlocal EnableExtensions

rem Always run from this script directory (double-click cwd may be System32).
cd /d "%~dp0"

set "PS_SCRIPT=%~dp0clean-rustdesk-windows.ps1"
if not exist "%PS_SCRIPT%" (
    echo ERROR: Missing "%PS_SCRIPT%"
    pause
    exit /b 1
)

net session >nul 2>&1
if errorlevel 1 (
    echo Requesting Administrator permission...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -WorkingDirectory '%~dp0.' -Verb RunAs"
    exit /b
)

echo Cleaning RustDesk test state...
echo Script: %PS_SCRIPT%
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Force
set "RC=%ERRORLEVEL%"

echo.
if not "%RC%"=="0" (
    echo Cleanup failed with exit code %RC%
) else (
    echo Cleanup finished.
)

pause
exit /b %RC%
