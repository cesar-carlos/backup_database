# Script automatizado para criar o instalador
# Faz: sincronizar versão + compilar instalador
# Uso: .\build_installer.ps1

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Build do Instalador - Backup Database" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Caminhos
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$updateVersionScript = Join-Path $scriptRoot "update_version.ps1"
$setupIssPath = Join-Path $scriptRoot "setup.iss"

# Passo 1: Sincronizar versão
Write-Host "Passo 1: Sincronizando versão..." -ForegroundColor Yellow
if (Test-Path $updateVersionScript) {
    & powershell -ExecutionPolicy Bypass -File $updateVersionScript
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO: Falha ao sincronizar versão" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "AVISO: Script update_version.ps1 não encontrado. Pulando sincronização." -ForegroundColor Yellow
}
Write-Host ""

# Passo 2: Verificar se o projeto foi compilado
Write-Host "Passo 2: Verificando build do Flutter..." -ForegroundColor Yellow
$buildPath = Join-Path $projectRoot "build\windows\x64\runner\Release"
$exePath = Join-Path $buildPath "backup_database.exe"

if (-not (Test-Path $exePath)) {
    Write-Host "ERRO: Executável não encontrado em: $exePath" -ForegroundColor Red
    Write-Host "Execute primeiro: flutter build windows --release" -ForegroundColor Yellow
    exit 1
}
Write-Host "✓ Executável encontrado" -ForegroundColor Green
Write-Host ""

# Passo 3: Localizar Inno Setup Compiler
Write-Host "Passo 3: Localizando Inno Setup Compiler..." -ForegroundColor Yellow
$programFilesX86 = ${env:ProgramFiles(x86)}
$programFiles = $env:ProgramFiles

$innoSetupPaths = @(
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    "$programFilesX86\Inno Setup 6\ISCC.exe",
    "$programFiles\Inno Setup 6\ISCC.exe"
)

$isccPath = $null
foreach ($path in $innoSetupPaths) {
    if (Test-Path $path) {
        $isccPath = $path
        break
    }
}

if (-not $isccPath) {
    Write-Host "ERRO: Inno Setup Compiler não encontrado." -ForegroundColor Red
    Write-Host "Instale o Inno Setup 6 de: https://jrsoftware.org/isdl.php" -ForegroundColor Yellow
    exit 1
}
$isccPath = (Resolve-Path $isccPath).Path
Write-Host "✓ Inno Setup encontrado: $isccPath" -ForegroundColor Green
Write-Host ""

# Passo 4: Compilar instalador
Write-Host "Passo 4: Compilando instalador..." -ForegroundColor Yellow
Write-Host "Aguarde, isso pode levar alguns minutos..." -ForegroundColor Gray

$setupIssFullPath = (Resolve-Path $setupIssPath).Path

$process = Start-Process `
    -FilePath $isccPath `
    -ArgumentList @($setupIssFullPath) `
    -Wait `
    -NoNewWindow `
    -PassThru

if ($process.ExitCode -ne 0) {
    Write-Host "ERRO: Falha ao compilar instalador" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Instalador criado com sucesso!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

# Localizar o instalador criado
$distPath = Join-Path $scriptRoot "dist"
if (Test-Path $distPath) {
    $installerFiles = Get-ChildItem -Path $distPath -Filter "*.exe" | Sort-Object LastWriteTime -Descending
    if ($installerFiles.Count -gt 0) {
        $latestInstaller = $installerFiles[0]
        Write-Host ""
        Write-Host "Arquivo: $($latestInstaller.FullName)" -ForegroundColor Cyan
        Write-Host "Tamanho: $([math]::Round($latestInstaller.Length / 1MB, 2)) MB" -ForegroundColor Cyan
        Write-Host ""
    }
}

Write-Host "Próximos passos:" -ForegroundColor Yellow
Write-Host "1. Teste o instalador em uma VM limpa (recomendado)" -ForegroundColor Gray
Write-Host "2. Faça upload para GitHub Releases" -ForegroundColor Gray
Write-Host "3. O GitHub Actions atualizará o appcast.xml automaticamente" -ForegroundColor Gray

