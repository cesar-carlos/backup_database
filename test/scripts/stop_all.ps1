# Stop All Instances
# Para todas as instâncias do Backup Database (server + client)

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
Write-ColorOutput White "Parando Todas as Instâncias"
Write-ColorOutput White "=========================================="
Write-Output ""

# Contar processos
$processes = Get-Process | Where-Object {
    $_.ProcessName -like "*flutter*" -or
    $_.ProcessName -like "*dart*" -or
    $_.MainWindowTitle -like "*Backup Database*"
}

if ($processes.Count -eq 0) {
    Write-ColorOutput Yellow "⚠ Nenhuma instância rodando"
    exit 0
}

Write-ColorOutput Cyan "Encontradas $($processes.Count) instâncias:"
Write-Output ""

$processes | ForEach-Object {
    Write-ColorOutput White "  - $($_.ProcessName) (PID: $($_.Id), CPU: $($_.CPU))"
}

Write-Output ""
Write-ColorOutput Yellow "Deseja parar todas as instâncias? (S/N)"
$response = Read-Host

if ($response -ne "S" -and $response -ne "s") {
    Write-ColorOutput Yellow "Operação cancelada"
    exit 0
}

Write-Output ""
Write-ColorOutput Cyan "Parando instâncias..."
Write-Output ""

$stopped = 0
$processes | ForEach-Object {
    try {
        Stop-Process -Id $_.Id -Force -ErrorAction Stop
        Write-ColorOutput Green "✓ Parado: $($_.ProcessName) (PID: $($_.Id))"
        $stopped++
    }
    catch {
        Write-ColorOutput Red "✗ Erro ao parar $($_.ProcessName): $($_.Exception.Message)"
    }
}

Write-Output ""
Write-ColorOutput Green "=========================================="
Write-ColorOutput Green "Total de instâncias paradas: $stopped"
Write-ColorOutput Green "=========================================="

# Limpeza de arquivos temporários
Write-Output ""
Write-ColorOutput Cyan "Limpando arquivos temporários..."

$tempFiles = @(".env.backup", ".server.pid")
$cleaned = 0

foreach ($file in $tempFiles) {
    if (Test-Path $file) {
        Remove-Item $file -Force
        Write-ColorOutput Green "✓ Removido: $file"
        $cleaned++
    }
}

if ($cleaned -eq 0) {
    Write-ColorOutput Gray "  Nenhum arquivo temporário encontrado"
} else {
    Write-ColorOutput Green "✓ $cleaned arquivos temporários removidos"
}

Write-Output ""
Write-ColorOutput Green "Limpeza concluída!"
