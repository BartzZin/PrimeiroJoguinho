$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
docker compose --env-file .env -f ops/compose.yaml stop
if ($LASTEXITCODE) { throw 'Não foi possível parar os containers do projeto' }
Write-Output 'Containers do Xadrez Arcano parados. Dados preservados; outros projetos não foram alterados.'
