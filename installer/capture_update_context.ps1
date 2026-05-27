# Captura o contexto de update e enriquece com o estado atual do Windows Service.

param(
    [Parameter(Mandatory = $true)]
    [string]$ContextPath,
    [string]$ServiceName = "BackupDatabaseService"
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "encoding_utils.ps1")

function Get-StringValue([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }
    return $Value.Trim()
}

function Get-ServiceRegistryImagePath([string]$Name) {
    try {
        $serviceKey = "HKLM:\SYSTEM\CurrentControlSet\Services\$Name"
        return (Get-ItemProperty -Path $serviceKey -ErrorAction Stop).ImagePath
    } catch {
        return $null
    }
}

function Resolve-ExecutableFromImagePath([string]$ImagePath) {
    if ([string]::IsNullOrWhiteSpace($ImagePath)) {
        return $null
    }

    $trimmed = $ImagePath.Trim()
    if ($trimmed.StartsWith('"')) {
        $parts = $trimmed.Split('"')
        if ($parts.Length -ge 2) {
            return Get-StringValue -Value $parts[1]
        }
    }

    $exeMatch = [regex]::Match($trimmed, '^[^"]+?\.exe', 'IgnoreCase')
    if ($exeMatch.Success) {
        return Get-StringValue -Value $exeMatch.Value
    }

    $token = ($trimmed -split "\s+")[0]
    return Get-StringValue -Value $token
}

function Get-NssmValue(
    [string]$NssmPath,
    [string]$Name,
    [string[]]$Arguments
) {
    if ([string]::IsNullOrWhiteSpace($NssmPath) -or -not (Test-Path $NssmPath)) {
        return $null
    }

    $result = & $NssmPath get $Name @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return Get-StringValue -Value (($result | Out-String).Trim())
}

# S2 da auditoria: captura valores de AppExit (Default/77/78) que estavam
# faltando na implementação original. Sem essa captura, customizações do
# cliente (ex.: mudar AppRestartDelay) eram perdidas no restore — e se o
# update introduzir uma nova chave (AppExit 79, p.ex.), não há como
# detectar regressão entre captura e restore.
function Get-NssmAppExitValue(
    [string]$NssmPath,
    [string]$Name,
    [string]$ExitCode
) {
    return Get-NssmValue -NssmPath $NssmPath -Name $Name -Arguments @("AppExit", $ExitCode)
}

if (-not (Test-Path $ContextPath)) {
    exit 0
}

$context = Read-Utf8NoBomFile -Path $ContextPath | ConvertFrom-Json
$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
$serviceExists = $null -ne $service

$serviceConfig = $null
if ($serviceExists) {
    $imagePath = Get-ServiceRegistryImagePath -Name $ServiceName
    $nssmPath = Resolve-ExecutableFromImagePath -ImagePath $imagePath
    $serviceConfig = [ordered]@{
        NssmPath            = $nssmPath
        Application         = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("Application")
        AppParameters       = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppParameters")
        AppDirectory        = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppDirectory")
        AppEnvironmentExtra = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppEnvironmentExtra")
        ObjectName          = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("ObjectName")
        DisplayName         = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("DisplayName")
        Description         = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("Description")
        Start               = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("Start")
        AppStdout           = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppStdout")
        AppStderr           = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppStderr")
        AppRestartDelay     = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppRestartDelay")
        AppNoConsole        = Get-NssmValue -NssmPath $nssmPath -Name $ServiceName -Arguments @("AppNoConsole")
        AppExitDefault      = Get-NssmAppExitValue -NssmPath $nssmPath -Name $ServiceName -ExitCode "Default"
        AppExit77           = Get-NssmAppExitValue -NssmPath $nssmPath -Name $ServiceName -ExitCode "77"
        AppExit78           = Get-NssmAppExitValue -NssmPath $nssmPath -Name $ServiceName -ExitCode "78"
    }
}

$updated = [ordered]@{
    schemaVersion     = if ($null -ne $context.schemaVersion) { [int]$context.schemaVersion } else { 2 }
    contextId         = $context.contextId
    origin            = $context.origin
    appMode           = $context.appMode
    currentVersion    = $context.currentVersion
    targetVersion     = $context.targetVersion
    relaunchArguments = @($context.relaunchArguments)
    executablePath    = $context.executablePath
    createdAt         = $context.createdAt
    expiresAt         = $context.expiresAt
    serviceName       = $ServiceName
    serviceExists     = $serviceExists
    serviceConfig     = $serviceConfig
    capturedAt        = (Get-Date).ToUniversalTime().ToString("o")
}

$json = $updated | ConvertTo-Json -Depth 8
Write-Utf8NoBomFile -Path $ContextPath -Value $json
