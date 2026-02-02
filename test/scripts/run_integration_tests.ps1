# Run Integration Tests
# Executa todos os testes de integração de socket

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
Write-ColorOutput White "Testes de Integração - Socket"
Write-ColorOutput White "=========================================="
Write-Output ""

# Verificar se servidor está rodando
Write-ColorOutput Cyan "Passo 1: Verificando se servidor está rodando..."

try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectTask = $tcpClient.ConnectAsync("localhost", 9527)
    $completed = $connectTask.Wait(2000)

    if ($completed) {
        Write-ColorOutput Green "✓ Servidor detectado na porta 9527"
        $tcpClient.Close()

        Write-ColorOutput Yellow "⚠ AVISO: Servidor está rodando"
        Write-ColorOutput Yellow "  Os testes iniciarão seu próprio servidor"
        Write-ColorOutput Yellow "  Deseja continuar mesmo assim? (S/N)"
        $response = Read-Host

        if ($response -ne "S" -and $response -ne "s") {
            Write-ColorOutput Yellow "Cancelado pelo usuário"
            exit 0
        }
    }
}
catch {
    Write-ColorOutput Green "✓ Porta 9527 livre (ok para testes)"
}

Write-Output ""

# Executar testes
Write-ColorOutput Cyan "Passo 2: Executando testes de integração..."
Write-Output ""

$tests = @(
    @{Name="Socket Integration"; Path="test/integration/socket_integration_test.dart"},
    @{Name="File Transfer"; Path="test/integration/file_transfer_integration_test.dart"}
)

$passed = 0
$failed = 0
$total = $tests.Count

foreach ($test in $tests) {
    Write-ColorOutput White "=========================================="
    Write-ColorOutput White "Testando: $($test.Name)"
    Write-ColorOutput White "=========================================="
    Write-Output ""

    $testCmd = "dart test `"$($test.Path)`""
    Write-ColorOutput Cyan "Comando: $testCmd"
    Write-Output ""

    $result = Invoke-Expression $testCmd 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-ColorOutput Green "✓ PASSED: $($test.Name)"
        $passed++
    }
    else {
        Write-ColorOutput Red "✗ FAILED: $($test.Name)"
        Write-ColorOutput Red "Resultado:"
        Write-Output $result
        $failed++
    }

    Write-Output ""
}

# Resumo
Write-ColorOutput White "=========================================="
Write-ColorOutput White "Resumo dos Testes"
Write-ColorOutput White "=========================================="
Write-Output ""
Write-ColorOutput White "Total: $total"
Write-ColorOutput Green "Passou: $passed"
Write-ColorOutput Red "Falhou: $failed"
Write-Output ""

if ($failed -eq 0) {
    Write-ColorOutput Green "✓ Todos os testes passaram!"
    exit 0
}
else {
    Write-ColorOutput Red "✗ Alguns testes falharam"
    Write-ColorOutput Yellow "Revise os erros acima e corrija antes de continuar"
    exit 1
}
