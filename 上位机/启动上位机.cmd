@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_gui.ps1" %*
if errorlevel 1 (
 echo.
 echo Startup failed. See the error above and output\startup.log if present.
 pause
 exit /b 1
)
exit /b 0
