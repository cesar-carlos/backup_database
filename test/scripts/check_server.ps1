# Check if Server is Running
# Verifica se o socket server está respondendo na porta 9527

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
Write-ColorOutput White "Verificando Socket Server"
Write-ColorOutput White "=========================================="
Write-Output ""

$port = 9527
$hostServer = "localhost"

Write-ColorOutput Cyan "Testando conexão em $hostServer`:$port"
Write-Output ""

try {
    # Tentar conexão TCP
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync($hostServer, $port)
    $completed = $connectTask.Wait(5000) # 5 segundos timeout

    if ($completed) {
        Write-ColorOutput Green "✓ SUCESSO: Server está rodando e aceitando conexões"
        Write-Output ""
        Write-ColorOutput White "Detalhes:"
        Write-ColorOutput White "  - Host: $hostServer"
        Write-ColorOutput White "  - Porta: $port"
        Write-ColorOutput White "  - Status: Conectado"

        $tcpClient.Close()
    }
    else {
        Write-ColorOutput Red "✗ FALHA: Timeout ao conectar (5s)"
        Write-ColorOutput Yellow "Possíveis causas:"
        Write-ColorOutput Yellow "  - Server não está rodando"
        Write-ColorOutput Yellow "  - Firewall bloqueando a porta $port"
        Write-ColorOutput Yellow "  - Server rodando em porta diferente"
    }
}
catch {
    Write-ColorOutput Red "✗ ERRO: $($_.Exception.Message)"
    Write-ColorOutput Yellow "Verifique se:"
    Write-ColorOutput Yellow "  1. O server está rodando (use start_server.ps1)"
    Write-ColorOutput Yellow "  2. DEBUG_APP_MODE=server no .env"
    Write-ColorOutput Yellow "  3. SINGLE_INSTANCE_ENABLED=false no .env"
}

Write-Output ""
Write-ColorOutput White "=========================================="
