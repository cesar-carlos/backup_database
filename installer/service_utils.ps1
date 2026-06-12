# Shared Windows service helpers for installer PowerShell scripts.
# Timing mirrors WindowsServiceTimingConfig.defaultConfig in Dart.

$script:ServiceStartPollingInitialDelaySeconds = 3
$script:ServiceStartPollingIntervalSeconds = 1
$script:ServiceStartPollingTimeoutSeconds = 30

function Test-ServiceScQueryRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScQueryOutput
    )

    $upper = $ScQueryOutput.ToUpperInvariant()
    if ($upper.Contains('RUNNING')) {
        return $true
    }
    if ($upper.Contains('EM EXECUÇÃO') -or $upper.Contains('EM EXECUCAO')) {
        return $true
    }
    if ($ScQueryOutput -match '(?:STATE|ESTADO)\s*:\s*4\b') {
        return $true
    }
    return $false
}

function Test-ServiceScQueryStopped {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScQueryOutput
    )

    $upper = $ScQueryOutput.ToUpperInvariant()
    if ($upper.Contains('STOPPED')) {
        return $true
    }
    if ($upper.Contains('PARADO')) {
        return $true
    }
    if ($ScQueryOutput -match '(?:STATE|ESTADO)\s*:\s*1\b') {
        return $true
    }
    return $false
}

function Get-ServiceScQueryStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName
    )

    $output = (sc.exe query $ServiceName 2>&1 | Out-String).TrimEnd()
    $exitCode = $LASTEXITCODE
    $stateName = 'unknown'

    if ($output -match '(?:STATE|ESTADO)\s*:\s*\d+\s+(\S+)') {
        $stateName = $Matches[1]
    }

    $isRunning = ($exitCode -eq 0) -and (Test-ServiceScQueryRunning -ScQueryOutput $output)
    $isStopped = ($exitCode -eq 0) -and (Test-ServiceScQueryStopped -ScQueryOutput $output)

    return [PSCustomObject]@{
        ExitCode = $exitCode
        IsRunning = $isRunning
        IsStopped = $isStopped
        StateName = $stateName
        RawOutput = $output
    }
}

function Wait-ServiceRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [int]$TimeoutSeconds = $script:ServiceStartPollingTimeoutSeconds,
        [int]$IntervalSeconds = $script:ServiceStartPollingIntervalSeconds,
        [int]$InitialDelaySeconds = $script:ServiceStartPollingInitialDelaySeconds
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $pollCount = 0
    $lastStatus = $null

    if ($InitialDelaySeconds -gt 0) {
        Start-Sleep -Seconds $InitialDelaySeconds
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $IntervalSeconds
        $pollCount++
        $lastStatus = Get-ServiceScQueryStatus -ServiceName $ServiceName

        Write-Host (
            "Wait-ServiceRunning: poll=$pollCount " +
            "running=$($lastStatus.IsRunning) state=$($lastStatus.StateName)"
        )

        if ($lastStatus.IsRunning) {
            Write-Host (
                "Wait-ServiceRunning: converged in $($stopwatch.ElapsedMilliseconds)ms"
            )
            return $true
        }
    }

    $lastState = if ($null -ne $lastStatus) { $lastStatus.StateName } else { 'unknown' }
    $message = (
        "Timeout ao aguardar RUNNING para '$ServiceName' apos " +
        "$($stopwatch.ElapsedMilliseconds)ms. Ultimo estado: $lastState"
    )
    Write-Warning $message
    if ($null -ne $lastStatus -and -not [string]::IsNullOrWhiteSpace($lastStatus.RawOutput)) {
        Write-Warning $lastStatus.RawOutput
    }
    return $false
}

function Start-WindowsServiceWithPolling {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [int]$TimeoutSeconds = $script:ServiceStartPollingTimeoutSeconds,
        [int]$IntervalSeconds = $script:ServiceStartPollingIntervalSeconds,
        [int]$InitialDelaySeconds = $script:ServiceStartPollingInitialDelaySeconds
    )

    $startOutput = (sc.exe start $ServiceName 2>&1 | Out-String).TrimEnd()
    $startExitCode = $LASTEXITCODE

    if ($startExitCode -eq 0) {
        Write-Host "sc start $ServiceName concluido (exit 0)"
    } elseif ($startExitCode -eq 1056) {
        Write-Host "Servico '$ServiceName' ja estava em execucao (exit 1056)"
    } else {
        Write-Warning (
            "sc start $ServiceName falhou (exit $startExitCode): $startOutput"
        )
        return $false
    }

    return Wait-ServiceRunning `
        -ServiceName $ServiceName `
        -TimeoutSeconds $TimeoutSeconds `
        -IntervalSeconds $IntervalSeconds `
        -InitialDelaySeconds $InitialDelaySeconds
}

function Wait-ServiceStopped {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ServiceName,
        [int]$TimeoutSeconds = $script:ServiceStartPollingTimeoutSeconds,
        [int]$IntervalSeconds = $script:ServiceStartPollingIntervalSeconds,
        [int]$InitialDelaySeconds = $script:ServiceStartPollingInitialDelaySeconds
    )

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $pollCount = 0
    $lastStatus = $null

    if ($InitialDelaySeconds -gt 0) {
        Start-Sleep -Seconds $InitialDelaySeconds
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $IntervalSeconds
        $pollCount++
        $lastStatus = Get-ServiceScQueryStatus -ServiceName $ServiceName

        Write-Host (
            "Wait-ServiceStopped: poll=$pollCount " +
            "stopped=$($lastStatus.IsStopped) state=$($lastStatus.StateName)"
        )

        if ($lastStatus.IsStopped) {
            Write-Host (
                "Wait-ServiceStopped: converged in $($stopwatch.ElapsedMilliseconds)ms"
            )
            return $true
        }
    }

    $lastState = if ($null -ne $lastStatus) { $lastStatus.StateName } else { 'unknown' }
    $message = (
        "Timeout ao aguardar STOPPED para '$ServiceName' apos " +
        "$($stopwatch.ElapsedMilliseconds)ms. Ultimo estado: $lastState"
    )
    Write-Warning $message
    if ($null -ne $lastStatus -and -not [string]::IsNullOrWhiteSpace($lastStatus.RawOutput)) {
        Write-Warning $lastStatus.RawOutput
    }
    return $false
}
