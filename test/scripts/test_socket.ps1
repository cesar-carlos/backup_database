# Quick Socket Test
# Testa a comunicação socket entre servidor e cliente

$ErrorActionPreference = "Stop"

function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

Write-ColorOutput White "=========================================="
Write-ColorOutput White "Teste de Comunicação Socket"
Write-ColorOutput White "=========================================="
Write-Output ""

# Passo 1: Verificar se o servidor está rodando
Write-ColorOutput Cyan "Passo 1: Verificando servidor..."

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync("localhost", 9527)
    $completed = $connectTask.Wait(3000)

    if (-not $completed) {
        Write-ColorOutput Red "✗ Server não está respondendo"
        Write-ColorOutput Yellow "Inicie o servidor com: .\start_server.ps1"
        exit 1
    }

    Write-ColorOutput Green "✓ Server está rodando na porta 9527"
    $tcpClient.Close()
}
catch {
    Write-ColorOutput Red "✗ Erro ao verificar servidor: $($_.Exception.Message)"
    exit 1
}

Write-Output ""

# Passo 2: Verificar configurações do .env
Write-ColorOutput Cyan "Passo 2: Verificando configurações..."

if (-not (Test-Path ".env")) {
    Write-ColorOutput Red "✗ Arquivo .env não encontrado"
    exit 1
}

$envContent = Get-Content ".env"

if ($envContent -match "SINGLE_INSTANCE_ENABLED=true") {
    Write-ColorOutput Red "✗ SINGLE_INSTANCE_ENABLED está true"
    Write-ColorOutput Yellow "Mude para false para permitir múltiplas instâncias"
    Write-Output ""
    Write-ColorOutput Yellow "No .env:"
    Write-ColorOutput Yellow "  SINGLE_INSTANCE_ENABLED=false"
    exit 1
} else {
    Write-ColorOutput Green "✓ Single instance desabilitado"
}

if ($envContent -match "DEBUG_APP_MODE=(server|client)") {
    $mode = $matches[1]
    Write-ColorOutput Green "✓ Modo configurado: $mode"
} else {
    Write-ColorOutput Red "✗ DEBUG_APP_MODE não encontrado no .env"
    exit 1
}

Write-Output ""

# Passo 3: Testar integração
Write-ColorOutput Cyan "Passo 3: Testes de integração disponíveis"
Write-Output ""

Write-ColorOutput White "Testes automatizados:"
Write-ColorOutput White "  1. dart test test/integration/socket_integration_test.dart"
Write-ColorOutput White "  2. dart test test/integration/file_transfer_integration_test.dart"
Write-Output ""

Write-ColorOutput White "Teste manual:"
Write-ColorOutput White "  1. Inicie o servidor: .\start_server.ps1"
Write-ColorOutput White "  2. Inicie o cliente: .\start_client.ps1"
Write-ColorOutput White "  3. No cliente, conecte em localhost:9527"
Write-ColorOutput White "  4. Teste: listar agendamentos, transferir arquivos"
Write-Output ""

Write-ColorOutput Green "=========================================="
Write-ColorOutput Green "Sistema pronto para testes!"
Write-ColorOutput Green "=========================================="
Write-Output ""
Write-ColorOutput Yellow "Dica: Use check_server.ps1 para verificar se o server está rodando"
