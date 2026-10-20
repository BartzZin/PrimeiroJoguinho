$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& "$PSScriptRoot/Start-Dev.ps1"
& '.venv/Scripts/python.exe' tools/play_local.py
if ($LASTEXITCODE) { throw 'Falha ao abrir partida local' }
