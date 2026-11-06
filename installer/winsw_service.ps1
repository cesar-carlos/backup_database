param(
    [string]$AppPath,
    [string]$AppDirectory,
    [ValidatePattern('^[A-Za-z0-9_]+$')][string]$ServiceName = 'BackupDatabaseService',
    [string]$MachineRoot = "$env:ProgramData\BackupDatabase",
    [switch]$Migrate,
    [switch]$StartAfterInstall,
    [string]$ServiceUser,
    [SecureString]$ServicePassword
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\service_utils.ps1"
. "$PSScriptRoot\rollback_core.ps1"
. "$PSScriptRoot\service_scm.ps1"
. "$PSScriptRoot\winsw_config.ps1"
Import-Module (Join-Path $PSHOME 'Modules\CimCmdlets') -ErrorAction Stop

function Write-ServiceXml([string]$Path, [string]$Xml, [string]$Account) {
    $temp = "$Path.pending"
    [IO.File]::WriteAllText($temp, '', [Text.UTF8Encoding]::new($false))
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetSecurityDescriptorSddlForm('D:P(A;;FA;;;SY)(A;;FA;;;BA)')
    if ($Account -and $Account -notin @('LocalSystem','System','NT AUTHORITY\SYSTEM')) {
        $sid = (New-Object Security.Principal.NTAccount($Account)).Translate([Security.Principal.SecurityIdentifier])
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'ReadAndExecute','Allow')))
    }
    Set-Acl -LiteralPath $temp -AclObject $acl
    [IO.File]::WriteAllText($temp, $Xml, [Text.UTF8Encoding]::new($false))
    [xml]$checked = [IO.File]::ReadAllText($temp)
    if ($checked.service.id -ne $ServiceName) { throw 'Invalid WinSW service id' }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp,$Path,"$Path.previous") }
    else { [IO.File]::Move($temp,$Path) }
}

