@echo off
setlocal
set "NEURALIFE_CHECK_DIR=%~dp0"
powershell.exe -NoLogo -NoProfile -Command "& (Join-Path $env:NEURALIFE_CHECK_DIR 'check-neuralife.ps1')"
if errorlevel 1 echo Check did not complete. See the message above. No execution policy was changed.
pause
endlocal
