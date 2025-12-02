# Script para sincronizar versão do pubspec.yaml com setup.iss
# Uso: .\update_version.ps1

$ErrorActionPreference = "Stop"

Write-Host "Sincronizando versão do pubspec.yaml com setup.iss..." -ForegroundColor Cyan

# Caminhos dos arquivos
$pubspecPath = Join-Path $PSScriptRoot "..\pubspec.yaml"
$setupIssPath = Join-Path $PSScriptRoot "setup.iss"

# Verificar se os arquivos existem
if (-not (Test-Path $pubspecPath)) {
    Write-Host "ERRO: pubspec.yaml não encontrado em: $pubspecPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $setupIssPath)) {
    Write-Host "ERRO: setup.iss não encontrado em: $setupIssPath" -ForegroundColor Red
    exit 1
}

# Ler versão do pubspec.yaml
$pubspecContent = Get-Content $pubspecPath -Raw
if ($pubspecContent -match 'version:\s*([^\s]+)') {
    $version = $matches[1].Trim()
    Write-Host "Versão encontrada no pubspec.yaml: $version" -ForegroundColor Green
} else {
    Write-Host "ERRO: Não foi possível encontrar a versão no pubspec.yaml" -ForegroundColor Red
    exit 1
}

# Ler conteúdo do setup.iss linha por linha
$setupIssLines = Get-Content $setupIssPath
$updated = $false
$newLines = @()

foreach ($line in $setupIssLines) {
    if ($line -match '^#define\s+MyAppVersion\s+".*"') {
        $newLines += "#define MyAppVersion `"$version`""
        $updated = $true
    } else {
        $newLines += $line
    }
}

if ($updated) {
    # Salvar o arquivo atualizado
    $newLines | Set-Content -Path $setupIssPath
    
    Write-Host "Versão atualizada no setup.iss: $version" -ForegroundColor Green
    Write-Host "Arquivo atualizado com sucesso!" -ForegroundColor Green
} else {
    Write-Host "ERRO: Não foi possível encontrar #define MyAppVersion no setup.iss" -ForegroundColor Red
    exit 1
}

