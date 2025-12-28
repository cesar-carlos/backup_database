# Script para remover serviço Backup Database do Windows
# Deve ser executado como Administrador

param(
    [string]$ServiceName = "BackupDatabaseService",
    [string]$NssmPath = ""
)

# Verificar se está executando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito e selecione 'Executar como administrador'" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Determinar caminho do NSSM se não fornecido
if ([string]::IsNullOrEmpty($NssmPath)) {
    $NssmPath = Join-Path $PSScriptRoot "nssm.exe"
}

# Verificar se NSSM existe
if (-not (Test-Path $NssmPath)) {
    Write-Host "ERRO: NSSM não encontrado em: $NssmPath" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Verificar se o serviço existe
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Serviço não encontrado: $ServiceName" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 0
}

Write-Host "Parando serviço..." -ForegroundColor Yellow
& $NssmPath stop $ServiceName

Start-Sleep -Seconds 2

Write-Host "Removendo serviço..." -ForegroundColor Yellow
& $NssmPath remove $ServiceName confirm

if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 3) {
    Write-Host ""
    Write-Host "Serviço removido com sucesso!" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "Erro ao remover serviço (código: $LASTEXITCODE)" -ForegroundColor Red
}

Write-Host ""
Read-Host "Pressione Enter para sair"

