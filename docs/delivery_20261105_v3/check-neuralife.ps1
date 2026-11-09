# Read-only inspection of Neuralife.exe and seven known game directories.
# Windows PowerShell 5.1; no network, elevation, policy changes or recursive scans.
$ErrorActionPreference = 'Stop'
$expected = 'bd5dfabccad6441152e66c7d208281cc7c0d14c625268bc19bc4a9d2c18ca355'
$base = $PSScriptRoot
$notes = [System.Collections.Generic.List[string]]::new()

function File-Fingerprint([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ path = $path; status = 'not_found' }
    }
    try {
        return [ordered]@{ path = $path; status = 'ok'; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
    } catch { return [ordered]@{ path = $path; status = 'unreadable' } }
}

function Dev-Arguments([string]$line) {
    # Inspect only two explicitly allowed switches. Never serialize the raw command line.
    $out = [ordered]@{}
    foreach ($name in @('game-dev', 'games-dev-root')) {
        $pattern = '(?i)(?:^|\s)--' + [regex]::Escape($name) + '(?:(?:=|\s+)(?:"([^"\r\n]*)"|([^\s"\r\n]+)))?(?=\s|$)'
        $values = @()
        foreach ($m in [regex]::Matches($line, $pattern)) {
            $value = if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Groups[2].Success -and -not $m.Groups[2].Value.StartsWith('--')) { $m.Groups[2].Value } else { $null }
            $values += [ordered]@{ present = $true; value = $value }
        }
        $out['--' + $name] = $values
    }
    return $out
}

$windowApiAvailable = $false
try {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class NeuralifeReadOnlyWindow {
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError=true)] public static extern bool GetClientRect(IntPtr handle, out RECT rect);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr handle);
}
'@
    $windowApiAvailable = $true
} catch { $notes.Add('Window API unavailable; client size omitted.') }

$qtModuleNames = @(
    'effectsplugin.dll',
    'ffmpegmediaplugin.dll',
    'modelsplugin.dll',
    'qcertonlybackend.dll',
    'qgif.dll',
    'qico.dll',
    'qjpeg.dll',
    'qmldbg_debugger.dll',
    'qmldbg_inspector.dll',
    'qmldbg_local.dll',
    'qmldbg_messages.dll',
    'qmldbg_native.dll',
    'qmldbg_nativedebugger.dll',
    'qmldbg_preview.dll',
    'qmldbg_profiler.dll',
    'qmldbg_quick3dprofiler.dll',
    'qmldbg_quickeventreplay.dll',
    'qmldbg_quickprofiler.dll',
    'qmldbg_server.dll',
    'qmldbg_tcp.dll',
    'qmlplugin.dll',
    'qmlshapesplugin.dll',
    'qmodernwindowsstyle.dll',
    'qnetworklistmanager.dll',
    'qquicklayoutsplugin.dll',
    'qschannelbackend.dll',
    'qsvg.dll',
    'qsvgicon.dll',
    'qt6core.dll',
    'qt6gui.dll',
    'qt6multimedia.dll',
    'qt6network.dll',
    'qt6opengl.dll',
    'qt6qml.dll',
    'qt6qmlmeta.dll',
    'qt6qmlmodels.dll',
    'qt6qmlworkerscript.dll',
    'qt6quick.dll',
    'qt6quick3dutils.dll',
    'qt6quickcontrols2.dll',
    'qt6quickcontrols2basic.dll',
    'qt6quickcontrols2basicstyleimpl.dll',
    'qt6quickcontrols2fluentwinui3styleimpl.dll',
    'qt6quickcontrols2fusion.dll',
    'qt6quickcontrols2fusionstyleimpl.dll',
    'qt6quickcontrols2imagine.dll',
    'qt6quickcontrols2imaginestyleimpl.dll',
    'qt6quickcontrols2impl.dll',
    'qt6quickcontrols2material.dll',
    'qt6quickcontrols2materialstyleimpl.dll',
    'qt6quickcontrols2universal.dll',
    'qt6quickcontrols2universalstyleimpl.dll',
    'qt6quickcontrols2windowsstyleimpl.dll',
    'qt6quickeffects.dll',
    'qt6quicklayouts.dll',
    'qt6quickshapes.dll',
    'qt6quicktemplates2.dll',
    'qt6svg.dll',
    'qt6texttospeech.dll',
    'qt6widgets.dll',
    'qtexttospeech_mock.dll',
    'qtexttospeech_sapi.dll',
    'qtexttospeech_winrt.dll',
    'qtquick2plugin.dll',
    'qtquickcontrols2basicstyleimplplugin.dll',
    'qtquickcontrols2basicstyleplugin.dll',
    'qtquickcontrols2fluentwinui3styleimplplugin.dll',
    'qtquickcontrols2fluentwinui3styleplugin.dll',
    'qtquickcontrols2fusionstyleimplplugin.dll',
    'qtquickcontrols2fusionstyleplugin.dll',
    'qtquickcontrols2imaginestyleimplplugin.dll',
    'qtquickcontrols2imaginestyleplugin.dll',
    'qtquickcontrols2implplugin.dll',
    'qtquickcontrols2materialstyleimplplugin.dll',
    'qtquickcontrols2materialstyleplugin.dll',
    'qtquickcontrols2nativestyleplugin.dll',
    'qtquickcontrols2plugin.dll',
    'qtquickcontrols2universalstyleimplplugin.dll',
    'qtquickcontrols2universalstyleplugin.dll',
    'qtquickcontrols2windowsstyleimplplugin.dll',
    'qtquickcontrols2windowsstyleplugin.dll',
    'qtquicktemplates2plugin.dll',
    'qtuiotouchplugin.dll',
    'quickwindowplugin.dll',
    'qwindows.dll',
    'windowsmediaplugin.dll',
    'workerscriptplugin.dll'
)

