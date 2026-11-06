param(
    [ValidateSet('Prepare','Arm','Commit','Restore','RecoverPending','StartExisting')][string]$Action,
    [Parameter(Mandatory=$true)][string]$AppDirectory,
    [string]$MachineRoot = "$env:ProgramData\BackupDatabase",
    [switch]$RestartService
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\rollback_core.ps1"
. "$PSScriptRoot\service_utils.ps1"
. "$PSScriptRoot\service_scm.ps1"
Import-Module (Join-Path $PSHOME 'Modules\CimCmdlets') -ErrorAction Stop
$serviceName = 'BackupDatabaseService'
$serviceKey = "HKLM\SYSTEM\CurrentControlSet\Services\$serviceName"
$validateService = {
    param($saved, $directory)
    $current = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
    Assert-RollbackServiceRegistration $saved $current $AppDirectory $directory
}
try {
    if ($Action -eq 'StartExisting') {
        Start-Service -Name $serviceName -ErrorAction Stop
        if (-not (Wait-ServiceRunning -ServiceName $serviceName)) { throw 'Service did not reach RUNNING' }
        exit 0
    }
    $pendingPath = Join-Path $MachineRoot 'staging\rollback\journal.json'
    $pending = $false
    if (Test-Path -LiteralPath $pendingPath) {
        $state = (Get-Content -LiteralPath $pendingPath -Raw | ConvertFrom-Json).state
        $pending = $state -in @('installing','restoring','restore-failed')
    }
    Invoke-RollbackTransaction -Action $Action -AppDirectory $AppDirectory -MachineRoot $MachineRoot -RestartService $RestartService.IsPresent -ProtectSnapshot {
        param($path)
        $acl = [Security.AccessControl.DirectorySecurity]::new()
        $acl.SetSecurityDescriptorSddlForm('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
        Set-Acl -LiteralPath $path -AclObject $acl
    } -StopProcesses {
        $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($svc) {
            if ($svc.Status -ne 'Stopped') { Stop-Service -Name $serviceName -ErrorAction Stop }
            if (-not (Wait-ServiceStopped -ServiceName $serviceName)) { throw 'Service did not stop' }
        }
        $exe = Join-Path $AppDirectory 'backup_database.exe'
        foreach ($process in Get-CimInstance Win32_Process -Filter "Name='backup_database.exe'") {
            if (-not $process.ExecutablePath) { throw 'Cannot establish application process ownership' }
            if ($process.ExecutablePath -eq $exe) {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
                Wait-Process -Id $process.ProcessId -Timeout 30 -ErrorAction SilentlyContinue
                if (Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue) { throw 'Application did not stop' }
            }
        }
    } -CaptureService {
        param($directory)
        $svc = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
        if (-not $svc) { return @{ exists = $false } }
        $file = Join-Path $directory 'service.reg'
        & reg.exe export $serviceKey $file /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot snapshot service registry' }
        $delayed = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName" -Name DelayedAutoStart -ErrorAction SilentlyContinue).DelayedAutoStart
        return @{ exists = $true; hash = (Get-RollbackHash $file);
            account = $svc.StartName; image = $svc.PathName; start = $svc.StartMode; delayed = ($delayed -eq 1);
            recovery = [BackupServiceScm]::GetRecovery($serviceName) }
    } -ValidateService $validateService -RestoreService {
        param($saved, $directory)
        & $validateService $saved $directory
        $current = Get-CimInstance Win32_Service -Filter "Name='$serviceName'"
        if (-not $saved.exists) {
            if ($current) {
                & sc.exe delete $serviceName | Out-Null
                if ($LASTEXITCODE -ne 0 -or -not (Wait-ServiceRemoved -ServiceName $serviceName)) { throw 'Cannot remove newly installed service' }
            }
            return
        }
        $winSwImage = '"' + (Join-Path $AppDirectory 'tools\BackupDatabaseService.exe') + '"'
        if (-not $current -or $current.StartName -ne $saved.account -or
            ($current.PathName -ne $saved.image -and $current.PathName -ne $winSwImage)) {
            throw 'Service registration/account/image changed; manual recovery required'
        }
        $file = Join-Path $directory 'service.reg'
        if ((Get-RollbackHash $file) -ne $saved.hash) { throw 'Corrupt service snapshot' }
        [BackupServiceScm]::SetImage($serviceName, $saved.image)
        if ($null -ne $saved.recovery) { Set-ServiceRecoverySnapshot $serviceName $saved.recovery }
        # NSSM may have added values that reg import alone would leave behind.
        $parameters = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName\Parameters"
        if (Test-Path -LiteralPath $parameters) { Remove-Item -LiteralPath $parameters -Recurse -Force }
        & reg.exe import $file | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot restore service registry' }
        $mode = @{ Auto = 'auto'; Manual = 'demand'; Disabled = 'disabled' }[$saved.start]
        if ($saved.start -eq 'Auto' -and $saved.delayed) { $mode = 'delayed-auto' }
        if (-not $mode) { throw 'Unsupported service start mode' }
        & sc.exe config $serviceName start= $mode | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Cannot restore SCM configuration' }
        $migrationPath = Join-Path $MachineRoot 'staging\service-migration\journal.json'
        if (Test-Path -LiteralPath $migrationPath) {
            $migration = Get-Content -LiteralPath $migrationPath -Raw | ConvertFrom-Json
            if ($migration.app -eq $AppDirectory -and $migration.service -eq $serviceName) {
                $migration.state = 'restored'
                Write-RollbackJournal $migrationPath $migration
            }
        }
    } -StartService {
        Start-Service -Name $serviceName -ErrorAction Stop
        if (-not (Wait-ServiceRunning -ServiceName $serviceName)) { throw 'Restored service did not reach RUNNING' }
    }
    if ($Action -eq 'RecoverPending' -and $pending) { exit 10 }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message -ErrorAction Continue
    exit 1
}
