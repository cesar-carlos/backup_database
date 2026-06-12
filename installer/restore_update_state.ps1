# Restaura o estado operacional apos update silencioso.
#
# Exit codes (contrato com setup.iss / install_service.ps1):
#   0 = sucesso; update_context.json removido ao final
#   1 = falha generica (exception, NSSM start falhou, etc.)
#   2 = condicao recuperavel: conta nao-LocalSystem OU servico nao
#       atingiu RUNNING no polling. update_context.json e PRESERVADO
#       para retry/debug.

param(
    [Parameter(Mandatory = $true)]
    [string]$ContextPath,
    [Parameter(Mandatory = $true)]
    [string]$AppPath,
    [Parameter(Mandatory = $true)]
    [string]$AppDirectory,
    [Parameter(Mandatory = $true)]
    [string]$NssmPath,
    [string]$ServiceName = "BackupDatabaseService"
)

$ErrorActionPreference = "Stop"

# §audit-2026-05-28: capturar erros do script em arquivo dedicado.
# Antes, throws subiam para o stderr do Inno Setup que ia parar em
# logs do Setup que ninguem revisita pos-install. Agora gravamos
# tudo em "restore_update_state.error.log" ao lado do contexto,
# para troubleshooting facil pelo painel de Updates da app.
$ErrorLogPath = Join-Path (Split-Path -Parent $ContextPath) `
    'restore_update_state.error.log'

function Write-RestoreError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [object]$ErrorRecord = $null
    )

    $ts = (Get-Date).ToUniversalTime().ToString('o')
    $line = "[$ts] $Message"
    if ($null -ne $ErrorRecord) {
        $line += "`n$($ErrorRecord | Out-String)"
    }

    # 1) Sempre tenta gravar no error log dedicado (novo: facil de
    #    descobrir no painel Updates da UI sem caçar logs do Setup).
    try {
        $parent = Split-Path -Parent $ErrorLogPath
        if (-not (Test-Path $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        Add-Content -Path $ErrorLogPath -Value $line -Encoding UTF8
    } catch {
        # Falha ao escrever no error log — segue para o stderr abaixo.
    }

    # 2) Sempre emite no stderr (defesa em profundidade): mantem compat
    #    com Inno Setup logs, captura por NSSM e testes que verificam
    #    `result.stderr` (`update_installer_scripts_test.dart`).
    [Console]::Error.WriteLine($line)
}

# Trap global para que QUALQUER exception nao tratada chegue ao
# error log antes do exit. Sem isso, o operador so via "exit code 1"
# do PowerShell e o motivo se perdia.
trap {
    Write-RestoreError -Message "Exception nao tratada em restore_update_state.ps1" -ErrorRecord $_
    exit 1
}

function Test-AuthenticodeSignature {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # Best-effort: registra a assinatura Authenticode do executavel. Nao
    # bloqueia o restore se o binario ainda nao for assinado, mas deixa
    # trilha clara no stdout (capturado por nssm em service_stdout.log).
    if (-not (Test-Path $Path)) {
        Write-Host "AVISO: $Path nao existe para checar Authenticode." -ForegroundColor Yellow
        return
    }
    try {
        $sig = Get-AuthenticodeSignature -FilePath $Path -ErrorAction Stop
    } catch {
        Write-Host "AVISO: falha ao consultar Authenticode de $($Path): $_" -ForegroundColor Yellow
        return
    }
    switch ($sig.Status) {
        'Valid' {
            $subject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { '(sem subject)' }
            Write-Host "OK: Authenticode valido para $Path (assinante: $subject)" -ForegroundColor Green
        }
        'NotSigned' {
            Write-Host "AVISO: $Path nao esta assinado digitalmente." -ForegroundColor Yellow
        }
        default {
            Write-Host "AVISO: Authenticode com status '$($sig.Status)' para $Path; revisar assinatura." -ForegroundColor Yellow
        }
    }
}

function Get-DateValue {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $text = [string]$Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    try {
        return [DateTime]::Parse(
            $text,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
    } catch {
        return $null
    }
}

function Get-ConfigValue {
    param(
        [object]$Config,
        [string]$Name,
        [string]$Default = $null
    )

    if ($null -eq $Config) {
        return $Default
    }

    $property = $Config.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    $value = [string]$property.Value
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $Default
    }

    return $value.Trim()
}

function Set-NssmValue {
    param(
        [string[]]$Arguments
    )

    & $NssmPath @Arguments | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao executar: $NssmPath $($Arguments -join ' ')"
    }
}

if (-not (Test-Path $ContextPath)) {
    exit 0
}

# Loga assinatura Authenticode do binario alvo (defesa-em-profundidade
# alem do SHA-256 ja validado pelo Dart antes do handoff).
Test-AuthenticodeSignature -Path $AppPath

$context = Get-Content -Path $ContextPath -Raw | ConvertFrom-Json
$schemaVersion = 0
if ($null -ne $context.schemaVersion) {
    $schemaVersion = [int]$context.schemaVersion
}
$expiresAt = Get-DateValue -Value $context.expiresAt
$targetVersion = [string]$context.targetVersion

if ($schemaVersion -lt 2 -or [string]::IsNullOrWhiteSpace($targetVersion)) {
    Remove-Item -Path $ContextPath -Force -ErrorAction SilentlyContinue
    exit 0
}

if ($null -eq $expiresAt -or $expiresAt -lt (Get-Date).ToUniversalTime()) {
    Remove-Item -Path $ContextPath -Force -ErrorAction SilentlyContinue
    exit 0
}

