@echo off
setlocal
title Cyberpunk 2077 VR Port - Uninstaller

set "PS=powershell.exe"
where pwsh.exe >nul 2>&1 && set "PS=pwsh.exe"

"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CyberpunkVR.ps1" -Uninstall %*

pause
endlocal
