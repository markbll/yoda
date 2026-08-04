@echo off
setlocal
set "SCRIPT_DIR=%~dp0"

powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File "%SCRIPT_DIR%YODA.ps1"

if errorlevel 1 (
    echo.
    echo YODA exited with an error - see the message above.
    pause
)

endlocal