$processes = @()
try { $items = @(Get-CimInstance Win32_Process -Filter "Name = 'Neuralife.exe'") }
catch { $items = @(); $notes.Add('Cannot query Neuralife.exe processes with current permissions.') }
if ($items.Count -eq 0) { $notes.Add('No visible Neuralife.exe process found. Keep the game running and retry.') }
foreach ($item in $items) {
    $entry = [ordered]@{
        pid = $item.ProcessId
        executable = $null
        version = $null
        expectedSha256 = $expected
        matchesUploadedExecutable = $null
        workingDirectory = 'unavailable: not exposed by Win32_Process; process memory is not read'
        developerArguments = $null
        qtModules = @()
        qtModulesStatus = 'unavailable'
        mainWindowClient = [ordered]@{ status = 'unavailable' }
    }
    if ($item.ExecutablePath) {
        $entry.executable = File-Fingerprint $item.ExecutablePath
        if ($entry.executable.status -eq 'ok') { $entry.matchesUploadedExecutable = ($entry.executable.sha256 -eq $expected) }
        try {
            $v = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($item.ExecutablePath)
            $entry.version = [ordered]@{ fileVersion = $v.FileVersion; productVersion = $v.ProductVersion }
        } catch { $entry.version = 'unreadable' }
    }
    if ($null -ne $item.CommandLine) { $entry.developerArguments = Dev-Arguments $item.CommandLine }
    try {
        $proc = Get-Process -Id $item.ProcessId
        try {
            $entry.qtModules = @($proc.Modules | Where-Object {
                $_.ModuleName -match '^Qt[56].*\.dll$' -or $qtModuleNames -contains $_.ModuleName.ToLowerInvariant()
            } | ForEach-Object { [ordered]@{ name = $_.ModuleName; path = $_.FileName } })
            $entry.qtModulesStatus = 'ok: filtered Qt runtime/platform/QML modules only'
        } catch { $entry.qtModulesStatus = 'unavailable: access denied, bitness mismatch, or process exited' }
        if ($windowApiAvailable -and $proc.MainWindowHandle -ne [IntPtr]::Zero) {
            $rect = New-Object NeuralifeReadOnlyWindow+RECT
            if ([NeuralifeReadOnlyWindow]::GetClientRect($proc.MainWindowHandle, [ref]$rect)) {
                $dpi = $null
                try { $dpi = [NeuralifeReadOnlyWindow]::GetDpiForWindow($proc.MainWindowHandle) } catch {}
                $entry.mainWindowClient = [ordered]@{
                    status = 'ok'; width = $rect.Right - $rect.Left; height = $rect.Bottom - $rect.Top; windowDpi = $dpi
                    scope = 'MainWindowHandle only; may be the launcher rather than the game. GetClientRect units are as exposed to this PowerShell process; no DPI-awareness setting changed.'
                }
            }
        }
    } catch { $notes.Add('A Neuralife process exited or could not be accessed during inspection.') }
    $processes += $entry
}

$games = @()
foreach ($name in @('hanoi', 'sokoban', 'traffic', 'target', 'pursuit', 'claw', 'luban')) {
    $dir = Join-Path $base $name
    # Exact known paths only. No traversal of other directories or patient files.
    $games += [ordered]@{
        module = $name
        main = File-Fingerprint (Join-Path $dir 'Main.qml')
        definition = File-Fingerprint (Join-Path $dir 'TaskDefinition.qml')
    }
}
$result = [ordered]@{
    schemaVersion = 1; collectedAtUtc = [DateTime]::UtcNow.ToString('o')
    toolDirectory = $base; processes = $processes; games = $games; notes = @($notes.ToArray())
    limits = 'No patient/config contents, raw command line, non-Neuralife processes, network, disk scan, or process memory collected. File paths can contain local account names; review before sharing.'
}
$json = $result | ConvertTo-Json -Depth 12
$stamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss-fff')
$stem = 'neuralife-check-' + $stamp
$destination = $base
try {
    [IO.File]::WriteAllText((Join-Path $destination ($stem + '.json')), $json, [Text.UTF8Encoding]::new($false))
} catch {
    $destination = $env:TEMP
    [IO.File]::WriteAllText((Join-Path $destination ($stem + '.json')), $json, [Text.UTF8Encoding]::new($false))
}
# Text mirrors the same explicitly allowlisted JSON fields; no additional data.
[IO.File]::WriteAllText((Join-Path $destination ($stem + '.txt')), "Neuralife read-only check`r`n$json", [Text.UTF8Encoding]::new($false))
Write-Host ('Saved JSON: ' + (Join-Path $destination ($stem + '.json')))
Write-Host ('Saved text: ' + (Join-Path $destination ($stem + '.txt')))
