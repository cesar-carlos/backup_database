# Restaura o estado operacional apos update silencioso.

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

    Set-NssmValue -Arguments @("install", $ServiceName, $AppPath)
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
    Set-NssmValue -Arguments @("set", $ServiceName, "AppExit", "Default", "Restart")
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
    if ($objectName -ne "LocalSystem" -and $objectName -ne "NT AUTHORITY\\SYSTEM" -and $objectName -ne "System") {
        throw "Restauracao automatica do Windows Service so e suportada para LocalSystem. Conta detectada: $objectName"
    }
    Set-NssmValue -Arguments @("set", $ServiceName, "ObjectName", "LocalSystem")

    & $NssmPath start $ServiceName | Out-Null
}

if ($origin -eq "ui") {
    $argumentList = @()
    if ($null -ne $context.relaunchArguments) {
        $argumentList = @($context.relaunchArguments | ForEach-Object { [string]$_ })
    }
    Start-Process -FilePath $AppPath -WorkingDirectory $AppDirectory -ArgumentList $argumentList | Out-Null
}

Remove-Item -Path $ContextPath -Force -ErrorAction SilentlyContinue
