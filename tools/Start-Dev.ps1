param([switch]$OpenClient)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
if (-not (Test-Path '.env')) { & "$PSScriptRoot/Setup-Dev.ps1" }
docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
if ($LASTEXITCODE) {
    Start-Process -FilePath 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(120)
    do {
        Start-Sleep -Seconds 2
        docker info --format '{{.ServerVersion}}' 2>$null | Out-Null
        if (-not $LASTEXITCODE) { break }
    } while ((Get-Date) -lt $deadline)
    if ($LASTEXITCODE) { throw 'Docker não iniciou. Verifique WSL2/virtualização no Docker Desktop.' }
}
docker compose --env-file .env -f ops/compose.yaml up -d --build --wait
if ($LASTEXITCODE) { throw 'Falha ao iniciar containers do projeto' }
Write-Output 'API local: http://127.0.0.1:8000 — iniciar/parar é sempre manual.'
if ($OpenClient) {
    $godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
    Start-Process -FilePath $godotPath -ArgumentList @('--path', "`"$projectRoot/client-godot`"")
}
