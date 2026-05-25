param(
    [string]$AppExePath = (Join-Path (Get-Location) "build\windows\x64\runner\Release\backup_database.exe"),
    [string]$NssmPath = (Join-Path (Get-Location) "installer\dependencies\nssm-2.24\win64\nssm.exe"),
    [string]$ServiceName = "BackupDatabaseSmokeService",
    [string]$TaskName = "\BackupDatabase\MachineStartupSmoke",
    [string]$ScheduleId = "00000000-0000-4000-8000-000000000001",
    [switch]$KeepArtifacts
)

$ErrorActionPreference = "Stop"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-Logged {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int[]]$AllowedExitCodes = @(0)
    )
    Write-Host ">> $FilePath $($Arguments -join ' ')"
    $process = Start-Process -FilePath $FilePath -ArgumentList $Arguments -NoNewWindow -PassThru -Wait
    if ($AllowedExitCodes -notcontains $process.ExitCode) {
        throw "Command failed with exit $($process.ExitCode): $FilePath $($Arguments -join ' ')"
    }
    return $process.ExitCode
}

function Test-IsWindows {
    return [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [System.Runtime.InteropServices.OSPlatform]::Windows
    )
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-SmokeService {
    param([string]$Name)
    & sc.exe stop $Name 2>$null | Out-Null
    Start-Sleep -Seconds 2
    & sc.exe delete $Name 2>$null | Out-Null
    Start-Sleep -Seconds 2
}

function Get-ServiceStateText {
    param([string]$Name)
    $output = & sc.exe query $Name 2>&1
    return ($output | Out-String)
}

function Assert-ServiceRunning {
    param([string]$Name)
    $state = Get-ServiceStateText -Name $Name
    Assert-True -Condition ($state -match "RUNNING|EM EXECU") -Message "Service $Name is not running. State: $state"
}

function Assert-ServiceNotRunning {
    param([string]$Name)
    $state = Get-ServiceStateText -Name $Name
    Assert-True -Condition ($state -notmatch "RUNNING|EM EXECU") -Message "Service $Name should not be running. State: $state"
}

function Wait-ProcessExit {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds,
        [string]$Label
    )
    $exited = $Process.WaitForExit($TimeoutSeconds * 1000)
    Assert-True -Condition $exited -Message "$Label did not exit within $TimeoutSeconds seconds"
    return $Process.ExitCode
}

function Stop-SmokeProcess {
    param([System.Diagnostics.Process]$Process)
    if ($null -ne $Process -and -not $Process.HasExited) {
        Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
        $Process.WaitForExit(10000) | Out-Null
    }
}

function Get-TaskSnapshot {
    param([string]$Name)
    $xml = & schtasks.exe /Query /TN $Name /XML 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    $path = Join-Path $env:TEMP ("backup_database_smoke_task_{0}.xml" -f ([guid]::NewGuid().ToString("N")))
    $xml | Set-Content -Path $path -Encoding UTF8
    return [pscustomobject]@{ Path = $path }
}

function Restore-TaskSnapshot {
    param(
        [string]$Name,
        [object]$Snapshot
    )
    & schtasks.exe /Delete /TN $Name /F 2>$null | Out-Null
    if ($null -ne $Snapshot -and (Test-Path $Snapshot.Path)) {
        Invoke-Logged -FilePath "schtasks.exe" -Arguments @("/Create", "/TN", $Name, "/XML", $Snapshot.Path, "/F") | Out-Null
        Remove-Item -Path $Snapshot.Path -Force -ErrorAction SilentlyContinue
    }
}

function Get-NssmValue {
    param(
        [string]$Name,
        [string[]]$Arguments
    )
    $output = & $NssmPath get $Name @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }
    return ($output | Out-String).Trim()
}

