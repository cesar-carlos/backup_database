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
    if ($Scenario -in @('absent-directory', 'created-before-arm')) { Remove-Item -LiteralPath "$machine\config" -Recurse -Force }
    if ($Scenario -eq 'empty-removed-before-arm') { Remove-Item -LiteralPath "$machine\config\settings.json" }
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
    if ($Scenario -in @('missing-journal-arm', 'missing-journal-commit', 'unknown-transaction')) {
        if ($Scenario -eq 'unknown-transaction') {
            New-Item -ItemType Directory -Path "$machine\staging\rollback" -Force | Out-Null
            Set-Content "$machine\staging\rollback\unknown" 'preserve'
        }
        $action = switch ($Scenario) {
            'missing-journal-arm' { 'Arm' }
            'missing-journal-commit' { 'Commit' }
            default { 'RecoverPending' }
        }
        $message = $null
        try { Invoke-RollbackTransaction -Action $action @callbacks } catch { $message = $_.Exception.Message }
        Check ($message -match 'Missing rollback journal') "Unexpected guard result: $message"
        Check ($script:stops -eq 0) 'Stopped processes without transaction'
        return
    }
    if ($Scenario -in @('snapshot-failure', 'snapshot-retry')) {
        $script:copyOriginal = ${function:Copy-RollbackTree}
        function Copy-RollbackTree { throw 'Injected snapshot disk failure' }
        $failed = $false
        try { Invoke-RollbackTransaction -Action Prepare @callbacks } catch { $failed = $true }
        Check $failed 'Accepted incomplete snapshot'
        $failed = $false
        try { Invoke-RollbackTransaction -Action Arm @callbacks } catch { $failed = $true }
        Check $failed 'Armed incomplete snapshot'
        Check ((Get-Content "$app\backup_database.exe") -eq 'old binary') 'Modified original before snapshot'
        Check ($script:starts -eq 0) 'Started process during failed snapshot'
        if ($Scenario -eq 'snapshot-retry') {
            Set-Item Function:Copy-RollbackTree $script:copyOriginal
            Invoke-RollbackTransaction -Action RecoverPending @callbacks
            $callbacks.RestartService = $false
            Invoke-RollbackTransaction -Action Prepare @callbacks
            Invoke-RollbackTransaction -Action Arm @callbacks
            Set-Content "$app\backup_database.exe" 'partial update'
            Invoke-RollbackTransaction -Action Restore @callbacks
            Check ($script:starts -eq 1) 'Lost original service restart intent'
            Check ((Get-Content "$app\backup_database.exe") -eq 'old binary') 'Failed to recover after snapshot retry'
        }
        return
    }
    if ($Scenario -in @('fresh-install', 'missing-executable')) {
        if ($Scenario -eq 'fresh-install') {
            $null = Assert-RollbackPath $app
            Remove-Item -LiteralPath $app -Recurse -Force
        } else { Remove-Item -LiteralPath "$app\backup_database.exe" }
        $callbacks.RestartService = $false
        $callbacks.CaptureService = { return @{ exists = $false; account = 'original' } }
        Invoke-RollbackTransaction -Action Prepare @callbacks
        Invoke-RollbackTransaction -Action Arm @callbacks
        New-Item -ItemType Directory -Path $app -Force | Out-Null
        Set-Content "$app\backup_database.exe" 'partial installation'
        Set-Content "$machine\config\settings.json" 'partial config'
        Invoke-RollbackTransaction -Action Restore @callbacks
        Check (-not (Test-Path "$app\backup_database.exe")) 'Partial binary survived rollback'
        Check ((Get-Content "$machine\config\settings.json") -eq 'old config') 'Lost previous configuration'
        if ($Scenario -eq 'fresh-install') { Check (-not (Test-Path $app)) 'Created app directory survived rollback' }
        return
    }
    Invoke-RollbackTransaction -Action Prepare @callbacks
    $journalPath = "$machine\staging\rollback\journal.json"
    Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'prepared') 'Snapshot missing'
    if ($Scenario -eq 'commit-before-arm') {
        $failed = $false
        try { Invoke-RollbackTransaction -Action Commit @callbacks } catch { $failed = $true }
        Check $failed 'Committed unarmed snapshot'
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'prepared') 'Changed state on invalid commit'
        return
    }
    if ($Scenario -in @('changed-before-arm', 'created-before-arm', 'empty-removed-before-arm', 'duplicate-arm-group')) {
        switch ($Scenario) {
            'changed-before-arm' { Set-Content "$machine\data\db.sqlite" 'concurrent mutation' }
            'created-before-arm' { New-Item -ItemType Directory -Path "$machine\config" | Out-Null }
            'empty-removed-before-arm' { Remove-Item -LiteralPath "$machine\config" }
            'duplicate-arm-group' {
                $journal = Get-Content $journalPath -Raw | ConvertFrom-Json
                $journal.groups[3] = $journal.groups[0]
                Write-RollbackJournal $journalPath $journal
            }
        }
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
    if ($Scenario -in @('invalid-late-acl', 'metadata-directory-conflict')) {
        if ($Scenario -eq 'invalid-late-acl') {
            $journal = Get-Content $journalPath -Raw | ConvertFrom-Json
            $journal.groups[3].inventory[0].acl = 'invalid SDDL'
            Write-RollbackJournal $journalPath $journal
        } else {
            Move-Item -LiteralPath "$machine\migration_state.json" -Destination "$root\saved-marker"
            New-Item -ItemType Directory -Path "$machine\migration_state.json" | Out-Null
        }
        $failed = $false
        try { Invoke-RollbackTransaction -Action Restore @callbacks } catch { $failed = $true }
        Check $failed 'Accepted invalid restore metadata'
        Check ((Get-Content "$app\backup_database.exe") -eq 'partial new binary') 'Replaced app before validating metadata'
        Check ((Get-Content "$machine\data\db.sqlite") -eq 'migrated database') 'Replaced database before validating metadata'
        Check ($script:starts -eq 0) 'Started invalid recovery'
        return
    }
    if ($Scenario -in @('late-start-failure', 'final-journal-failure', 'checkpoint-failure')) {
        $script:journalOriginal = ${function:Write-RollbackJournal}
        function Write-RollbackJournal($Path, $Journal) {
            if (($Scenario -eq 'final-journal-failure' -and $Journal.state -eq 'restored') -or
                ($Scenario -eq 'checkpoint-failure' -and $Journal.state -eq 'restart-pending')) {
                throw 'Injected journal persistence failure'
            }
            & $script:journalOriginal $Path $Journal
        }
        $callbacks.StartService = {
            $script:starts++
            Set-Content "$machine\data\db.sqlite" 'new writes after recovery'
            if ($Scenario -eq 'late-start-failure') { throw 'Injected timeout after service began writing' }
        }
        $failed = $false
        try { Invoke-RollbackTransaction -Action Restore @callbacks } catch { $failed = $true }
        Check $failed 'Ignored persistence/start failure'
        $state = (Get-Content $journalPath -Raw | ConvertFrom-Json).state
        if ($Scenario -eq 'checkpoint-failure') {
            Check ($script:starts -eq 0) 'Started before durable checkpoint'
            Check ($state -eq 'restore-failed') 'Lost full recovery retry state'
        } else {
            Check ($state -eq 'restart-pending') 'Lost restart checkpoint'
            Check ((Get-Content "$machine\data\db.sqlite") -eq 'new writes after recovery') 'Lost live writes'
            $callbacks.StopProcesses = { throw 'Must not stop/re-copy a recovered installation' }
            $callbacks.RestoreService = { throw 'Must not restore service registration again' }
            $callbacks.StartService = {
                Check ((Get-Content "$machine\data\db.sqlite") -eq 'new writes after recovery') 'Retry overwrote live writes'
            }
        }
        Set-Item Function:Write-RollbackJournal $script:journalOriginal
        $Scenario = 'retry'
        Invoke-RollbackTransaction -Action RecoverPending @callbacks
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq 'restored') 'Retry did not finish recovery'
        return
    }
    if ($Scenario -in @('linked-snapshot', 'linked-destination', 'file-destination')) {
        $path = if ($Scenario -eq 'linked-snapshot') { "$machine\staging\rollback\config" } else { "$machine\config" }
        $null = Assert-RollbackPath $path
        Move-Item -LiteralPath $path -Destination "$root\preserved-config"
        if ($Scenario -eq 'file-destination') { Set-Content -LiteralPath $path 'unexpected file' }
        else { New-Item -ItemType Junction -Path $path -Target "$root\preserved-config" | Out-Null }
        try {
            $message = $null
            try { Invoke-RollbackTransaction -Action Restore @callbacks } catch { $message = $_.Exception.Message }
            Check ($message -match 'Reparse point|not a directory') "Unexpected failure: $message"
            Check ((Get-Content "$app\backup_database.exe") -eq 'partial new binary') 'Replaced app before validating all paths'
            Check ((Get-Content "$machine\data\db.sqlite") -eq 'migrated database') 'Replaced database before validating all paths'
            Check ($script:starts -eq 0) 'Started service after invalid path'
        } finally {
            # Delete only the junction itself, never its target.
            if ($Scenario -ne 'file-destination') { [IO.Directory]::Delete($path) }
        }
        return
    }
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
        $expectedState = if ($Scenario -eq 'start-failure') { 'restart-pending' } else { 'restore-failed' }
        Check ((Get-Content $journalPath -Raw | ConvertFrom-Json).state -eq $expectedState) 'No durable retry state'
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
