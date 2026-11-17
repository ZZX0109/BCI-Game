param([switch]$Apply)
$ErrorActionPreference = 'Stop'
$manifestPath = Join-Path $PSScriptRoot 'moves.json'
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

function Assert-Child([string]$Path, [string]$Root) {
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if (-not $fullPath.StartsWith($fullRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path outside intended directory: $fullPath"
    }
    # Reject links in existing ancestors as well as in the moved tree.
    $candidate = $fullPath
    while ($candidate -and $candidate.Length -ge $fullRoot.TrimEnd('\').Length) {
        if (Test-Path -LiteralPath $candidate) {
            if ((Get-Item -LiteralPath $candidate -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Link not allowed: $candidate"
            }
        }
        $candidate = Split-Path -Parent $candidate
    }
}

if ($manifest.state -ne 'completed') { throw 'Manifest is not a completed migration' }
$moves = @($manifest.moves | Where-Object { $_.restorable -ne $false })
[array]::Reverse($moves)
foreach ($entry in $moves) {
    $originalRoot = if ($entry.kind -eq 'host-development') { $manifest.hostRoot } else { $manifest.sourceRoot }
    $archiveRoot = switch ($entry.kind) {
        'host-development' { $manifest.hostArchive }
        'research' { Join-Path $manifest.sourceRoot 'reference\research' }
        'historical-import' { Join-Path $manifest.sourceRoot 'archive\imports\20261116' }
        default { throw "Unexpected move kind: $($entry.kind)" }
    }
    Assert-Child $entry.source $originalRoot
    Assert-Child $entry.destination $archiveRoot
    if (Test-Path -LiteralPath $entry.source) { throw "Original path already exists; refusing overwrite: $($entry.source)" }
    $archived = Get-Item -LiteralPath $entry.destination -Force
    $items = if ($archived.PSIsContainer) { @(Get-ChildItem -LiteralPath $entry.destination -Recurse -Force) } else { @($archived) }
    if (@($items | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { throw 'Archived tree contains links' }
    if (@($items | Where-Object { -not $_.PSIsContainer }).Count -ne @($entry.files).Count) { throw "Archived file count changed: $($entry.destination)" }
    foreach ($file in $entry.files) {
        $filePath = if ($file.relativePath) { Join-Path $entry.destination $file.relativePath } else { $entry.destination }
        Assert-Child $filePath $archiveRoot
        if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
            throw "Archived file changed; refusing restore: $filePath"
        }
    }
}

if (-not $Apply) {
    $moves | Select-Object @{Name='From';Expression={$_.destination}}, @{Name='To';Expression={$_.source}}
    Write-Output "Verified $($moves.Count) moves. Preview only. Run with -Apply to restore original locations."
    exit 0
}

foreach ($entry in $moves) {
    # Paths and content have all been checked before the first move.
    New-Item -ItemType Directory -Path (Split-Path -Parent $entry.source) -Force | Out-Null
    Move-Item -LiteralPath $entry.destination -Destination $entry.source
    foreach ($file in $entry.files) {
        $filePath = if ($file.relativePath) { Join-Path $entry.source $file.relativePath } else { $entry.source }
        if ((Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
            throw "Restored hash mismatch: $filePath"
        }
    }
}
Write-Output "Restored $($moves.Count) original paths. Directory indexes and report files remain for reference."