function Get-ServiceSnapshot {
    param([string]$Name)
    $service = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $service) {
        return $null
    }

    $application = Get-NssmValue -Name $Name -Arguments @("Application")
    Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($application)) `
        -Message "Existing service $Name is not an NSSM service; refusing to overwrite it."

    return [pscustomobject]@{
        Application = $application
        AppParameters = Get-NssmValue -Name $Name -Arguments @("AppParameters")
        AppDirectory = Get-NssmValue -Name $Name -Arguments @("AppDirectory")
        AppEnvironmentExtra = Get-NssmValue -Name $Name -Arguments @("AppEnvironmentExtra")
        DisplayName = Get-NssmValue -Name $Name -Arguments @("DisplayName")
        Description = Get-NssmValue -Name $Name -Arguments @("Description")
        Start = Get-NssmValue -Name $Name -Arguments @("Start")
        AppStdout = Get-NssmValue -Name $Name -Arguments @("AppStdout")
        AppStderr = Get-NssmValue -Name $Name -Arguments @("AppStderr")
        AppExitDefault = Get-NssmValue -Name $Name -Arguments @("AppExit", "Default")
        AppExit77 = Get-NssmValue -Name $Name -Arguments @("AppExit", "77")
        AppRestartDelay = Get-NssmValue -Name $Name -Arguments @("AppRestartDelay")
        AppNoConsole = Get-NssmValue -Name $Name -Arguments @("AppNoConsole")
        ObjectName = Get-NssmValue -Name $Name -Arguments @("ObjectName")
        WasRunning = ($service.Status -eq "Running")
    }
}

function Set-NssmIfValue {
    param(
        [string]$Name,
        [string]$Key,
        [string[]]$Values
    )
    if ($null -ne $Values -and $Values.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($Values[0])) {
        Invoke-Logged -FilePath $NssmPath -Arguments @("set", $Name, $Key) + $Values | Out-Null
    }
}

function Restore-ServiceSnapshot {
    param(
        [string]$Name,
        [object]$Snapshot
    )
    Remove-SmokeService -Name $Name
    if ($null -eq $Snapshot) {
        return
    }

    Invoke-Logged -FilePath $NssmPath -Arguments @("install", $Name, $Snapshot.Application) | Out-Null
    Set-NssmIfValue -Name $Name -Key "AppParameters" -Values @($Snapshot.AppParameters)
    Set-NssmIfValue -Name $Name -Key "AppDirectory" -Values @($Snapshot.AppDirectory)
    Set-NssmIfValue -Name $Name -Key "AppEnvironmentExtra" -Values @($Snapshot.AppEnvironmentExtra)
    Set-NssmIfValue -Name $Name -Key "DisplayName" -Values @($Snapshot.DisplayName)
    Set-NssmIfValue -Name $Name -Key "Description" -Values @($Snapshot.Description)
    Set-NssmIfValue -Name $Name -Key "Start" -Values @($Snapshot.Start)
    Set-NssmIfValue -Name $Name -Key "AppStdout" -Values @($Snapshot.AppStdout)
    Set-NssmIfValue -Name $Name -Key "AppStderr" -Values @($Snapshot.AppStderr)
    Set-NssmIfValue -Name $Name -Key "AppExit" -Values @("Default", $Snapshot.AppExitDefault)
    Set-NssmIfValue -Name $Name -Key "AppExit" -Values @("77", $Snapshot.AppExit77)
    Set-NssmIfValue -Name $Name -Key "AppRestartDelay" -Values @($Snapshot.AppRestartDelay)
    Set-NssmIfValue -Name $Name -Key "AppNoConsole" -Values @($Snapshot.AppNoConsole)
    Set-NssmIfValue -Name $Name -Key "ObjectName" -Values @($Snapshot.ObjectName)

    if ($Snapshot.WasRunning) {
        Invoke-Logged -FilePath $NssmPath -Arguments @("start", $Name) | Out-Null
    }
}

function Get-RunValueSnapshot {
    param(
        [string]$RegistryPath,
        [string]$Name
    )
    $item = Get-ItemProperty -Path $RegistryPath -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $item) {
        return [pscustomobject]@{ Path = $RegistryPath; Name = $Name; Existed = $false; Value = $null }
    }
    return [pscustomobject]@{ Path = $RegistryPath; Name = $Name; Existed = $true; Value = [string]$item.$Name }
}

function Restore-RunValueSnapshot {
    param([object]$Snapshot)
    if ($null -eq $Snapshot) {
        return
    }
    if ($Snapshot.Existed) {
        New-Item -Path $Snapshot.Path -Force | Out-Null
        Set-ItemProperty -Path $Snapshot.Path -Name $Snapshot.Name -Value $Snapshot.Value -Force
    } else {
        Remove-ItemProperty -Path $Snapshot.Path -Name $Snapshot.Name -ErrorAction SilentlyContinue
    }
}

function Remove-LegacyRunEntries {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    )
    $names = @("Backup Database", "BackupDatabase")
    foreach ($path in $paths) {
        foreach ($name in $names) {
            Remove-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
        }
    }
}

Assert-True -Condition (Test-IsWindows) -Message "This smoke test only runs on Windows."
Assert-True -Condition (Test-IsAdmin) -Message "Run this smoke test from an elevated PowerShell session."
Assert-True -Condition (Test-Path $AppExePath) -Message "App executable not found: $AppExePath"
Assert-True -Condition (Test-Path $NssmPath) -Message "NSSM not found: $NssmPath"

$appDir = Split-Path -Parent $AppExePath
$uiProcess = $null
$duplicateProcess = $null
$scheduleProcess = $null
$serviceSnapshot = $null
$taskSnapshot = $null
$runSnapshots = @()

try {
    Write-Host "Saving previous service, task, and legacy Run state"
    $serviceSnapshot = Get-ServiceSnapshot -Name $ServiceName
    $taskSnapshot = Get-TaskSnapshot -Name $TaskName
    $runSnapshots = @(
        Get-RunValueSnapshot -RegistryPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Backup Database"
        Get-RunValueSnapshot -RegistryPath "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BackupDatabase"
        Get-RunValueSnapshot -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Backup Database"
        Get-RunValueSnapshot -RegistryPath "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BackupDatabase"
    )

    Write-Host "Preparing smoke service $ServiceName"
    Remove-SmokeService -Name $ServiceName

    Invoke-Logged -FilePath $NssmPath -Arguments @("install", $ServiceName, $AppExePath) | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppParameters", "--mode=server --minimized --run-as-service") | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppDirectory", $appDir) | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppEnvironmentExtra", "SERVICE_MODE=server") | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppExit", "Default", "Restart") | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppExit", "77", "Exit") | Out-Null
    Invoke-Logged -FilePath $NssmPath -Arguments @("set", $ServiceName, "AppRestartDelay", "60000") | Out-Null

    $appExit77 = (& $NssmPath get $ServiceName AppExit 77 2>&1 | Out-String).Trim()
    Assert-True -Condition ($appExit77 -match "Exit") -Message "NSSM AppExit 77 is not Exit. Value: $appExit77"

    Write-Host "Scenario: UI owns lock, service exits without restart loop"
    $uiProcess = Start-Process -FilePath $AppExePath -ArgumentList @("--minimized") -WorkingDirectory $appDir -PassThru
    Start-Sleep -Seconds 6
    Assert-True -Condition (-not $uiProcess.HasExited) -Message "UI owner exited before service collision check."
    Invoke-Logged -FilePath "sc.exe" -Arguments @("start", $ServiceName) -AllowedExitCodes @(0, 1056) | Out-Null
    Start-Sleep -Seconds 8
    Assert-ServiceNotRunning -Name $ServiceName
    Stop-SmokeProcess -Process $uiProcess
    $uiProcess = $null

    Write-Host "Scenario: service owns lock, startup duplicate exits silently"
    Invoke-Logged -FilePath "sc.exe" -Arguments @("start", $ServiceName) -AllowedExitCodes @(0, 1056) | Out-Null
    Start-Sleep -Seconds 8
    Assert-ServiceRunning -Name $ServiceName
    $duplicateProcess = Start-Process -FilePath $AppExePath -ArgumentList @("--minimized", "--launch-origin=windows-startup") -WorkingDirectory $appDir -PassThru
    $duplicateExit = Wait-ProcessExit -Process $duplicateProcess -TimeoutSeconds 30 -Label "windows-startup duplicate"
    Assert-True -Condition ($duplicateExit -eq 0) -Message "Startup duplicate exit code should be 0, got $duplicateExit"

    Write-Host "Scenario: service owns lock, scheduled execution delegates and exits"
    $scheduleProcess = Start-Process -FilePath $AppExePath -ArgumentList @("--schedule-id=$ScheduleId") -WorkingDirectory $appDir -PassThru
    $scheduleExit = Wait-ProcessExit -Process $scheduleProcess -TimeoutSeconds 120 -Label "scheduled duplicate"
    Assert-True -Condition (@(0, 1, 2) -contains $scheduleExit) -Message "Unexpected scheduled duplicate exit code: $scheduleExit"

    Write-Host "Scenario: client startup scheduled task can be created"
    & schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
    $taskRun = "`"$AppExePath`" --minimized --launch-origin=windows-startup"
    Invoke-Logged -FilePath "schtasks.exe" -Arguments @("/Create", "/TN", $TaskName, "/SC", "ONLOGON", "/TR", $taskRun, "/F", "/RL", "LIMITED") | Out-Null
    $taskQuery = (& schtasks.exe /Query /TN $TaskName 2>&1 | Out-String)
    Assert-True -Condition ($taskQuery -match "MachineStartupSmoke") -Message "Smoke startup task was not created."

    Write-Host "Scenario: legacy Run entries are removed during simulated upgrade cleanup"
    New-Item -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
    New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Force | Out-Null
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Backup Database" -Value "`"$AppExePath`""
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BackupDatabase" -Value "`"$AppExePath`""
    Remove-LegacyRunEntries
    Assert-True -Condition ($null -eq (Get-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Backup Database" -ErrorAction SilentlyContinue)) `
        -Message "Legacy HKLM Run entry was not removed."
    Assert-True -Condition ($null -eq (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "BackupDatabase" -ErrorAction SilentlyContinue)) `
        -Message "Legacy HKCU Run entry was not removed."

    Write-Host "Windows single-instance smoke completed successfully."
}
finally {
    Stop-SmokeProcess -Process $uiProcess
    Stop-SmokeProcess -Process $duplicateProcess
    Stop-SmokeProcess -Process $scheduleProcess

    if (-not $KeepArtifacts) {
        Restore-TaskSnapshot -Name $TaskName -Snapshot $taskSnapshot
        Restore-ServiceSnapshot -Name $ServiceName -Snapshot $serviceSnapshot
        foreach ($snapshot in $runSnapshots) {
            Restore-RunValueSnapshot -Snapshot $snapshot
        }
    }
}
