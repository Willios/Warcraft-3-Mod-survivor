param(
    [string]$WarcraftDataDir = 'C:\Program Files (x86)\Warcraft III (Legacy)'
)

$ErrorActionPreference = 'Stop'

$root = Split-Path (Split-Path $PSScriptRoot)
$dist = Join-Path $root 'engine\dist\windows'
$out = Join-Path $root 'release'
$destination = Join-Path $out 'Warcraft Survivors Portable'
$stage = Join-Path $out 'Warcraft Survivors Portable.stage'
$runtime = Join-Path $stage 'OpenRealm'
$data = Join-Path $stage 'Data'
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'

if (Test-Path -LiteralPath $stage) {
    throw "Staging folder already exists: $stage. Inspect it before removing it."
}
if (-not (Test-Path -LiteralPath $csc)) {
    throw "The .NET Framework C# compiler was not found at $csc"
}

$requiredFiles = @(
    'War3.mpq',
    'War3x.mpq',
    'Maps\FrozenThrone\(6)Moonglade.w3x'
)
foreach ($file in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $WarcraftDataDir $file))) {
        throw "Missing required Warcraft III file in '$WarcraftDataDir': $file"
    }
}

New-Item -ItemType Directory -Force -Path $runtime, $data | Out-Null

# Copy the OpenRealm runtime and its own share/config tree, not benilla-config.
Copy-Item (Join-Path $dist '*.exe'), (Join-Path $dist '*.dll') $runtime
Copy-Item -LiteralPath (Join-Path $dist 'share') -Destination $runtime -Recurse
Remove-Item (Join-Path $runtime 'share\warcraft-3\Scripts\Survivor\test_*.lua')
Get-ChildItem -LiteralPath (Join-Path $runtime 'share\warcraft-3') -Filter *.cfg |
    Where-Object Name -ne 'config.cfg' | Remove-Item
Remove-Item (Join-Path $runtime 'share\warcraft-3\Maps\WarcraftSurvivor.w3m') -ErrorAction SilentlyContinue
Copy-Item (Join-Path $root 'src\ashenvale_survivor.lua'), (Join-Path $root 'src\engine_boot.lua') `
    (Join-Path $runtime 'share\warcraft-3\Scripts\Survivor')

# Keep the complete Legacy install under Data so the launcher can use it offline.
Get-ChildItem -LiteralPath $WarcraftDataDir -Force |
    Copy-Item -Destination $data -Recurse -Force

$launcher = Join-Path $stage 'WarcraftSurvivors.exe'
& $csc /nologo /target:winexe /optimize+ /reference:System.Windows.Forms.dll `
    "/out:$launcher" (Join-Path $PSScriptRoot 'warcraft_survivors_launcher.cs')
if ($LASTEXITCODE -ne 0) {
    throw "Launcher compilation failed with exit code $LASTEXITCODE"
}

@'
Warcraft Survivors - portable build
===================================

Double-click WarcraftSurvivors.exe to start the game. Keep the Data and OpenRealm
folders beside it. Data contains the Warcraft III Legacy files; OpenRealm contains
the modified OpenRealm engine, its configuration, and the survivor scripts.

This package includes Blizzard game data copied from the builder's local install.
Keep it for your personal use and do not upload or share it.

Progress is saved in %APPDATA%\warcraft-3\CustomMapData\WarcraftSurvivors\.
'@ | Set-Content -LiteralPath (Join-Path $stage 'README.txt') -Encoding UTF8

$backup = $null
if (Test-Path -LiteralPath $destination) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $out "Warcraft Survivors Portable.previous-$stamp"
    if (Test-Path -LiteralPath $backup) {
        $backup = Join-Path $out "Warcraft Survivors Portable.previous-$stamp-$([guid]::NewGuid().ToString('N'))"
    }
    Move-Item -LiteralPath $destination -Destination $backup
}

try {
    Move-Item -LiteralPath $stage -Destination $destination
} catch {
    if ($backup -and -not (Test-Path -LiteralPath $destination)) {
        Move-Item -LiteralPath $backup -Destination $destination
    }
    throw
}

"Portable folder created: $destination"
if ($backup) { "Previous build preserved at: $backup" }
