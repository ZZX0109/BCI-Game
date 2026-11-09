@echo off
setlocal
set "EXE=%NEURALIFE_EXE%"
if not defined EXE set "EXE=D:\program\AIT\Neuralife\bin\Neuralife.exe"
if not exist "%EXE%" (
  echo Neuralife host not found. Set NEURALIFE_EXE to your Neuralife.exe path.
  pause
  exit /b 1
)
set "GAME=%~1"
if not defined GAME set "GAME=claw"
set "DEVROOT=%~dp0"
set "DEVROOT=%DEVROOT:~0,-1%"
if /i "%GAME%"=="luban" set "QT_QUICK_BACKEND=rhi"
"%EXE%" --game-dev "%GAME%" --games-dev-root "%DEVROOT%"
endlocal
