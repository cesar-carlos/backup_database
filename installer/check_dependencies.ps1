# Script de verificacao de dependencias
# Backup Database - requisitos obrigatorios do app + CLIs opcionais por banco

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Backup Database - Verificacao" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$mandatoryOk = $true

function Test-CommandInPath {
    param(
        [string]$CommandName
    )

    $command = Get-Command $CommandName -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        return $null
    }

    return $command.Source
}

function Write-OptionalToolStatus {
    param(
        [string]$Label,
        [string]$CommandName,
        [string]$OnlyIfUsing
    )

    Write-Host $Label -ForegroundColor Yellow
    $commandPath = Test-CommandInPath -CommandName $CommandName
    if ($commandPath) {
        Write-Host "  OK: $CommandName encontrado no PATH" -ForegroundColor Green
        Write-Host "      Localizacao: $commandPath" -ForegroundColor Gray
    } else {
        Write-Host "  AVISO: $CommandName nao encontrado no PATH" -ForegroundColor Yellow
        Write-Host "         Necessario apenas se voce usar $OnlyIfUsing" -ForegroundColor Gray
        Write-Host "         Consulte: docs\\path_setup.md" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "[1/7] Verificando Visual C++ Redistributables..." -ForegroundColor Yellow
$vcRedist = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" -ErrorAction SilentlyContinue
if ($vcRedist) {
    Write-Host "  OK: Visual C++ Redistributables encontrado (versao: $($vcRedist.Version))" -ForegroundColor Green
} else {
    Write-Host "  ERRO: Visual C++ Redistributables nao encontrado" -ForegroundColor Red
    Write-Host "        Download: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
    $mandatoryOk = $false
}
Write-Host ""

Write-OptionalToolStatus -Label "[2/7] Verificando sqlcmd (SQL Server)..." -CommandName "sqlcmd" -OnlyIfUsing "SQL Server"
Write-OptionalToolStatus -Label "[3/7] Verificando dbisql (Sybase SQL Anywhere)..." -CommandName "dbisql" -OnlyIfUsing "Sybase SQL Anywhere"
Write-OptionalToolStatus -Label "[4/7] Verificando dbbackup (Sybase SQL Anywhere)..." -CommandName "dbbackup" -OnlyIfUsing "Sybase SQL Anywhere"
Write-OptionalToolStatus -Label "[5/7] Verificando psql (PostgreSQL)..." -CommandName "psql" -OnlyIfUsing "PostgreSQL"
Write-OptionalToolStatus -Label "[6/7] Verificando pg_basebackup (PostgreSQL)..." -CommandName "pg_basebackup" -OnlyIfUsing "PostgreSQL"
Write-OptionalToolStatus -Label "[7/7] Verificando gbak (Firebird)..." -CommandName "gbak" -OnlyIfUsing "Firebird"

Write-Host "Observacao: para Firebird em producao tambem valide nbackup, gstat e isql." -ForegroundColor Gray
Write-Host ""

Write-Host "========================================" -ForegroundColor Cyan
if ($mandatoryOk) {
    Write-Host "  Status: requisitos obrigatorios do app OK" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Avisos de CLI acima so importam para os bancos que esta maquina realmente usa." -ForegroundColor Green
} else {
    Write-Host "  Status: faltam requisitos obrigatorios do app" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Acoes recomendadas:" -ForegroundColor Yellow
    Write-Host "  1. Instale o Visual C++ Redistributables" -ForegroundColor Yellow
    Write-Host "  2. Consulte docs\\requirements.md" -ForegroundColor Yellow
    Write-Host "  3. Consulte docs\\path_setup.md" -ForegroundColor Yellow
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if (-not $mandatoryOk) {
    Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
