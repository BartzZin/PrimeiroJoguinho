param([switch]$SmokeTest)
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
. "$PSScriptRoot/Project-Log.ps1"
Initialize-ProjectLog
try {
    Write-ProjectStep 'Validando ferramentas do projeto...'
    foreach ($required in @('.venv/Scripts/python.exe', '.tools/godot/Godot_v4.7.2-stable_win64.exe')) {
        if (-not (Test-Path -LiteralPath $required)) { throw "Ferramenta ausente: $required. Execute a preparacao do projeto." }
    }
    Invoke-ProjectNative -FilePath '.venv/Scripts/python.exe' -Arguments @('-c', 'import app.main, httpx') -Operation 'Validar dependencias Python' | Out-Null
    & "$PSScriptRoot/Start-Dev.ps1" -LogPath $script:ProjectLogPath
    Write-ProjectStep 'Criando a partida e abrindo as duas janelas...'
    $launchArguments = @('tools/play_local.py')
    if ($SmokeTest) { $launchArguments += '--smoke-test' }
    Invoke-ProjectNative -FilePath '.venv/Scripts/python.exe' -Arguments $launchArguments -Operation 'Abrir partida' | Out-Null
    Write-ProjectStep "Inicializacao concluida. Log: $script:ProjectLogPath"
} catch {
    Write-ProjectStep -Level 'ERROR' -Message ("Inicializacao interrompida: {0}" -f $_.Exception.Message)
    Write-Host "Consulte o log: $script:ProjectLogPath"
    exit 1
}
