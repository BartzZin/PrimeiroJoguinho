$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& '.venv/Scripts/python.exe' tools/backup.py create
if ($LASTEXITCODE) { throw 'Falha ao criar backup cifrado' }
