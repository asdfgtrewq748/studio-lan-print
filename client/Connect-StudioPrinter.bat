@echo off
chcp 65001 >nul
setlocal
set "PS1=%~dp0Add-StudioPrinter.ps1"
if not exist "%PS1%" set "PS1=%~dp0..\client\Add-StudioPrinter.ps1"
if not exist "%PS1%" (
  echo Add-StudioPrinter.ps1 not found next to this bat.
  pause
  exit /b 1
)
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
set ERR=%ERRORLEVEL%
echo.
if %ERR% neq 0 (
  echo Install failed. Code=%ERR%
) else (
  echo Install succeeded.
)
pause
exit /b %ERR%
