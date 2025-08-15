@echo off
:: Flask to Electron Build Launcher
:: This batch file launches the PowerShell build script with proper execution policy

echo Starting Flask to Electron build process...
echo.

:: Run the PowerShell script with bypass execution policy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-app.ps1"

:: Keep window open if there was an error
if %ERRORLEVEL% neq 0 (
    echo.
    echo Build failed with error code %ERRORLEVEL%
    pause
)
