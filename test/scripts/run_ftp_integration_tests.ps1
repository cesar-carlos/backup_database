# Run FTP Integration Tests
# Executa testes de integração FTP (upload completo, fallback sem REST, testConnection)
# Usa ftp_server in-process - nao requer servidor FTP externo

$ErrorActionPreference = "Stop"

$env:RUN_FTP_INTEGRATION = "1"

Write-Host "==========================================" -ForegroundColor White
Write-Host "Testes de Integração FTP" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

$result = flutter test "test/integration/ftp_integration_test.dart" 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "PASSED: Todos os testes FTP passaram" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "FAILED: Testes FTP falharam" -ForegroundColor Red
    Write-Output $result
    exit 1
}
