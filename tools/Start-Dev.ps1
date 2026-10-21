param([switch]$OpenClient, [string]$LogPath = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
. "$PSScriptRoot/Project-Log.ps1"
Initialize-ProjectLog -Path $LogPath
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { throw 'Docker Desktop nao encontrado.' }
if (-not (Test-Path '.env')) { & "$PSScriptRoot/Setup-Dev.ps1" }
function Test-DockerReady {
    # Windows PowerShell 5.1 treats native stderr as ErrorRecords. A stopped
    # daemon is expected here and must not abort the launcher under Stop.
    $result = Invoke-ProjectNative -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}') -Operation 'Consultar Docker' -Quiet -AllowFailure
    return ($result -eq 0)
}
Write-ProjectStep 'Verificando Docker (inicio sempre manual)...'
if (-not (Test-DockerReady)) {
    if (-not (Test-Path -LiteralPath 'C:\Program Files\Docker\Docker\Docker Desktop.exe')) { throw 'Docker Desktop nao encontrado.' }
    Write-ProjectStep 'Abrindo Docker Desktop. A primeira abertura pode demorar alguns minutos...'
    Start-Process -FilePath 'C:\Program Files\Docker\Docker\Docker Desktop.exe' -WindowStyle Hidden
    $deadline = (Get-Date).AddSeconds(300)
    do {
        Start-Sleep -Seconds 2
        if (Test-DockerReady) { break }
    } while ((Get-Date) -lt $deadline)
    if (-not (Test-DockerReady)) { throw 'Docker não iniciou. Verifique WSL2/virtualização no Docker Desktop.' }
}
Write-ProjectStep 'Iniciando os containers do Xadrez Arcano...'
Invoke-ProjectNative -FilePath 'docker' -Arguments @('compose', '--env-file', '.env', '-f', 'ops/compose.yaml', 'up', '-d', '--build', '--wait') -Operation 'Iniciar containers' | Out-Null
$ready = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health/ready' -TimeoutSec 5
if ($ready.status -ne 'ready' -or -not $ready.accepting_matches) { throw 'Servidor indisponivel ou em manutencao.' }
Write-ProjectStep 'API pronta: http://127.0.0.1:8000. Inicio e parada sempre manuais.'
if ($OpenClient) {
    $godotPath = Join-Path $projectRoot '.tools/godot/Godot_v4.7.2-stable_win64.exe'
    Start-Process -FilePath $godotPath -ArgumentList @('--path', "`"$projectRoot/client-godot`"")
}
