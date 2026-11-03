param(
    [string]$Game = ""
)

$EXE = "D:\program\AIT\Neuralife\bin\Neuralife.exe"
$DEVROOT = "C:\Users\Ait\Desktop\Neuralife"

$games = @("hanoi","pursuit","target","sokoban","claw","traffic","luban")

if ($Game -eq "") {
    Write-Host "Available games (run: .\play.ps1 <name>):"
    Write-Host "  hanoi    - Tower of Hanoi"
    Write-Host "  pursuit  - Light-chasing ball"
    Write-Host "  target   - Precision target"
    Write-Host "  sokoban  - Push box"
    Write-Host "  claw     - Claw machine"
    Write-Host "  traffic  - Traffic light crossing"
    Write-Host "  luban    - Luban lock"
    exit 0
}

if (-not $games.Contains($Game)) {
    Write-Host "Unknown game: $Game"
    Write-Host "Available: $($games -join ', ')"
    exit 1
}

Write-Host "Launching $Game ..."
& "$EXE" --game-dev $Game --games-dev-root "$DEVROOT"