$origin = [string]$context.origin
$serviceExists = [bool]$context.serviceExists
$serviceConfig = $context.serviceConfig

if ($serviceExists) {
    if (-not (Test-Path $NssmPath)) {
        throw "NSSM nao encontrado em $NssmPath"
    }

    $logsDir = "C:\ProgramData\BackupDatabase\logs"
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }

    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -ne $existingService) {
        & $NssmPath stop $ServiceName 2>$null | Out-Null
        Start-Sleep -Seconds 2
        & $NssmPath remove $ServiceName confirm 2>$null | Out-Null
        Start-Sleep -Seconds 2
    }

    & $NssmPath install $ServiceName "`"$AppPath`""
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao executar: $NssmPath install $ServiceName `"$AppPath`""
    }
    Start-Sleep -Seconds 2

    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppParameters",
        (Get-ConfigValue -Config $serviceConfig -Name "AppParameters" -Default "--mode=server --minimized --run-as-service")
    )
    Set-NssmValue -Arguments @("set", $ServiceName, "AppDirectory", $AppDirectory)
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppEnvironmentExtra",
        (Get-ConfigValue -Config $serviceConfig -Name "AppEnvironmentExtra" -Default "SERVICE_MODE=server")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "DisplayName",
        (Get-ConfigValue -Config $serviceConfig -Name "DisplayName" -Default "Backup Database Service")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "Description",
        (Get-ConfigValue -Config $serviceConfig -Name "Description" -Default "Servico de backup automatico para SQL Server, Sybase, PostgreSQL e Firebird")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "Start",
        (Get-ConfigValue -Config $serviceConfig -Name "Start" -Default "SERVICE_AUTO_START")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppStdout",
        (Get-ConfigValue -Config $serviceConfig -Name "AppStdout" -Default "C:\ProgramData\BackupDatabase\logs\service_stdout.log")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppStderr",
        (Get-ConfigValue -Config $serviceConfig -Name "AppStderr" -Default "C:\ProgramData\BackupDatabase\logs\service_stderr.log")
    )
    # S2 da auditoria: usa valores capturados quando presentes; cai para
    # defaults conhecidos quando o capture é antigo (schemaVersion < 3) ou
    # o cliente nunca customizou. Os defaults aqui DEVEM espelhar o
    # `_NssmConfigPlan` do Dart e o `install_service.ps1`.
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppExit",
        "Default",
        (Get-ConfigValue -Config $serviceConfig -Name "AppExitDefault" -Default "Restart")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppExit",
        "77",
        (Get-ConfigValue -Config $serviceConfig -Name "AppExit77" -Default "Exit")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppExit",
        "78",
        (Get-ConfigValue -Config $serviceConfig -Name "AppExit78" -Default "Exit")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppRestartDelay",
        (Get-ConfigValue -Config $serviceConfig -Name "AppRestartDelay" -Default "60000")
    )
    Set-NssmValue -Arguments @(
        "set",
        $ServiceName,
        "AppNoConsole",
        (Get-ConfigValue -Config $serviceConfig -Name "AppNoConsole" -Default "1")
    )

    $objectName = Get-ConfigValue -Config $serviceConfig -Name "ObjectName" -Default "LocalSystem"
    $normalizedAccount = $objectName.Trim().ToLowerInvariant()
    $supportedAccounts = @('localsystem', 'system', 'nt authority\system')
    if ($supportedAccounts -notcontains $normalizedAccount) {
        # Antes era `throw` — agora loga em arquivo dedicado para que o
        # operador descubra o problema no painel de updates da app
        # (audit 2026-05-28). exit 2 sinaliza "config incompativel".
        Write-RestoreError -Message ("Restauracao automatica do Windows Service so e " +
            "suportada para LocalSystem. Conta detectada: $objectName. " +
            "Reinstale o servico manualmente via 'Instalar como Servico do Windows'.")
        exit 2
    }
    Set-NssmValue -Arguments @("set", $ServiceName, "ObjectName", "LocalSystem")

    & $NssmPath start $ServiceName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao iniciar servico $ServiceName via NSSM (exit $LASTEXITCODE)"
    }

    $serviceUtilsPath = Join-Path $AppDirectory 'tools\service_utils.ps1'
    if (-not (Test-Path $serviceUtilsPath)) {
        Write-RestoreError -Message (
            "service_utils.ps1 ausente em $serviceUtilsPath; " +
            "servico iniciado mas RUNNING nao foi confirmado por polling."
        )
    } else {
        . $serviceUtilsPath
        $isRunning = Wait-ServiceRunning -ServiceName $ServiceName
        if (-not $isRunning) {
            Write-RestoreError -Message (
                "Servico $ServiceName restaurado mas nao atingiu RUNNING dentro de " +
                "$script:ServiceStartPollingTimeoutSeconds segundos apos NSSM start. " +
                "Exit 2: update_context.json preservado para retry."
            )
            exit 2
        }
    }
}

if ($origin -eq "ui") {
    $argumentList = @()
    if ($null -ne $context.relaunchArguments) {
        $argumentList = @($context.relaunchArguments | ForEach-Object { [string]$_ })
    }
    Start-Process -FilePath $AppPath -WorkingDirectory $AppDirectory -ArgumentList $argumentList | Out-Null
}

Remove-Item -Path $ContextPath -Force -ErrorAction SilentlyContinue
