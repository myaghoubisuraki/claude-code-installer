@echo off
:: Claude Code Installer — Windows Launcher
:: This batch file launches install.ps1 with the correct PowerShell flags.
:: Double-click this file OR run it from Command Prompt.

setlocal

echo.
echo   Claude Code Installer — Windows
echo   ================================
echo.

:: Check for PowerShell
where powershell >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo   [ERROR] PowerShell not found. Please install PowerShell 5.1+
    pause
    exit /b 1
)

:: Get the directory this .bat file lives in
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%install.ps1"

if not exist "%PS_SCRIPT%" (
    echo   [ERROR] install.ps1 not found in: %SCRIPT_DIR%
    echo   Make sure you cloned the full repository.
    pause
    exit /b 1
)

echo   Launching PowerShell installer...
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo   [ERROR] Installation failed. See the log file printed above.
    pause
    exit /b 1
)

pause
