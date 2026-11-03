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
"%EXE%" --game-dev %1 --games-dev-root "%DEVROOT%"

:EOF
