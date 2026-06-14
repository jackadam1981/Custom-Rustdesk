@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%clean-rustdesk-windows.ps1"

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    echo Requesting Administrator permission...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo Cleaning RustDesk test state...
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -Force -Confirm:$false

exit /b %errorlevel%
