@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0play.ps1" -Game "%~1"
exit /b %ERRORLEVEL%
