# Find and Display Recent Logs
# Encontra e exibe logs recentes para debugging rápido

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
Write-ColorOutput White "Buscando Logs Recentes"
Write-ColorOutput White "=========================================="
Write-Output ""

# Diretório de dados do app
$appDataPath = "$env:APPDATA\backup_database"

if (-not (Test-Path $appDataPath)) {
    Write-ColorOutput Red "✗ Diretório de dados não encontrado: $appDataPath"
    exit 1
}

Write-ColorOutput Cyan "Diretório: $appDataPath"
Write-Output ""

# Buscar arquivos de log
$logFiles = Get-ChildItem -Path $appDataPath -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($logFiles.Count -eq 0) {
    Write-ColorOutput Yellow "⚠ Nenhum arquivo de log encontrado"
    Write-Output ""
    Write-ColorOutput Yellow "Possíveis causas:"
    Write-ColorOutput Yellow "  1. App ainda não foi executado"
    Write-ColorOutput Yellow "  2. Logs desabilitados"
    Write-ColorOutput Yellow "  3. Diretório de dados diferente"
    exit 0
}

Write-ColorOutput Green "✓ Encontrados $($logFiles.Count) arquivos de log"
Write-Output ""

# Mostrar os 5 logs mais recentes
Write-ColorOutput Cyan "Logs mais recentes:"
Write-Output ""

$logFiles | Select-Object -First 5 | ForEach-Object {
    $size = [math]::Round($_.Length / 1KB, 2)
    Write-ColorOutput White "$($_.Name)"
    Write-ColorOutput Gray "  Path: $($_.DirectoryName)"
    Write-ColorOutput Gray "  Tamanho: ${size} KB"
    Write-ColorOutput Gray "  Modificado: $($_.LastWriteTime)"
    Write-Output ""
}

# Perguntar se quer abrir algum log
Write-ColorOutput Yellow "Deseja abrir o log mais recente? (S/N)"
$response = Read-Host

if ($response -eq "S" -or $response -eq "s") {
    $latestLog = $logFiles[0]
    Write-ColorOutput Cyan "Abrindo: $($latestLog.FullName)"
    notepad $latestLog.FullName
}
