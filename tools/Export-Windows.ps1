$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
New-Item -ItemType Directory -Force exports/windows | Out-Null
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotPath --headless --path client-godot --editor --import --quit
if ($LASTEXITCODE) { throw 'Falha na importação Godot' }
& $godotPath --headless --path client-godot --export-release 'Windows Desktop' (Join-Path $projectRoot 'exports/windows/XadrezArcano.exe')
if ($LASTEXITCODE) { throw 'Falha ao exportar Windows' }
Copy-Item -LiteralPath 'licenses' -Destination 'exports/windows' -Recurse -Force
Write-Output 'Build: exports/windows/XadrezArcano.exe'
