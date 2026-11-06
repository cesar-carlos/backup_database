param([string]$Scenario)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\..\installer\rollback_core.ps1"
$root = Join-Path ([IO.Path]::GetTempPath()) ('rollback-test-' + [Guid]::NewGuid().ToString('N'))
$app = Join-Path $root 'app'
$machine = Join-Path $root 'machine'
function Check($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
try {
    foreach ($dir in @($app, "$machine\data", "$machine\config", "$machine\secrets")) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Set-Content "$app\backup_database.exe" 'old binary'
    Set-Content "$machine\data\db.sqlite" 'old database'
    Set-Content "$machine\config\settings.json" 'old config'
    Set-Content "$machine\secrets\key" 'old secret'
    Set-Content "$machine\migration_state.json" 'old migration state'
    if ($Scenario -like 'registration-*') {
        Set-Content "$root\service.reg" 'saved service configuration'
        $saved = @{ exists=$true; account='CONTOSO\backup'; image='"C:\old\nssm.exe"'; hash=(Get-RollbackHash "$root\service.reg") }
        $current = [pscustomobject]@{ StartName=$saved.account; PathName=$saved.image }
        switch ($Scenario) {
            'registration-winsw' { $current.PathName='"' + (Join-Path $app 'tools\BackupDatabaseService.exe') + '"' }
            'registration-account-changed' { $current.StartName='LocalSystem' }
            'registration-image-changed' { $current.PathName='"C:\foreign\service.exe"' }
            'registration-missing' { $current=$null }
            'registration-corrupt' { Set-Content "$root\service.reg" 'damaged snapshot' }
            'registration-foreign-new' { $saved.exists=$false }
            'registration-missing-account' { $saved.account=$null }
        }
        $failure=$Scenario -notin @('registration-nssm','registration-winsw')
        $errorMessage=$null
        try { Assert-RollbackServiceRegistration $saved $current $app $root } catch { $errorMessage=$_.Exception.Message }
        Check (($null -ne $errorMessage) -eq $failure) "Unexpected registration validation: $Scenario / $errorMessage"
        if ($failure) { Check ($errorMessage -match 'Service registration|Corrupt service snapshot|Foreign service registration') 'Failed outside registration guard' }
        return
    }
    if ($Scenario -eq 'absent-directory') { Remove-Item -LiteralPath "$machine\config" -Recurse -Force }
    $script:starts = 0
    $script:stops = 0
    $callbacks = @{
        AppDirectory = $app; MachineRoot = $machine;
        RestartService = ($Scenario -ne 'stopped');
        CaptureService = { param($directory) return @{ exists = $true; account = 'original' } };
        StopProcesses = { $script:stops++ };
        RestoreService = { param($saved, $directory)
            Check ($saved.account -eq 'original') 'Lost service configuration'
            if ($Scenario -eq 'service-failure') { throw 'Injected service restore failure' }
        };
        StartService = {
            if ($Scenario -eq 'start-failure') { throw 'Injected service start timeout' }
            Check ((Get-Content "$app\backup_database.exe") -eq 'old binary') 'Started mixed binaries'
            Check ((Get-Content "$machine\data\db.sqlite") -eq 'old database') 'Started migrated database'
            $script:starts++
        }
    }
    if ($Scenario -eq 'snapshot-failure') {
        function Copy-RollbackTree { throw 'Injected snapshot disk failure' }
        $failed = $false
        try { Invoke-RollbackTransaction -Action Prepare @callbacks } catch { $failed = $true }
        Check $failed 'Accepted incomplete snapshot'
        $failed = $false
        try { Invoke-RollbackTransaction -Action Arm @callbacks } catch { $failed = $true }
        Check $failed 'Armed incomplete snapshot'
        Check ((Get-Content "$app\backup_database.exe") -eq 'old binary') 'Modified original before snapshot'
        Check ($script:starts -eq 0) 'Started process during failed snapshot'
        return
    }
    Invoke-RollbackTransaction -Action Prepare @callbacks
    $journalPath = "$machine\staging\rollback\journal.json"
    Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'prepared') 'Snapshot missing'
    if ($Scenario -eq 'changed-before-arm') {
        Set-Content "$machine\data\db.sqlite" 'concurrent mutation'
        $failed = $false
        try { Invoke-RollbackTransaction -Action Arm @callbacks } catch { $failed = $true }
        Check $failed 'Armed stale snapshot'
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'prepared') 'Armed failed preparation'
        return
    }
    if ($Scenario -eq 'before-copy') {
        Invoke-RollbackTransaction -Action RecoverPending @callbacks
        Check ($script:starts -eq 0) 'Restarted unarmed transaction'
        return
    }
    Invoke-RollbackTransaction -Action Arm @callbacks
    Set-Content "$app\backup_database.exe" 'partial new binary'
    Set-Content "$app\new.dll" 'new dependency'
    Set-Content "$machine\data\db.sqlite" 'migrated database'
    New-Item -ItemType Directory -Path "$machine\config" -Force | Out-Null
    Set-Content "$machine\config\settings.json" 'new config'
    Set-Content "$machine\secrets\key" 'new secret'
    Set-Content "$machine\migration_state.json" 'new migration state'
    Set-Content "$machine\new_migration.done" 'new marker'
    if ($Scenario -eq 'service-preflight-failure') {
        $callbacks.ValidateService = { throw 'Injected account mismatch or corrupt service snapshot' }
        $stops = $script:stops
        $failed = $false
        try { Invoke-RollbackTransaction -Action Restore @callbacks } catch { $failed = $true }
        Check $failed 'Accepted invalid service snapshot'
        Check ($script:stops -eq $stops) 'Stopped service before ownership validation'
        Check ((Get-Content "$app\backup_database.exe") -eq 'partial new binary') 'Replaced app before service validation'
        Check ((Get-Content "$machine\data\db.sqlite") -eq 'migrated database') 'Replaced data before service validation'
        Check ((Get-Content "$machine\secrets\key") -eq 'new secret') 'Replaced credentials before service validation'
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'restore-failed') 'Lost retry journal'
        $callbacks.ValidateService = {}
    }
    if ($Scenario -eq 'interrupted-swap') {
        Move-Item -LiteralPath $app -Destination "$root\app.interrupted"
        $journal = Get-Content $journalPath -Raw | ConvertFrom-Json
        $journal.state = 'restoring'
        Write-RollbackJournal $journalPath $journal
    }
    if ($Scenario -eq 'committed') {
        Invoke-RollbackTransaction -Action Commit @callbacks
        Invoke-RollbackTransaction -Action RecoverPending @callbacks
        Check ((Get-Content "$app\backup_database.exe") -eq 'partial new binary') 'Rolled back committed transaction'
        return
    }
    if ($Scenario -eq 'corrupt') { Set-Content "$machine\staging\rollback\secrets\key" 'corrupt' }
    if ($Scenario -eq 'copy-failure') {
        $script:copyOriginal = ${function:Copy-RollbackTree}
        function Copy-RollbackTree { throw 'Injected disk/copy failure' }
    }
    if ($Scenario -in @('corrupt','copy-failure','service-failure','start-failure')) {
        $failed = $false
        try { Invoke-RollbackTransaction -Action Restore @callbacks } catch { $failed = $true }
        Check $failed 'Fault did not fail recovery'
        Check ($script:starts -eq 0) 'Started service after failed recovery'
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'restore-failed') 'No durable retry state'
        if ($Scenario -eq 'corrupt') {
            Check ((Get-Content "$app\backup_database.exe") -eq 'partial new binary') 'Mutated target before verifying all snapshots'
            return
        }
        if ($Scenario -eq 'copy-failure') { Set-Item Function:Copy-RollbackTree $script:copyOriginal }
        $Scenario = 'retry'
    }
    Invoke-RollbackTransaction -Action RecoverPending @callbacks
    Check ((Get-Content "$app\backup_database.exe") -eq 'old binary') 'Binary not restored'
    Check (-not (Test-Path "$app\new.dll")) 'New DLL survived rollback'
    if ($Scenario -eq 'absent-directory') {
        Check (-not (Test-Path "$machine\config")) 'New directory remained active'
    } else { Check ((Get-Content "$machine\config\settings.json") -eq 'old config') 'Config not restored' }
    Check ((Get-Content "$machine\secrets\key") -eq 'old secret') 'Secret not restored'
    Check ((Get-Content "$machine\migration_state.json") -eq 'old migration state') 'Migration state not restored'
    Check (-not (Test-Path "$machine\new_migration.done")) 'New migration marker remained active'
    Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'restored') 'Recovery not committed'
    Check ($script:starts -eq [int]$callbacks.RestartService) 'Wrong restart policy'
    $starts = $script:starts
    Invoke-RollbackTransaction -Action RecoverPending @callbacks
    Check ($script:starts -eq $starts) 'Repeated recovery restarted service'
    $quarantines = @(Get-ChildItem -LiteralPath $root -Directory -Filter 'app.failed-*')
    Check ($quarantines.Count -gt 0 -or $Scenario -eq 'interrupted-swap') 'Failed files were not preserved'
} finally {
    $resolved = [IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved).StartsWith('rollback-test-')) {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
