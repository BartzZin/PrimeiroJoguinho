param([Parameter(Mandatory=$true)][string]$File, [string]$Database = 'arcano_restore')
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path $PSScriptRoot -Parent)
& '.venv/Scripts/python.exe' tools/backup.py restore $File --database $Database
if ($LASTEXITCODE) { throw 'Falha na restauração; o banco principal não foi alterado' }
