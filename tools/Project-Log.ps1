# Shared by manual launchers. Native stderr is not a PowerShell failure code.
function Initialize-ProjectLog {
    param([string]$Path = '')
    $taskRoot = Split-Path $PSScriptRoot -Parent
    $logFolder = Join-Path $taskRoot '.runtime/logs'
    if (-not $Path) { $Path = Join-Path $logFolder ("launcher-{0}-{1}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $PID) }
    $script:ProjectLogPath = [IO.Path]::GetFullPath($Path)
    try { New-Item -ItemType Directory -Force -Path $logFolder | Out-Null }
    catch { Write-Host 'Nao foi possivel criar a pasta de logs; continuando sem esse registro.'; return }
    Get-ChildItem -LiteralPath $logFolder -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -Skip 15 | ForEach-Object {
        # An open client log belongs to a running game; leave it alone.
        try {
            $probe = [IO.File]::Open($_.FullName, 'Open', 'ReadWrite', 'None')
            $probe.Close()
            Remove-Item -LiteralPath $_.FullName -ErrorAction SilentlyContinue
        } catch { }
    }
}

function Write-ProjectStep {
    param([string]$Message, [string]$Level = 'INFO', [switch]$Quiet)
    if (-not $Quiet) { Write-Host $Message }
    try {
        if ((Test-Path -LiteralPath $script:ProjectLogPath) -and (Get-Item -LiteralPath $script:ProjectLogPath).Length -gt 2MB) {
            for ($index = 4; $index -ge 1; $index--) {
                $source = "$script:ProjectLogPath.$index"
                $target = "$script:ProjectLogPath.$($index + 1)"
                if (Test-Path -LiteralPath $source) { Move-Item -LiteralPath $source -Destination $target -Force }
            }
            Move-Item -LiteralPath $script:ProjectLogPath -Destination "$script:ProjectLogPath.1" -Force
        }
        $clean = $Message -replace '(?i)Bearer\s+\S+', '[REDACTED]'
        $clean = $clean -replace '(?i)(password|access_token|refresh_token|invite|room_code)\s*[:=]\s*\S+', '[REDACTED]'
        Add-Content -LiteralPath $script:ProjectLogPath -Encoding UTF8 -Value ("{0} [{1}] {2}" -f [DateTime]::UtcNow.ToString('o'), $Level, $clean)
    } catch { }
}

function Invoke-ProjectNative {
    param([string]$FilePath, [string[]]$Arguments, [string]$Operation, [switch]$Quiet, [switch]$AllowFailure)
    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $nativeLines = @(& $FilePath @Arguments 2>&1)
        $nativeExit = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if (-not $Quiet -or $nativeExit) {
        foreach ($nativeLine in $nativeLines) {
            Write-ProjectStep -Message ([string]$nativeLine) -Level 'NATIVE' -Quiet:$Quiet
        }
    }
    if ($nativeExit -and -not $AllowFailure) { throw "$Operation falhou (codigo $nativeExit)." }
    return $nativeExit
}
