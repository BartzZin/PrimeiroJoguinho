@echo off
setlocal
title Encerrar servidor do Xadrez Arcano
echo Feche as janelas do jogo antes de parar o servidor.
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\Stop-Dev.ps1"
if errorlevel 1 (
    echo.
    echo Nao foi possivel parar o servidor. Confira a mensagem acima.
    pause
    exit /b 1
)
endlocal
