# Script para instalar Backup Database como serviço do Windows
# Deve ser executado como Administrador

param(
    [string]$ServiceName = "BackupDatabaseService",
    [string]$AppPath = "",
    [string]$AppDirectory = "",
    [string]$NssmPath = "",
    [string]$DisplayName = "Backup Database Service",
    [string]$Description = "Servico de backup automatico para SQL Server, Sybase, PostgreSQL e Firebird",
    [string]$ServiceUser = "",
    [SecureString]$ServicePassword,
    [switch]$NonInteractive,
    [switch]$StartAfterInstall
)

function Wait-IfInteractive {
    param([string]$Message = "Pressione Enter para sair")
    if (-not $NonInteractive) {
        Read-Host $Message
    }
}

# Verificar se está executando como administrador
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: Este script deve ser executado como Administrador!" -ForegroundColor Red
    Write-Host "Clique com botão direito e selecione 'Executar como administrador'" -ForegroundColor Yellow
    Wait-IfInteractive
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
    Wait-IfInteractive
    exit 1
}

# Verificar se o executável existe
if (-not (Test-Path $AppPath)) {
    Write-Host "ERRO: Executável não encontrado em: $AppPath" -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

Write-Host "Instalando serviço do Windows..." -ForegroundColor Green
Write-Host "Nome do serviço: $ServiceName" -ForegroundColor Cyan
Write-Host "Caminho do executável: $AppPath" -ForegroundColor Cyan

$serviceUtilsPath = Join-Path $PSScriptRoot 'service_utils.ps1'
$hasServiceUtils = Test-Path $serviceUtilsPath
if ($hasServiceUtils) {
    . $serviceUtilsPath
}

# Verificar se o serviço já existe
$existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($existingService) {
    Write-Host "Serviço já existe. Removendo versão anterior..." -ForegroundColor Yellow
    if ($hasServiceUtils) {
        sc.exe stop $ServiceName | Out-Null
        if (-not (Wait-ServiceStopped -ServiceName $ServiceName)) {
            Write-Host "ERRO: serviço '$ServiceName' nao atingiu STOPPED antes da remocao." -ForegroundColor Red
            Wait-IfInteractive
            exit 1
        }
    }
    & $NssmPath remove $ServiceName confirm
    if ($hasServiceUtils) {
        if (-not (Wait-ServiceRemoved -ServiceName $ServiceName)) {
            Write-Host "ERRO: serviço '$ServiceName' ainda marcado para exclusao." -ForegroundColor Red
            Wait-IfInteractive
            exit 1
        }
    } else {
        Start-Sleep -Seconds 2
    }
}

# Instalar o serviço (apenas o executável, sem argumentos inline)
Write-Host "Instalando serviço..." -ForegroundColor Green
& $NssmPath install $ServiceName "`"$AppPath`""

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERRO: Falha ao instalar serviço!" -ForegroundColor Red
    Wait-IfInteractive
    exit 1
}

# Helper: configura uma chave crítica do NSSM e aborta em caso de falha.
function Set-NssmCritical {
    param(
        [string]$Key,
        [string[]]$ExtraArgs = @()
    )
    & $NssmPath set $ServiceName $Key @ExtraArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERRO CRÍTICO: falha ao configurar NSSM $Key (exit $LASTEXITCODE). Abortando." -ForegroundColor Red
        & $NssmPath remove $ServiceName confirm | Out-Null
        if ($hasServiceUtils) {
            Wait-ServiceRemoved -ServiceName $ServiceName | Out-Null
        }
        Wait-IfInteractive
        exit 1
    }
}

# Configurar argumentos explicitamente — CRÍTICO: sem os args o serviço roda em modo UI.
# Mantemos a mesma ordem usada por restore_update_state.ps1 e pela doc operacional
# (TROUBLESHOOTING_SERVICE.md) para simplificar grep em logs de auditoria.
Write-Host "Configurando parâmetros do aplicativo..." -ForegroundColor Green
Set-NssmCritical -Key "AppParameters" -ExtraArgs @("--mode=server --minimized --run-as-service")

# Configurar diretório de trabalho — CRÍTICO: necessário para assets e arquivos auxiliares
Write-Host "Configurando diretório de trabalho..." -ForegroundColor Green
Set-NssmCritical -Key "AppDirectory" -ExtraArgs @($AppDirectory)

# Configurar variável de ambiente de detecção — CRÍTICO: fallback de detecção de modo serviço
Write-Host "Configurando variáveis de ambiente..." -ForegroundColor Green
Set-NssmCritical -Key "AppEnvironmentExtra" -ExtraArgs @("SERVICE_MODE=server")

# Configurações não-críticas (falha gera aviso, não aborta)
& $NssmPath set $ServiceName DisplayName $DisplayName
& $NssmPath set $ServiceName Description $Description
& $NssmPath set $ServiceName Start SERVICE_AUTO_START
Set-NssmCritical -Key "AppNoConsole" -ExtraArgs @("1")

# Configurar redirecionamento de logs
$logPath = "$env:ProgramData\BackupDatabase\logs"
if (-not (Test-Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force | Out-Null
}

Write-Host "Configurando arquivos de log..." -ForegroundColor Green
Set-NssmCritical -Key "AppStdout" -ExtraArgs @("$logPath\service_stdout.log")
Set-NssmCritical -Key "AppStderr" -ExtraArgs @("$logPath\service_stderr.log")

# Configurar auto-restart em caso de crash
& $NssmPath set $ServiceName AppExit Default Restart
# 77 = lockDenied (single-instance) — nao reiniciar
Set-NssmCritical -Key "AppExit" -ExtraArgs @("77", "Exit")
# 78 = handoffForInstaller (auto update silencioso) — nao reiniciar enquanto
# o setup.iss substitui binarios; restore_update_state.ps1 reativa o servico.
Set-NssmCritical -Key "AppExit" -ExtraArgs @("78", "Exit")
& $NssmPath set $ServiceName AppRestartDelay 60000

function Remove-ServiceAfterAccountFailure {
    param([string]$Reason)
    Write-Host "ERRO CRÍTICO: $Reason. Abortando." -ForegroundColor Red
    & $NssmPath remove $ServiceName confirm | Out-Null
    if ($hasServiceUtils) {
        Wait-ServiceRemoved -ServiceName $ServiceName | Out-Null
    }
    Wait-IfInteractive
    exit 1
}

function New-LockedServicePasswordFile {
    param([string]$Password)
    $stamp = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) "backup_db_svc_pwd_${stamp}_$suffix.txt"
    try {
        [System.IO.File]::WriteAllText($path, '')
    } catch {
        return $null
    }
    & icacls.exe $path /inheritance:r /grant:r 'NT AUTHORITY\SYSTEM:(F)' 'BUILTIN\Administrators:(F)' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
    try {
        [System.IO.File]::WriteAllText($path, $Password)
    } catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $null
    }
    return $path
}

function Set-ServiceAccountFromFile {
    param(
        [string]$User,
        [string]$SecretFile
    )
    if (-not (Test-Path -LiteralPath $SecretFile)) {
        Write-Host "ERRO: arquivo de senha ausente." -ForegroundColor Red
        return $false
    }
    $servicePassword = [System.IO.File]::ReadAllText($SecretFile)
    if (-not ('BackupDbServiceConfig' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BackupDbServiceConfig {
  [DllImport("advapi32.dll", EntryPoint="OpenSCManagerW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr OpenSCManager(string machine, string database, uint access);

  [DllImport("advapi32.dll", EntryPoint="OpenServiceW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr OpenService(IntPtr scm, string name, uint access);

  [DllImport("advapi32.dll", EntryPoint="ChangeServiceConfigW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool ChangeServiceConfig(
    IntPtr service,
    uint serviceType,
    uint startType,
    uint errorControl,
    string binaryPath,
    string loadOrderGroup,
    IntPtr tagId,
    string dependencies,
    string startName,
    string password,
    string displayName);

  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool CloseServiceHandle(IntPtr handle);
}
'@
    }
    $scm = [BackupDbServiceConfig]::OpenSCManager($null, $null, 1)
    if ($scm -eq [IntPtr]::Zero) {
        $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Write-Host "ERRO: OpenSCManager $code" -ForegroundColor Red
        return $false
    }
    try {
        $svc = [BackupDbServiceConfig]::OpenService($scm, $ServiceName, 2)
        if ($svc -eq [IntPtr]::Zero) {
            $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            Write-Host "ERRO: OpenService $code" -ForegroundColor Red
            return $false
        }
        try {
            $noChange = [uint32]::MaxValue
            $ok = [BackupDbServiceConfig]::ChangeServiceConfig(
                $svc, $noChange, $noChange, $noChange,
                $null, $null, [IntPtr]::Zero, $null,
                $User, $servicePassword, $null)
            if (-not $ok) {
                $code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
                Write-Host "ERRO: ChangeServiceConfig $code" -ForegroundColor Red
                return $false
            }
            return $true
        } finally {
            [BackupDbServiceConfig]::CloseServiceHandle($svc) | Out-Null
            $servicePassword = $null
        }
    } finally {
        [BackupDbServiceConfig]::CloseServiceHandle($scm) | Out-Null
    }
}

# Configurar usuário do serviço. Senha nunca vai para o argv do nssm:
# arquivo temporário com ACL e ChangeServiceConfigW.
if (-not [string]::IsNullOrEmpty($ServiceUser) -and $null -ne $ServicePassword) {
    $credential = New-Object System.Management.Automation.PSCredential($ServiceUser, $ServicePassword)
    $plainPassword = $credential.GetNetworkCredential().Password

    if ([string]::IsNullOrEmpty($plainPassword)) {
        $plainPassword = $null
        Write-Host "Senha vazia detectada. Usando LocalSystem..." -ForegroundColor Yellow
        & $NssmPath set $ServiceName ObjectName LocalSystem
    } else {
        Write-Host "Configurando usuário do serviço..." -ForegroundColor Green
        $secretFile = $null
        $accountConfigured = $false
        try {
            $secretFile = New-LockedServicePasswordFile -Password $plainPassword
            $plainPassword = $null
            if ([string]::IsNullOrEmpty($secretFile)) {
                $accountConfigured = $false
            } else {
                $accountConfigured = Set-ServiceAccountFromFile -User $ServiceUser -SecretFile $secretFile
            }
        } finally {
            $plainPassword = $null
            if (-not [string]::IsNullOrEmpty($secretFile) -and (Test-Path -LiteralPath $secretFile)) {
                Remove-Item -LiteralPath $secretFile -Force -ErrorAction SilentlyContinue
            }
        }
        if (-not $accountConfigured) {
            Remove-ServiceAfterAccountFailure -Reason "falha ao definir a conta do servico (ChangeServiceConfig)"
        }
        Write-Host "AVISO: conta customizada desabilita a restauracao automatica do update silencioso do servico." -ForegroundColor Yellow
    }
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
    Wait-IfInteractive
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
Write-Host "Logs do serviço estão em: $logPath" -ForegroundColor Cyan
Write-Host ""

if ($StartAfterInstall) {
    $serviceUtilsPath = Join-Path $PSScriptRoot 'service_utils.ps1'
    if (-not (Test-Path $serviceUtilsPath)) {
        Write-Host "ERRO: service_utils.ps1 nao encontrado em: $serviceUtilsPath" -ForegroundColor Red
        Wait-IfInteractive
        exit 1
    }

    . $serviceUtilsPath

    Write-Host "Iniciando servico e aguardando RUNNING..." -ForegroundColor Green
    $isRunning = Start-WindowsServiceWithPolling -ServiceName $ServiceName
    if (-not $isRunning) {
        Write-Host (
            "AVISO: servico instalado mas nao confirmou RUNNING dentro de " +
            "$script:ServiceStartPollingTimeoutSeconds segundos."
        ) -ForegroundColor Yellow
        Wait-IfInteractive
        exit 2
    }

    Write-Host "Servico em execucao (RUNNING confirmado)." -ForegroundColor Green
    Write-Host ""
    Wait-IfInteractive
    exit 0
}

Write-Host "Para iniciar o serviço manualmente:" -ForegroundColor Cyan
Write-Host "  sc start $ServiceName" -ForegroundColor White
Write-Host ""
Write-Host "Ou use o Gerenciador de Serviços do Windows (services.msc)" -ForegroundColor Cyan
Write-Host ""
Wait-IfInteractive
