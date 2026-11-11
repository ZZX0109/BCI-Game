param([string]$Game = "")
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$games = @((Get-Content -LiteralPath (Join-Path $root 'config\active_games.json') -Raw | ConvertFrom-Json).games)
if ($Game -eq '') {
    Write-Host "Available V5 games: $($games -join ', ')"
    exit 0
}
if ($Game -notin $games) {
    Write-Error "Not an active V5 game: $Game"
    exit 1
}
$exe = if ($env:NEURALIFE_EXE) { $env:NEURALIFE_EXE } else { 'D:\program\AIT\Neuralife\bin\Neuralife.exe' }
$devRoot = if ($env:NEURALIFE_DEVROOT) { $env:NEURALIFE_DEVROOT } else { $root }
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Neuralife.exe not found: $exe" }
if ($Game -eq 'luban') { $env:QT_QUICK_BACKEND = 'rhi' }
& $exe --game-dev $Game --games-dev-root $devRoot
exit $LASTEXITCODE
