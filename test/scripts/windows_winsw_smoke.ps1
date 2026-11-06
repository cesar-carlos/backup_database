# Run only on an isolated, configured Windows VM as Administrator.
param([Parameter(Mandatory=$true)][string]$AppExePath)
$ErrorActionPreference='Stop'
$repo=Resolve-Path "$PSScriptRoot\..\.."
$app=(Resolve-Path -LiteralPath $AppExePath).Path
$appDir=Split-Path -Parent $app
$service='BackupDatabaseWinSWSmoke'
if (Get-Service $service -ErrorAction SilentlyContinue) { throw 'Smoke service already exists; refusing to replace it' }
if (Get-Process backup_database -ErrorAction SilentlyContinue) { throw 'Close application processes before smoke testing' }
$toolsDir=Join-Path $appDir 'tools'
New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
foreach ($name in @('winsw_service.ps1','winsw_config.ps1','service_scm.ps1','rollback_core.ps1','service_utils.ps1','install_service.ps1')) {
    Copy-Item -LiteralPath "$repo\installer\$name" -Destination $toolsDir -Force
}
Copy-Item -LiteralPath "$repo\installer\dependencies\winsw-2.12.0\BackupDatabaseService.exe" -Destination $toolsDir -Force
. "$toolsDir\service_utils.ps1"
try {
    & "$toolsDir\winsw_service.ps1" -AppPath $app -AppDirectory $appDir -ServiceName $service -StartAfterInstall
    if ($LASTEXITCODE -ne 0) { throw 'WinSW installation/start failed' }
    Start-Sleep -Seconds 10
    if ((Get-Service $service).Status -ne 'Running') { throw 'Service exited during bootstrap' }
    $bootstrapLog=Join-Path $env:ProgramData 'BackupDatabase\logs\service_bootstrap.log'
    $beforeStop=if (Test-Path -LiteralPath $bootstrapLog) { [IO.File]::ReadAllText($bootstrapLog) } else { '' }
    Stop-Service $service -ErrorAction Stop
    if (-not (Wait-ServiceStopped $service)) { throw 'WinSW stop failed' }
    $afterStop=[IO.File]::ReadAllText($bootstrapLog)
    $newLog=if ($afterStop.StartsWith($beforeStop)) { $afterStop.Substring($beforeStop.Length) } else { $afterStop }
    if ($newLog -notmatch 'initialize: lock released, exiting') { throw 'Service stopped without confirming graceful cleanup' }
    Start-Service $service -ErrorAction Stop
    if (-not (Wait-ServiceRunning $service)) { throw 'WinSW restart failed' }
} finally {
    if (Get-Service $service -ErrorAction SilentlyContinue) {
        Stop-Service $service -ErrorAction Stop
        if (-not (Wait-ServiceStopped $service)) { throw 'Cannot safely remove smoke service' }
        & sc.exe delete $service | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Wait-ServiceRemoved $service)) { throw 'Smoke service removal failed' }
    }
}
