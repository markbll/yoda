@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%Yoda_GUI.ps1"

if errorlevel 1 (
    echo.
    echo Yoda GUI exited with an error - see the message above.
    pause
)

endlocal
