# Script para instalar Backup Database como serviço do Windows
# Deve ser executado como Administrador

param(
    [string]$ServiceName = "BackupDatabaseService",
    [string]$AppPath = "",
    [string]$AppDirectory = "",
    [string]$NssmPath = "",
    [string]$DisplayName = "Backup Database Service",
    [string]$Description = "Serviço de backup automático para SQL Server e Sybase",
    [string]$ServiceUser = "",
    [SecureString]$ServicePassword
)

# Verificar se está executando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito e selecione 'Executar como administrador'" -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Determinar caminhos se não fornecidos
if ([string]::IsNullOrEmpty($AppPath)) {
    $AppPath = Join-Path $PSScriptRoot "..\backup_database.exe"
}

if ([string]::IsNullOrEmpty($AppDirectory)) {
    $AppDirectory = Split-Path $AppPath -Parent
}

if ([string]::IsNullOrEmpty($NssmPath)) {
    $NssmPath = Join-Path $PSScriptRoot "nssm.exe"
}

# Verificar se NSSM existe
if (-not (Test-Path $NssmPath)) {
    Write-Host "ERRO: NSSM não encontrado em: $NssmPath" -ForegroundColor Red
    Write-Host "Verifique se o aplicativo foi instalado corretamente." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Verificar se o executável existe
if (-not (Test-Path $AppPath)) {
    Write-Host "ERRO: Executável não encontrado em: $AppPath" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

Write-Host "Instalando serviço do Windows..." -ForegroundColor Green
Write-Host "Nome do serviço: $ServiceName" -ForegroundColor Cyan
Write-Host "Caminho do executável: $AppPath" -ForegroundColor Cyan

# Verificar se o serviço já existe
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Serviço já existe. Removendo versão anterior..." -ForegroundColor Yellow
    & $NssmPath remove $ServiceName confirm
    Start-Sleep -Seconds 2
}

# Instalar o serviço
Write-Host "Instalando serviço..." -ForegroundColor Green
& $NssmPath install $ServiceName "`"$AppPath`"" --minimized --mode=server

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: Falha ao instalar serviço!" -ForegroundColor Red
    Read-Host "Pressione Enter para sair"
    exit 1
}

# Configurar diretório de trabalho
Write-Host "Configurando diretório de trabalho..." -ForegroundColor Green
& $NssmPath set $ServiceName AppDirectory $AppDirectory

# Configurar nome de exibição
& $NssmPath set $ServiceName DisplayName $DisplayName

# Configurar descrição
& $NssmPath set $ServiceName Description $Description

# Configurar para iniciar automaticamente
& $NssmPath set $ServiceName Start SERVICE_AUTO_START

# Configurar para não exigir sessão interativa
& $NssmPath set $ServiceName AppNoConsole 1

# Configurar redirecionamento de logs
$logPath = "$env:ProgramData\BackupDatabase\logs"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

& $NssmPath set $ServiceName AppStdout "$logPath\service_stdout.log"
& $NssmPath set $ServiceName AppStderr "$logPath\service_stderr.log"

# Configurar auto-restart em caso de crash
& $NssmPath set $ServiceName AppExit Default Restart
& $NssmPath set $ServiceName AppRestartDelay 60000

# Configurar usuário do serviço (se fornecido)
if (-not [string]::IsNullOrEmpty($ServiceUser) -and $null -ne $ServicePassword) {
    $credential = New-Object System.Management.Automation.PSCredential($ServiceUser, $ServicePassword)
    $plainPassword = $credential.GetNetworkCredential().Password

    if ([string]::IsNullOrEmpty($plainPassword)) {
        Write-Host "Senha vazia detectada. Usando LocalSystem..." -ForegroundColor Yellow
        & $NssmPath set $ServiceName ObjectName LocalSystem
    }

    Write-Host "Configurando usuário do serviço..." -ForegroundColor Green
    & $NssmPath set $ServiceName ObjectName $ServiceUser $plainPassword
} else {
    Write-Host "Configurando para rodar como LocalSystem..." -ForegroundColor Green
    & $NssmPath set $ServiceName ObjectName LocalSystem
}

# Verificação pós-instalação
Write-Host ""
Write-Host "Verificando instalação do serviço..." -ForegroundColor Green

$verifyService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $verifyService) {
    Write-Host "ERRO: Serviço '$ServiceName' não encontrado após instalação!" -ForegroundColor Red
    Write-Host "Verifique o log do NSSM e tente novamente." -ForegroundColor Yellow
    Read-Host "Pressione Enter para sair"
    exit 1
}

$scQuery = sc.exe query $ServiceName 2>&1
Write-Host "Status atual do serviço:" -ForegroundColor Cyan
Write-Host $scQuery -ForegroundColor Gray

if ($LASTEXITCODE -ne 0) {
    Write-Host "AVISO: sc query retornou código $LASTEXITCODE — verifique o status manualmente." -ForegroundColor Yellow
} else {
    Write-Host "✓ Serviço criado e registrado com sucesso." -ForegroundColor Green
}

Write-Host ""
Write-Host "Serviço instalado com sucesso!" -ForegroundColor Green
Write-Host ""
Write-Host "Para iniciar o serviço manualmente:" -ForegroundColor Cyan
Write-Host "  sc start $ServiceName" -ForegroundColor White
Write-Host ""
Write-Host "Ou use o Gerenciador de Serviços do Windows (services.msc)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Logs do serviço estão em: $logPath" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione Enter para sair"

