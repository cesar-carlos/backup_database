# Get Logs from Server and Client
# Coleta logs de ambas as instâncias para análise

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
Write-ColorOutput White "Coletando Logs - Server + Client"
Write-ColorOutput White "=========================================="
Write-Output ""

# Criar diretório para logs
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logDir = "test_logs_$timestamp"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

Write-ColorOutput Cyan "Diretório de logs: $logDir"
Write-Output ""

# Coletar logs do app (se existirem)
$appDataPath = "$env:APPDATA\backup_database"

if (Test-Path $appDataPath) {
    Write-ColorOutput Green "✓ Diretório de dados encontrado: $appDataPath"

    # Procurar arquivos de log
    $logFiles = Get-ChildItem -Path $appDataPath -Filter "*.log" -Recurse -ErrorAction SilentlyContinue

    if ($logFiles.Count -gt 0) {
        Write-ColorOutput Cyan "Encontrados $($logFiles.Count) arquivos de log"
        Write-Output ""

        foreach ($logFile in $logFiles) {
            $destPath = Join-Path $logDir $logFile.Name
            Copy-Item $logFile.FullName $destPath -Force
            Write-ColorOutput Green "✓ Copiado: $($logFile.Name)"
        }
    } else {
        Write-ColorOutput Yellow "⚠ Nenhum arquivo .log encontrado"
    }
} else {
    Write-ColorOutput Yellow "⚠ Diretório de dados não encontrado"
}

Write-Output ""

# Salvar informações do ambiente
$envInfoPath = Join-Path $logDir "environment_info.txt"
@"
========================================
Environment Information
========================================

Timestamp: $timestamp
Machine: $env:COMPUTERNAME
User: $env:USERNAME

========================================
Flutter Version
========================================
"@ | Out-File -FilePath $envInfoPath -Encoding UTF8

flutter --version | Out-File -FilePath $envInfoPath -Append -Encoding UTF8

@"

========================================
PowerShell Version
========================================
$PSVersionTable
========================================
"@ | Out-File -FilePath $envInfoPath -Append -Encoding UTF8

Write-ColorOutput Green "✓ Informações de ambiente salvas"

Write-Output ""

# Salvar configurações atuais
$configPath = Join-Path $logDir "current_config.txt"
@"
========================================
Current .env Configuration
========================================
"@ | Out-File -FilePath $configPath -Encoding UTF8

if (Test-Path ".env") {
    Get-Content ".env" | Out-File -FilePath $configPath -Append -Encoding UTF8
    Write-ColorOutput Green "✓ Configuração atual salva"
} else {
    "No .env file found" | Out-File -FilePath $configPath -Append -Encoding UTF8
    Write-ColorOutput Yellow "⚠ Nenhum .env encontrado"
}

Write-Output ""

# Resumo
Write-ColorOutput White "=========================================="
Write-ColorOutput Green "Logs coletados com sucesso!"
Write-ColorOutput White "=========================================="
Write-Output ""
Write-ColorOutput White "Local: $logDir\"
Write-ColorOutput White "Arquivos:"
Get-ChildItem $logDir | ForEach-Object {
    Write-ColorOutput Cyan "  - $($_.Name)"
}
Write-Output ""
Write-ColorOutput Yellow "Use estes logs para debugging de problemas"
