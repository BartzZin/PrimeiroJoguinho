param([string]$Profile = 'default')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
if (-not (Test-Path $godotPath)) { throw 'Execute tools/Install-Tools.ps1 primeiro.' }
Start-Process -FilePath $godotPath -ArgumentList @('--path', "`"$projectRoot/client-godot`"", '--', "--profile=$Profile")
