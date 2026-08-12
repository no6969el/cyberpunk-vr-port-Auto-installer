@echo off
setlocal
title Cyberpunk 2077 VR Port - Installer

rem Double-click me. This just launches the PowerShell script next to it,
rem bypassing the execution policy prompt for this one run only.

set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CyberpunkVR.ps1" %*

if errorlevel 1 (
  echo.
  echo The installer exited with an error. Scroll up for details.
  pause
)
endlocal