$created = $false
$journal = $null
$migrationCommitted = $false
try {
    $AppDirectory = Assert-RollbackPath $AppDirectory
    $wrapper = Join-Path $AppDirectory 'tools\BackupDatabaseService.exe'
    $xmlPath = [IO.Path]::ChangeExtension($wrapper, '.xml')
    $null = Assert-RollbackPath $wrapper
    $null = Assert-RollbackPath $xmlPath
    $svc = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
    $transaction = Assert-RollbackPath (Join-Path $MachineRoot 'staging\service-migration')
    New-Item -ItemType Directory -Path $transaction -Force | Out-Null
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetSecurityDescriptorSddlForm('D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)')
    Set-Acl -LiteralPath $transaction -AclObject $acl
    $journalPath = Join-Path $transaction 'journal.json'
    if (Test-Path -LiteralPath $journalPath) {
        $prior = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        if ($prior.schema -ne 1 -or $prior.app -ne $AppDirectory -or $prior.service -ne $ServiceName -or
            $prior.state -notin @('switching','restore-failed','complete','restored')) {
            throw 'Invalid or foreign service migration journal'
        }
        if ($prior.state -in @('switching','restore-failed')) {
            if ($prior.app -ne $AppDirectory -or $prior.service -ne $ServiceName -or -not $svc -or $svc.StartName -ne $prior.account) { throw 'Pending migration belongs to another service/account' }
            if ($svc.PathName -ne $prior.image -and $svc.PathName.Trim('"') -ne $wrapper) { throw 'Service image changed outside migration' }
            $journal = $prior
            throw 'Interrupted migration: restoring original wrapper; rerun installation afterwards'
        }
    }
    # Recovery must not depend on the incomplete/new binaries it will replace.
    if (-not (Test-Path -LiteralPath $AppPath -PathType Leaf)) { throw 'Application binary missing' }
    if ((Get-RollbackHash $wrapper) -ne '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA') { throw 'WinSW binary integrity check failed' }
    if ($svc) {
        if (-not $Migrate) { throw 'Service already exists; use application installer to upgrade' }
        if ($svc.PathName.Trim('"') -eq $wrapper) {
            [xml]$existingXml = Get-Content -LiteralPath $xmlPath -Raw
            if ($existingXml.service.id -ne $ServiceName) { throw 'Invalid existing WinSW configuration' }
            if ($StartAfterInstall) { Start-Service $ServiceName; if (-not (Wait-ServiceRunning $ServiceName)) { throw 'WinSW service did not reach RUNNING' } }
            exit 0
        }
        if ($svc.PathName -notmatch '(?i)(^|[\\/])nssm\.exe"?\s*$') { throw 'Unknown service wrapper; migration blocked' }
        $legacy = Read-NssmRegistrySettings $ServiceName
        $xml = ConvertTo-WinSWConfig -ServiceName $ServiceName -AppPath $AppPath -AppDirectory $AppDirectory -LogDirectory (Join-Path $MachineRoot 'logs') -Legacy $legacy
        $journal = [pscustomobject]@{ schema=1; state='switching'; app=$AppDirectory; service=$ServiceName;
            image=$svc.PathName; account=$svc.StartName; running=($svc.State -eq 'Running');
            recovery=[BackupServiceScm]::GetRecovery($ServiceName);
            oldXml=$(if (Test-Path -LiteralPath $xmlPath) { [IO.File]::ReadAllText($xmlPath) } else { $null }) }
        Write-RollbackJournal $journalPath $journal
        if ($svc.State -ne 'Stopped') { Stop-Service $ServiceName -ErrorAction Stop }
        if (-not (Wait-ServiceStopped $ServiceName)) { throw 'Service did not stop; wrapper unchanged' }
        $stopped = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
        if (-not $stopped -or $stopped.StartName -ne $journal.account -or $stopped.PathName -ne $journal.image) {
            throw 'Service registration changed while stopping; migration blocked'
        }
        Write-ServiceXml $xmlPath $xml $svc.StartName
        [BackupServiceScm]::SetImage($ServiceName, ('"' + $wrapper + '"'))
        # Preserve explicitly configured SCM recovery. Translate NSSM's default
        # restart only where the SCM previously had no recovery policy.
        if (@($journal.recovery.Types).Count -eq 0) {
            $delay = if ($legacy.ContainsKey('AppRestartDelay')) { [uint32]$legacy.AppRestartDelay } else { 60000 }
            $restart = -not ($legacy.AppExit -and $legacy.AppExit[''] -eq 'Exit')
            Set-ServiceRecoverySnapshot $ServiceName @{ Reset=86400; Types=@($(if ($restart) {1} else {0})); Delays=@($delay); NonCrash=$false }
        }
        if ($StartAfterInstall -or $journal.running) {
            Start-Service $ServiceName -ErrorAction Stop
            if (-not (Wait-ServiceRunning $ServiceName)) { throw 'Migrated service did not reach RUNNING' }
        }
        $journal.state = 'complete'; Write-RollbackJournal $journalPath $journal
        $migrationCommitted = $true
    } else {
        if ($ServiceUser -and ($null -eq $ServicePassword -or $ServicePassword.Length -eq 0)) { throw 'Service account password required' }
        $xml = ConvertTo-WinSWConfig -ServiceName $ServiceName -AppPath $AppPath -AppDirectory $AppDirectory -LogDirectory (Join-Path $MachineRoot 'logs')
        Write-ServiceXml $xmlPath $xml $(if ($ServiceUser) {$ServiceUser} else {'LocalSystem'})
        $parameters = @{ Name=$ServiceName; BinaryPathName=('"' + $wrapper + '"'); DisplayName='Backup Database Service'; StartupType='Automatic'; ErrorAction='Stop' }
        if ($ServiceUser) { $parameters.Credential = New-Object Management.Automation.PSCredential($ServiceUser,$ServicePassword) }
        New-Service @parameters | Out-Null
        $created = $true
        Set-ServiceRecoverySnapshot $ServiceName @{ Reset=86400; Types=@(1); Delays=@(60000); NonCrash=$false }
        if ($StartAfterInstall) { Start-Service $ServiceName; if (-not (Wait-ServiceRunning $ServiceName)) { throw 'New service did not reach RUNNING' } }
    }
    exit 0
} catch {
    $reason = $_.Exception.Message
    try {
        if ($journal -and -not $migrationCommitted) {
            $current = Get-CimInstance Win32_Service -Filter "Name='$ServiceName'"
            if (-not $current -or $current.StartName -ne $journal.account) { throw 'Cannot recover changed service registration' }
            if ($current.PathName -ne $journal.image -and $current.PathName.Trim('"') -ne $wrapper) { throw 'Cannot recover changed service image' }
            if ($current.State -ne 'Stopped') { Stop-Service $ServiceName -ErrorAction Stop }
            if (-not (Wait-ServiceStopped $ServiceName)) { throw 'Cannot stop service for recovery' }
            [BackupServiceScm]::SetImage($ServiceName,$journal.image)
            Set-ServiceRecoverySnapshot $ServiceName $journal.recovery
            if ($null -ne $journal.oldXml) { Write-ServiceXml $xmlPath $journal.oldXml $journal.account }
            if ($journal.running) { Start-Service $ServiceName; if (-not (Wait-ServiceRunning $ServiceName)) { throw 'Original service restart failed' } }
            $journal.state='restored'; Write-RollbackJournal $journalPath $journal
        } elseif ($created) {
            Stop-Service $ServiceName -ErrorAction SilentlyContinue
            if (Wait-ServiceStopped $ServiceName) { & sc.exe delete $ServiceName | Out-Null }
        }
    } catch {
        if ($journal) { $journal.state='restore-failed'; Write-RollbackJournal $journalPath $journal }
        $reason += '; recovery failed: ' + $_.Exception.Message
    }
    Write-Error $reason -ErrorAction Continue
    exit 1
}
