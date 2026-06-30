# ============================================================
# clipsync Windows installer - Scheduled Task
# ============================================================
# Uso (PowerShell como Administrador):
#   powershell -ExecutionPolicy Bypass -File install.ps1 <ip-linux> [porta]
#
# Exemplos:
#   powershell -ExecutionPolicy Bypass -File install.ps1 192.168.56.101
#   powershell -ExecutionPolicy Bypass -File install.ps1 192.168.56.101 9998
# ============================================================

param(
    [Parameter(Mandatory=$true, HelpMessage="IP da maquina Linux")]
    [string]$Remote,

    [int]$Port = 9999
)

$ErrorActionPreference = "Stop"
$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$TARGET = "$env:USERPROFILE\scripts\clipsync.ps1"

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  clipsync - Windows Installer" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Remote : ${Remote}:${Port}"
Write-Host "  Script : $TARGET"
Write-Host ""

# 1. Copia o script
Write-Host "[1/4] Copiando clipsync.ps1..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path (Split-Path $TARGET) | Out-Null
Copy-Item -Path "$SCRIPT_DIR\clipsync.ps1" -Destination $TARGET -Force
Write-Host "       Copiado para $TARGET" -ForegroundColor Green

# 2. Remove tarefa antiga
Write-Host "[2/4] Removendo tarefa antiga (se existir)..." -ForegroundColor Yellow
Unregister-ScheduledTask -TaskName "Clipsync" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "       OK" -ForegroundColor Green

# 3. Cria tarefa agendada
Write-Host "[3/4] Criando Scheduled Task..." -ForegroundColor Yellow
$action = New-ScheduledTaskAction -Execute "powershell" `
    -Argument "-ExecutionPolicy Bypass -WindowStyle Hidden -File `"$TARGET`" $Remote $Port"

$trigger = New-ScheduledTaskTrigger -AtLogon

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

Register-ScheduledTask -TaskName "Clipsync" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description "Clipboard sync Linux <-> Windows ($Remote)" `
    -RunLevel Highest | Out-Null
Write-Host "       Tarefa 'Clipsync' criada" -ForegroundColor Green

# 4. Inicia agora
Write-Host "[4/4] Iniciando..." -ForegroundColor Yellow
Start-ScheduledTask -TaskName "Clipsync"
Start-Sleep -Seconds 2

$task = Get-ScheduledTask -TaskName "Clipsync"
Write-Host "       Status: $($task.State)" -ForegroundColor $(if ($task.State -eq "Running") { "Green" } else { "Red" })

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Instalado com sucesso!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  A tarefa 'Clipsync' inicia automaticamente no logon."
Write-Host "  O script fica em silencio quando o Linux nao responde."
Write-Host ""
Write-Host "  Para verificar:  Get-ScheduledTask -TaskName Clipsync"
Write-Host "  Para parar:      Stop-ScheduledTask -TaskName Clipsync"
Write-Host "  Para iniciar:    Start-ScheduledTask -TaskName Clipsync"
Write-Host "  Para remover:    Unregister-ScheduledTask -TaskName Clipsync"
Write-Host ""
