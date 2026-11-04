@echo off
set "EXE=D:\program\AIT\Neuralife\bin\Neuralife.exe"
set "DEVROOT=C:\Users\Ait\Desktop\Neuralife"

if not "%1"=="" goto LAUNCH

echo Available games - run: play.bat name
echo   hanoi    - Tower of Hanoi
echo   pursuit  - Light-chasing ball
echo   target   - Precision target
echo   sokoban  - Push box
echo   claw     - Claw machine
echo   traffic  - Traffic light crossing
echo   luban    - Luban lock
goto EOF

:LAUNCH
REM luban uses real Qt Quick 3D (View3D). The host defaults to the software
REM scene-graph backend, where Quick3D cannot render, so force the RHI backend
REM for that one game only. Other games keep the original behaviour.
if /i "%1"=="luban" set "QT_QUICK_BACKEND=rhi"

"%EXE%" --game-dev %1 --games-dev-root "%DEVROOT%"

:EOF
