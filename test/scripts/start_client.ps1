# Start Client Instance
# Inicia o app em modo cliente com configurações isoladas

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

Write-ColorOutput Cyan "=========================================="
Write-ColorOutput Cyan "Backup Database - Starting CLIENT instance"
Write-ColorOutput Cyan "=========================================="
Write-Output ""

# Verificar se estamos no diretório correto
if (-not (Test-Path "pubspec.yaml")) {
    Write-ColorOutput Red "ERRO: Execute este script na raiz do projeto (onde está pubspec.yaml)"
    exit 1
}

# Backup do .env atual
if (Test-Path ".env") {
    Copy-Item ".env" ".env.backup" -Force
    Write-ColorOutput Yellow "Backup do .env atual criado: .env.backup"
}

# Copiar configuração do cliente
Copy-Item ".env.client" ".env" -Force
Write-ColorOutput Cyan "Configuração do cliente carregada (.env.client)"
Write-Output ""

# Verificar SINGLE_INSTANCE_ENABLED
$envContent = Get-Content ".env"
if ($envContent -match "SINGLE_INSTANCE_ENABLED=false") {
    Write-ColorOutput Green "✓ Single instance desabilitado (permite múltiplas instâncias)"
} else {
    Write-ColorOutput Red "✗ SINGLE_INSTANCE_ENABLED deve ser false"
    exit 1
}

if ($envContent -match "DEBUG_APP_MODE=client") {
    Write-ColorOutput Green "✓ Modo CLIENT configurado"
} else {
    Write-ColorOutput Red "✗ DEBUG_APP_MODE deve ser 'client'"
    exit 1
}

Write-Output ""
Write-ColorOutput Cyan "=========================================="
Write-ColorOutput Cyan "Iniciando cliente..."
Write-ColorOutput Cyan "=========================================="
Write-ColorOutput Cyan "Use a UI para conectar ao servidor em localhost:9527"
Write-ColorOutput Cyan "Pressione Ctrl+C para parar"
Write-Output ""

# Iniciar o app
try {
    flutter run -d windows
}
finally {
    # Restaurar .env original
    if (Test-Path ".env.backup") {
        Copy-Item ".env.backup" ".env" -Force
        Remove-Item ".env.backup" -Force
        Write-ColorOutput Yellow "Configuração original restaurada"
    }
}
