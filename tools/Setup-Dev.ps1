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
    & '.venv/Scripts/python.exe' -c "from pathlib import Path; import secrets; p=secrets.token_hex(24); Path('.env').write_text('POSTGRES_PASSWORD='+p+'\nDATABASE_URL=postgresql+psycopg://arcano:'+p+'@127.0.0.1:55432/arcano\nADMIN_TOKEN='+secrets.token_hex(32)+'\n', encoding='utf-8')"
}
& '.venv/Scripts/python.exe' -c "from pathlib import Path; from cryptography.fernet import Fernet; p=Path('.env'); text=p.read_text(encoding='utf-8-sig'); p.write_text(text + ('BACKUP_KEY=' + Fernet.generate_key().decode() + '\n' if 'BACKUP_KEY=' not in text else ''), encoding='utf-8')"
Write-Output 'Ambiente preparado; segredos em .env ignorado pelo Git. Nenhum serviço foi registrado.'
