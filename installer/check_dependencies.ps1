# Script de Verificação de Dependências
# Backup Database - Verificação de Requisitos do Sistema

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Backup Database - Verificação" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$allOk = $true

# Verificar Visual C++ Redistributables
Write-Host "[1/4] Verificando Visual C++ Redistributables..." -ForegroundColor Yellow
$vcRedist = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
if ($vcRedist) {
    Write-Host "  ✓ Visual C++ Redistributables encontrado (Versão: $($vcRedist.Version))" -ForegroundColor Green
} else {
    Write-Host "  ✗ Visual C++ Redistributables NÃO encontrado" -ForegroundColor Red
    Write-Host "    Download: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    $allOk = $false
}
Write-Host ""

# Verificar sqlcmd (SQL Server)
Write-Host "[2/4] Verificando sqlcmd (SQL Server)..." -ForegroundColor Yellow
try {
    $sqlcmdResult = & sqlcmd -? 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ sqlcmd encontrado no PATH" -ForegroundColor Green
        $sqlcmdPath = (Get-Command sqlcmd -ErrorAction SilentlyContinue).Source
        if ($sqlcmdPath) {
            Write-Host "    Localização: $sqlcmdPath" -ForegroundColor Gray
        }
    } else {
        throw "sqlcmd não encontrado"
    }
} catch {
    Write-Host "  ⚠ sqlcmd NÃO encontrado no PATH" -ForegroundColor Yellow
    Write-Host "    Necessário apenas se você usar SQL Server" -ForegroundColor Gray
    Write-Host "    Se você usar apenas Sybase, pode ignorar este aviso." -ForegroundColor Gray
    Write-Host "    Consulte: docs\path_setup.md" -ForegroundColor Yellow
}
Write-Host ""

# Verificar dbbackup (Sybase)
Write-Host "[3/4] Verificando dbbackup (Sybase)..." -ForegroundColor Yellow
try {
    $dbbackupResult = & dbbackup -? 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ dbbackup encontrado no PATH" -ForegroundColor Green
        $dbbackupPath = (Get-Command dbbackup -ErrorAction SilentlyContinue).Source
        if ($dbbackupPath) {
            Write-Host "    Localização: $dbbackupPath" -ForegroundColor Gray
        }
    } else {
        throw "dbbackup não encontrado"
    }
} catch {
    Write-Host "  ⚠ dbbackup NÃO encontrado no PATH" -ForegroundColor Yellow
    Write-Host "    Necessário apenas se você usar Sybase SQL Anywhere" -ForegroundColor Gray
    Write-Host "    Consulte: docs\path_setup.md" -ForegroundColor Yellow
}
Write-Host ""

# Verificar dbisql (Sybase)
Write-Host "[4/4] Verificando dbisql (Sybase)..." -ForegroundColor Yellow
try {
    $dbisqlResult = & dbisql -? 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ dbisql encontrado no PATH" -ForegroundColor Green
        $dbisqlPath = (Get-Command dbisql -ErrorAction SilentlyContinue).Source
        if ($dbisqlPath) {
            Write-Host "    Localização: $dbisqlPath" -ForegroundColor Gray
        }
    } else {
        throw "dbisql não encontrado"
    }
} catch {
    Write-Host "  ⚠ dbisql NÃO encontrado no PATH" -ForegroundColor Yellow
    Write-Host "    Necessário apenas se você usar Sybase SQL Anywhere" -ForegroundColor Gray
    Write-Host "    Consulte: docs\path_setup.md" -ForegroundColor Yellow
}
Write-Host ""

# Resumo
Write-Host "========================================" -ForegroundColor Cyan
if ($allOk) {
    Write-Host "  Status: TODAS as dependências obrigatórias OK" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Você pode executar o Backup Database normalmente." -ForegroundColor Green
} else {
    Write-Host "  Status: ALGUMAS dependências estão faltando" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Ações necessárias:" -ForegroundColor Yellow
    Write-Host "  1. Instale as dependências faltantes" -ForegroundColor Yellow
    Write-Host "  2. Consulte docs\requirements.md para mais informações" -ForegroundColor Yellow
    Write-Host "  3. Consulte docs\path_setup.md para configurar o PATH" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Pausa para o usuário ler
if (-not $allOk) {
    Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

