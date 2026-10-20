@echo off
setlocal
title Xadrez Arcano
echo Iniciando Xadrez Arcano. Aguarde o Docker e as duas janelas do jogo...
echo.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Play-Local.ps1"
if errorlevel 1 (
    echo.
    echo Nao foi possivel abrir o jogo. A mensagem acima explica o problema.
    pause
    exit /b 1
)
endlocal
