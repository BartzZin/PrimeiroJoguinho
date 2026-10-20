$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
docker compose --env-file .env -f ops/compose.yaml exec -T api python -m app.cli invite
if ($LASTEXITCODE) { throw 'Falha ao criar convite' }
