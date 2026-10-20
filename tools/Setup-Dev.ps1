$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Set-Location $projectRoot
$pythonPath = Join-Path $env:LOCALAPPDATA 'Programs/Python/Python313/python.exe'
if (-not (Test-Path '.venv/Scripts/python.exe')) {
    if (-not (Test-Path $pythonPath)) { throw 'Instale Python 3.13 antes de continuar.' }
    & $pythonPath -m venv .venv
}
& '.venv/Scripts/python.exe' -m pip install -r server/requirements.lock
if ($LASTEXITCODE) { throw 'Falha ao instalar dependências' }
& '.venv/Scripts/python.exe' -m pip install --no-deps -e server
if ($LASTEXITCODE) { throw 'Falha ao registrar o servidor' }
if (-not (Test-Path '.env')) {
    $password = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(24)).ToLower()
    $adminToken = [Convert]::ToHexString([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).ToLower()
    @("POSTGRES_PASSWORD=$password", "DATABASE_URL=postgresql+psycopg://arcano:$password@127.0.0.1:55432/arcano", "ADMIN_TOKEN=$adminToken") | Set-Content '.env' -Encoding utf8
}
Write-Output 'Ambiente preparado; segredos em .env ignorado pelo Git. Nenhum serviço foi registrado.'
