# Script para remover serviço Backup Database do Windows
# Deve ser executado como Administrador

param(
    [string]$ServiceName = "BackupDatabaseService",
    [string]$NssmPath = "",
    [switch]$NonInteractive
)

function Wait-IfInteractive {
    param([string]$Message = "Pressione Enter para sair")
    if (-not $NonInteractive) {
        Read-Host $Message
    }
}

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito e selecione 'Executar como administrador'" -ForegroundColor Yellow
    Wait-IfInteractive
    exit 1
}

if ([string]::IsNullOrEmpty($NssmPath)) {
    $NssmPath = Join-Path $PSScriptRoot "nssm.exe"
}

if (-not (Test-Path $NssmPath)) {
    Write-Host "ERRO: NSSM não encontrado em: $NssmPath" -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

$serviceUtilsPath = Join-Path $PSScriptRoot "service_utils.ps1"
if (-not (Test-Path $serviceUtilsPath)) {
    Write-Host "ERRO: service_utils.ps1 não encontrado em: $serviceUtilsPath" -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}
. $serviceUtilsPath

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "Serviço não encontrado: $ServiceName" -ForegroundColor Yellow
    Wait-IfInteractive
    exit 0
}

Write-Host "Parando serviço..." -ForegroundColor Yellow
& $NssmPath stop $ServiceName
if (-not (Wait-ServiceStopped -ServiceName $ServiceName)) {
    Write-Host "ERRO: serviço '$ServiceName' não atingiu STOPPED." -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

Write-Host "Removendo serviço..." -ForegroundColor Yellow
& $NssmPath remove $ServiceName confirm
$removeExit = $LASTEXITCODE
if (-not ($removeExit -eq 0 -or $removeExit -eq 3)) {
    Write-Host "Erro ao remover serviço (código: $removeExit)" -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

if (-not (Wait-ServiceRemoved -ServiceName $ServiceName)) {
    Write-Host "ERRO: serviço '$ServiceName' ainda marcado para exclusão." -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

Write-Host ""
Write-Host "Serviço removido com sucesso!" -ForegroundColor Green
Write-Host ""
Wait-IfInteractive
exit 0
