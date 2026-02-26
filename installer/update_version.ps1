# Script para sincronizar versao do pubspec.yaml com setup.iss e .env
# Uso: .\update_version.ps1

$ErrorActionPreference = "Stop"

try {
    Write-Host "Sincronizando versao do pubspec.yaml com setup.iss e .env..." -ForegroundColor Cyan

    # Caminhos dos arquivos
    $pubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
    $setupIssPath = Join-Path $PSScriptRoot "setup.iss"
    $envPath = Join-Path $PSScriptRoot "..\.env"

    # Verificar se os arquivos existem
    if (-not (Test-Path $pubspecPath)) {
        Write-Host "ERRO: pubspec.yaml nao encontrado em: $pubspecPath" -ForegroundColor Red
        exit 1
    }

    if (-not (Test-Path $setupIssPath)) {
        Write-Host "ERRO: setup.iss nao encontrado em: $setupIssPath" -ForegroundColor Red
        exit 1
    }

    # Ler versao do pubspec.yaml
    $pubspecContent = Get-Content $pubspecPath -Raw -Encoding UTF8
    if ($pubspecContent -match 'version:\s*([^\s]+)') {
        $fullVersion = $matches[1].Trim()
        # Extrair apenas a parte da versao (sem build number) para .env
        if ($fullVersion -match '^([^+]+)') {
            $versionOnly = $matches[1].Trim()
        } else {
            $versionOnly = $fullVersion
        }
        Write-Host "Versao encontrada no pubspec.yaml: $fullVersion" -ForegroundColor Green
        Write-Host "Versao (sem build): $versionOnly" -ForegroundColor Gray
    } else {
        Write-Host "ERRO: Nao foi possivel encontrar a versao no pubspec.yaml" -ForegroundColor Red
        exit 1
    }

    # Atualizar setup.iss
    $setupIssLines = Get-Content $setupIssPath -Encoding UTF8
    $setupIssUpdated = $false
    $newSetupIssLines = @()

    foreach ($line in $setupIssLines) {
        if ($line -match '^#define\s+MyAppVersion\s+".*"') {
            $newLine = "#define MyAppVersion `"$fullVersion`""
            $newSetupIssLines += $newLine
            $setupIssUpdated = $true
        } else {
            $newSetupIssLines += $line
        }
    }

    if ($setupIssUpdated) {
        $newSetupIssLines | Set-Content -Path $setupIssPath -Encoding UTF8
        Write-Host "Versao atualizada no setup.iss: $fullVersion" -ForegroundColor Green
    } else {
        Write-Host "ERRO: Nao foi possivel encontrar #define MyAppVersion no setup.iss" -ForegroundColor Red
        exit 1
    }

    # Atualizar .env (se existir)
    if (Test-Path $envPath) {
        $envLines = Get-Content $envPath -Encoding UTF8
        $envUpdated = $false
        $newEnvLines = @()
        
        foreach ($line in $envLines) {
            if ($line -match '^APP_VERSION\s*=') {
                $newEnvLines += "APP_VERSION=$versionOnly"
                $envUpdated = $true
            } else {
                $newEnvLines += $line
            }
        }
        
        if ($envUpdated) {
            $newEnvLines | Set-Content -Path $envPath -Encoding UTF8
            Write-Host "Versao atualizada no .env: $versionOnly" -ForegroundColor Green
        } else {
            Write-Host "AVISO: APP_VERSION nao encontrado no .env. Adicionando..." -ForegroundColor Yellow
            $newEnvLines += "APP_VERSION=$versionOnly"
            $newEnvLines | Set-Content -Path $envPath -Encoding UTF8
            Write-Host "APP_VERSION adicionado ao .env: $versionOnly" -ForegroundColor Green
        }
    } else {
        Write-Host "AVISO: Arquivo .env nao encontrado. Pulando atualizacao." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Sincronizacao concluida com sucesso!" -ForegroundColor Green
    exit 0
} catch {
    Write-Host ""
    Write-Host "ERRO: Falha ao sincronizar versao" -ForegroundColor Red
    Write-Host "Detalhes do erro: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Linha: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Comando: $($_.InvocationInfo.Line)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Stack trace:" -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
    exit 1
}
