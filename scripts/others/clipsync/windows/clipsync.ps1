# ============================================================
# clipsync.ps1 - Windows side of the clipboard sync
# ============================================================
# Copy this script to your Windows machine and run in PowerShell:
#
#   powershell -ExecutionPolicy Bypass -File clipsync.ps1 <linux-ip> [porta]
#
# Uso: clipsync.ps1 192.168.56.101
#      clipsync.ps1 192.168.56.101 9999
#
# Para rodar sempre em background no boot:
#   Win+R -> taskschd.msc
#   Criar Tarefa Basica -> "Clipsync" -> "Ao fazer logon"
#   Programa: powershell
#   Argumentos: -ExecutionPolicy Bypass -WindowStyle Hidden -File C:\path\clipsync.ps1 <ip>
# ============================================================

param(
    [Parameter(Mandatory=$true, HelpMessage="IP da maquina Linux")]
    [string]$Remote,

    [int]$Port = 9999
)

$ErrorActionPreference = "Stop"
$STATE_DIR = Join-Path $env:TEMP "clipsync"
New-Item -ItemType Directory -Force -Path $STATE_DIR | Out-Null

$safeRemote = $Remote.Replace(".", "_").Replace("/", "_")
$RECV_FILE = Join-Path $STATE_DIR "last-recv-$safeRemote.txt"
$SENT_FILE = Join-Path $STATE_DIR "last-sent-$safeRemote.txt"

# -- MD5 hash function --
function Get-ClipHash {
    param([string]$text)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
    $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash) -replace "-", ""
}

# -- Test if remote is reachable (TCP connect) --
function Test-Remote {
    param([string]$RemoteHost, [int]$RemotePort)
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $result = $client.BeginConnect($RemoteHost, $RemotePort, $null, $null)
        $ok = $result.AsyncWaitHandle.WaitOne(2000)  # 2s timeout
        $client.Close()
        return $ok
    }
    catch {
        return $false
    }
}

# ============================================================
# BACKGROUND JOB: TCP listener (always running, passive)
# ============================================================
$listenerJob = Start-Job -Name "clipsync-listener" -ArgumentList $Port, $RECV_FILE, $SENT_FILE -ScriptBlock {
    param($port, $recvFile, $sentFile)

    function Get-ClipHash {
        param([string]$text)
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $hash = [System.Security.Cryptography.MD5]::Create().ComputeHash($bytes)
        return [System.BitConverter]::ToString($hash) -replace "-", ""
    }

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $port)
    $listener.Start()

    while ($true) {
        $client = $null; $stream = $null; $reader = $null
        try {
            $client = $listener.AcceptTcpClient()
            $stream = $client.GetStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $data = $reader.ReadToEnd()

            if (-not [string]::IsNullOrEmpty($data)) {
                $hash = Get-ClipHash $data
                $hash | Out-File -FilePath $recvFile -NoNewline
                $hash | Out-File -FilePath $sentFile -NoNewline
                Set-Clipboard -Value $data
            }
        }
        catch {
            # AcceptTcpClient can throw on shutdown; ignore
            Start-Sleep -Milliseconds 500
        }
        finally {
            if ($reader) { $reader.Dispose() }
            if ($stream) { $stream.Dispose() }
            if ($client) { $client.Dispose() }
        }
    }
}

# ============================================================
# FOREGROUND: clipboard watcher with connection-aware sending
# ============================================================
$SCRIPT:wasConnected = $false
$SCRIPT:lastClipboard = ""
$SCRIPT:backoff = 5          # seconds
$SCRIPT:failCount = 0

# Initial clipboard state
try { $SCRIPT:lastClipboard = Get-Clipboard -Raw -ErrorAction Stop } catch { $SCRIPT:lastClipboard = "" }

while ($true) {
    Start-Sleep -Milliseconds 500

    # Only try to send if remote is reachable
    if (-not (Test-Remote $Remote $Port)) {
        $SCRIPT:failCount++
        if ($SCRIPT:wasConnected) {
            # State transition: connected -> disconnected
            Write-Host "[clipsync] Desconectado de ${Remote}:${Port} - aguardando VM..." -ForegroundColor DarkYellow
            $SCRIPT:wasConnected = $false
            $SCRIPT:backoff = 5
        }
        # Exponential backoff for probe attempts (5s, 10s, 20s, ... max 60s)
        $SCRIPT:backoff = [Math]::Min($SCRIPT:backoff * 2, 60)
        Start-Sleep -Seconds $SCRIPT:backoff
        continue
    }

    # Connected!
    if (-not $SCRIPT:wasConnected) {
        Write-Host "[clipsync] Conectado a ${Remote}:${Port}" -ForegroundColor Green
        $SCRIPT:wasConnected = $true
        $SCRIPT:failCount = 0
        $SCRIPT:backoff = 5
    }

    # -- Read clipboard --
    $current = ""
    try {
        $current = Get-Clipboard -Raw -ErrorAction Stop
    }
    catch {
        continue
    }

    if ([string]::IsNullOrEmpty($current)) { continue }
    if ($current -eq $SCRIPT:lastClipboard) { continue }

    $SCRIPT:lastClipboard = $current
    $hash = Get-ClipHash $current

    # Don't echo what we just received
    $lastRecv = ""
    try {
        $c = Get-Content $RECV_FILE -ErrorAction Stop
        if ($c) { $lastRecv = $c }
    } catch { }

    if ($hash -eq $lastRecv) { continue }

    # Send to Linux
    $hash | Out-File -FilePath $SENT_FILE -NoNewline
    $tcpClient = $null; $tcpStream = $null; $writer = $null
    try {
        $tcpClient = [System.Net.Sockets.TcpClient]::new($Remote, $Port)
        $tcpStream = $tcpClient.GetStream()
        $writer = New-Object System.IO.StreamWriter($tcpStream)
        $writer.Write($current)
        $writer.Flush()
    }
    catch {
        # Silent - connection health check will handle notification
    }
    finally {
        if ($writer) { $writer.Dispose() }
        if ($tcpStream) { $tcpStream.Dispose() }
        if ($tcpClient) { $tcpClient.Dispose() }
    }
}

# Cleanup on Ctrl+C
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Get-Job -Name "clipsync-listener" -ErrorAction SilentlyContinue | Stop-Job | Remove-Job
} | Out-Null
