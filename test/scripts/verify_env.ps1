# Verify Environment Configuration
$ErrorActionPreference = "Stop"

# Get project root (two levels up from script location)
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $projectRoot

Write-Host "==========================================" -ForegroundColor White
Write-Host "Verificacao de Ambiente" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

$errors = 0
$warnings = 0

# Check .env.server
Write-Host "Arquivos de configuracao:" -ForegroundColor Cyan
Write-Host ""

if (Test-Path ".env.server") {
    Write-Host "[OK] .env.server encontrado" -ForegroundColor Green
} else {
    Write-Host "[ERROR] .env.server NAO encontrado" -ForegroundColor Red
    $errors++
}

if (Test-Path ".env.client") {
    Write-Host "[OK] .env.client encontrado" -ForegroundColor Green
} else {
    Write-Host "[ERROR] .env.client NAO encontrado" -ForegroundColor Red
    $errors++
}

if (Test-Path ".env") {
    Write-Host "[OK] .env encontrado" -ForegroundColor Green
} else {
    Write-Host "[WARN] .env nao encontrado" -ForegroundColor Yellow
    $warnings++
}

Write-Host ""

# Check .env.server content
if (Test-Path ".env.server") {
    Write-Host "Verificando .env.server:" -ForegroundColor Cyan
    Write-Host ""
    $content = Get-Content ".env.server" -Raw -Encoding UTF8

    if ($content -match "SINGLE_INSTANCE_ENABLED=false") {
        Write-Host "[OK] SINGLE_INSTANCE_ENABLED=false" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] SINGLE_INSTANCE_ENABLED deve ser false" -ForegroundColor Red
        $errors++
    }

    if ($content -match "DEBUG_APP_MODE=server") {
        Write-Host "[OK] DEBUG_APP_MODE=server" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] DEBUG_APP_MODE deve ser server" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""

# Check .env.client content
if (Test-Path ".env.client") {
    Write-Host "Verificando .env.client:" -ForegroundColor Cyan
    Write-Host ""
    $content = Get-Content ".env.client" -Raw -Encoding UTF8

    if ($content -match "SINGLE_INSTANCE_ENABLED=false") {
        Write-Host "[OK] SINGLE_INSTANCE_ENABLED=false" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] SINGLE_INSTANCE_ENABLED deve ser false" -ForegroundColor Red
        $errors++
    }

    if ($content -match "DEBUG_APP_MODE=client") {
        Write-Host "[OK] DEBUG_APP_MODE=client" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] DEBUG_APP_MODE deve ser client" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor White
Write-Host "Resumo" -ForegroundColor White
Write-Host "==========================================" -ForegroundColor White
Write-Host ""

if ($errors -eq 0) {
    Write-Host "[OK] Ambiente configurado corretamente!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Proximos passos:" -ForegroundColor White
    Write-Host "  1. .\test\scripts\start_server.ps1 (terminal 1)" -ForegroundColor White
    Write-Host "  2. .\test\scripts\start_client.ps1 (terminal 2)" -ForegroundColor White
    Write-Host "  3. Ou use: .\test\scripts\start_both.ps1" -ForegroundColor White
} else {
    Write-Host "[ERROR] $errors erros encontrados" -ForegroundColor Red
    Write-Host "[ERROR] Corrija os erros antes de continuar" -ForegroundColor Red
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor White

exit $errors
