# Start Both Server and Client
# Inicia duas instâncias simultâneas do app

$ErrorActionPreference = "Stop"

# Cores para output
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput White "=========================================="
Write-ColorOutput White "Backup Database - Server + Client"
Write-ColorOutput White "=========================================="
Write-Output ""

# Verificar se estamos no diretório correto
if (-not (Test-Path "pubspec.yaml")) {
    Write-ColorOutput Red "ERRO: Execute este script na raiz do projeto"
    exit 1
}

# Backup do .env atual
if (Test-Path ".env") {
    Copy-Item ".env" ".env.backup" -Force
    Write-ColorOutput Yellow "Backup do .env atual criado: .env.backup"
}

Write-Output ""
Write-ColorOutput Green "Passo 1: Iniciando SERVIDOR..."
Write-Output ""

# Configurar e iniciar servidor
Copy-Item ".env.server" ".env" -Force

# Iniciar servidor em background
$serverProcess = Start-Process -FilePath "flutter" -ArgumentList "run", "-d", "windows" -PassThru -WindowStyle Minimized

Write-ColorOutput Green "✓ Servidor iniciado (PID: $($serverProcess.Id))"
Write-ColorOutput Yellow "Aguardando 10 segundos para o servidor inicializar..."
Start-Sleep -Seconds 10

Write-Output ""
Write-ColorOutput Cyan "Passo 2: Iniciando CLIENTE..."
Write-Output ""

# Configurar e iniciar cliente
Copy-Item ".env.client" ".env" -Force

# Iniciar cliente em foreground
Write-ColorOutput Cyan "✓ Cliente iniciando..."
Write-ColorOutput Green "=========================================="
Write-ColorOutput Green "Ambas as instâncias estão rodando!"
Write-ColorOutput Green "=========================================="
Write-Output ""
Write-ColorOutput White "SERVIDOR:"
Write-ColorOutput White "  - Modo: Server"
Write-ColorOutput White "  - Porta: 9527"
Write-ColorOutput White "  - PID: $($serverProcess.Id)"
Write-Output ""
Write-ColorOutput White "CLIENTE:"
Write-ColorOutput White "  - Modo: Client"
Write-ColorOutput White "  - Conecte em: localhost:9527"
Write-Output ""
Write-ColorOutput Yellow "Pressione Ctrl+C no cliente para parar ambos"
Write-Output ""

# Armazenar PID do servidor para cleanup posterior
$serverProcess.Id | Out-File -FilePath ".server.pid" -Encoding ASCII

try {
    # Iniciar cliente (bloqueia aqui)
    & flutter run -d windows
}
finally {
    # Cleanup: matar servidor
    Write-Output ""
    Write-ColorOutput Yellow "Parando servidor..."

    if (Test-Path ".server.pid") {
        $serverPid = Get-Content ".server.pid"
        Stop-Process -Id $serverPid -Force -ErrorAction SilentlyContinue
        Remove-Item ".server.pid" -Force
        Write-ColorOutput Green "✓ Servidor parado"
    }

    # Restaurar .env original
    if (Test-Path ".env.backup") {
        Copy-Item ".env.backup" ".env" -Force
        Remove-Item ".env.backup" -Force
        Write-ColorOutput Yellow "✓ Configuração original restaurada"
    }
}
