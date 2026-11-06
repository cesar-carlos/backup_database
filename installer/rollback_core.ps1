# Filesystem transaction. Windows service operations are injected by the entry
# point; tests use isolated directories and fake service callbacks.
$ErrorActionPreference = 'Stop'
# A launcher running in PowerShell 7 can pass its module path to Windows
# PowerShell 5. Load the matching built-in ACL module explicitly.
Import-Module (Join-Path $PSHOME 'Modules\Microsoft.PowerShell.Security') -ErrorAction Stop

function Get-RollbackHash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
    finally { $stream.Dispose(); $sha.Dispose() }
}

function Assert-RollbackServiceRegistration($Saved, $Current, [string]$AppDirectory, [string]$SnapshotDirectory) {
    $winSwImage = '"' + (Join-Path $AppDirectory 'tools\BackupDatabaseService.exe') + '"'
    if ($Saved.exists) {
        if (-not $Current -or [string]::IsNullOrWhiteSpace([string]$Saved.account) -or
            $Current.StartName -ne $Saved.account -or
            ($Current.PathName -ne $Saved.image -and $Current.PathName -ne $winSwImage)) {
            throw 'Service registration/account/image changed; manual recovery required'
        }
        if ((Get-RollbackHash (Join-Path $SnapshotDirectory 'service.reg')) -ne $Saved.hash) { throw 'Corrupt service snapshot' }
    } elseif ($Current -and $Current.PathName -ne $winSwImage) {
        throw 'Foreign service registration; recovery blocked'
    }
}

function Assert-RollbackPath([string]$Path) {
    if (-not [IO.Path]::IsPathRooted($Path)) { throw "Relative rollback path: $Path" }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) { throw 'Drive root is not an installation' }
    $cursor = $full
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw "Reparse point is not allowed: $cursor"
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    return $full
}

function Get-RollbackInventory([string]$Root) {
    $result = @()
    if (-not (Test-Path -LiteralPath $Root)) { return $result }
    # Walk one level at a time so no junction is traversed before validation.
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($Root)
    while ($pending.Count -gt 0) {
        foreach ($item in Get-ChildItem -LiteralPath $pending.Pop() -Force) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked artifact: $($item.FullName)" }
            $relative = $item.FullName.Substring($Root.Length).TrimStart('\')
            if ($item.PSIsContainer) {
                $result += [pscustomobject]@{ path = $relative; directory = $true; hash = ''; acl = (Get-Acl -LiteralPath $item.FullName).Sddl }
                $pending.Push($item.FullName)
            } else {
                $result += [pscustomobject]@{ path = $relative; directory = $false;
                    hash = (Get-RollbackHash $item.FullName); acl = (Get-Acl -LiteralPath $item.FullName).Sddl }
            }
        }
    }
    return $result
}

function Assert-RollbackInventory([string]$Root, $Expected) {
    $actual = @(Get-RollbackInventory $Root)
    if ($actual.Count -ne @($Expected).Count) { throw "Inventory count mismatch: $Root" }
    $lookup = @{}
    foreach ($item in $actual) { $lookup[$item.path] = $item }
    foreach ($item in @($Expected)) {
        $found = $lookup[$item.path]
        if ($null -eq $found -or $found.directory -ne $item.directory -or $found.hash -ne $item.hash) {
            throw "Snapshot integrity mismatch: $Root / $($item.path)"
        }
    }
}

function Copy-RollbackTree([string]$Source, [string]$Destination, $Inventory) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($item in @($Inventory)) {
        $target = [IO.Path]::GetFullPath((Join-Path $Destination $item.path))
        if (-not $target.StartsWith($Destination + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid manifest path' }
        if ($item.directory) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
            Copy-Item -LiteralPath (Join-Path $Source $item.path) -Destination $target -Force
        }
    }
    Assert-RollbackInventory $Destination $Inventory
}

function Get-RollbackRootFiles([string]$Root) {
    foreach ($item in Get-ChildItem -LiteralPath $Root -Force -File) {
        $null = Assert-RollbackPath $item.FullName
        [pscustomobject]@{ path = $item.Name; directory = $false;
            hash = (Get-RollbackHash $item.FullName); acl = (Get-Acl -LiteralPath $item.FullName).Sddl }
    }
}

function Write-RollbackJournal([string]$Path, $Journal) {
    $temp = "$Path.tmp"
    $json = $Journal | ConvertTo-Json -Depth 16
    [IO.File]::WriteAllText($temp, $json, [Text.UTF8Encoding]::new($false))
    # Flush the journal before any directory replacement / service start.
    $stream = [IO.File]::Open($temp, 'Open', 'ReadWrite', 'None')
    try { $stream.Flush($true) } finally { $stream.Dispose() }
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($temp, $Path, "$Path.previous") }
    else { [IO.File]::Move($temp, $Path) }
}

function Invoke-RollbackTransaction {
    param([string]$Action, [string]$AppDirectory, [string]$MachineRoot,
        [bool]$RestartService = $false,
        [scriptblock]$CaptureService, [scriptblock]$StopProcesses,
        [scriptblock]$RestoreService, [scriptblock]$StartService,
        [scriptblock]$ProtectSnapshot = {},
        [scriptblock]$ValidateService = {})
    $app = Assert-RollbackPath $AppDirectory
    $machine = Assert-RollbackPath $MachineRoot
    if ($app.StartsWith($machine + '\', 'OrdinalIgnoreCase') -or
        $machine.StartsWith($app + '\', 'OrdinalIgnoreCase') -or $app -eq $machine) { throw 'Overlapping rollback roots' }
    $transaction = Assert-RollbackPath (Join-Path $machine 'staging\rollback')
    $journalPath = Join-Path $transaction 'journal.json'
    $targets = [ordered]@{ app = $app; data = (Join-Path $machine 'data');
        config = (Join-Path $machine 'config'); secrets = (Join-Path $machine 'secrets') }
    $journal = $null
    if (Test-Path -LiteralPath $journalPath) {
        $journal = Get-Content -LiteralPath $journalPath -Raw | ConvertFrom-Json
        if ($journal.schema -ne 1 -or $journal.app -ne $app -or $journal.machine -ne $machine) { throw 'Rollback journal belongs to another installation' }
        if ($journal.id -notmatch '^[a-fA-F0-9]{32}$') { throw 'Invalid rollback transaction ID' }
    }
    if ($Action -eq 'Prepare') {
        if ($journal -and $journal.state -notin @('committed', 'restored', 'prepared')) { throw 'Pending rollback must be recovered before install' }
        if (-not (Test-Path -LiteralPath (Join-Path $app 'backup_database.exe'))) { return }
        if (Test-Path -LiteralPath $transaction) {
            # Never recursively delete an unknown or incomplete transaction.
            if (-not $journal) { throw 'Incomplete snapshot; inspect rollback directory before retrying' }
            $null = Get-RollbackInventory $transaction
            $checked = Assert-RollbackPath $transaction
            if ($checked -ne (Join-Path $machine 'staging\rollback')) { throw 'Unexpected snapshot target' }
            Remove-Item -LiteralPath $checked -Recurse -Force
        }
        New-Item -ItemType Directory -Path $transaction -Force | Out-Null
        & $ProtectSnapshot $transaction
        $journal = [pscustomobject]@{ schema = 1; app = $app; machine = $machine;
            id = [Guid]::NewGuid().ToString('N'); state = 'preparing'; restart = $RestartService;
            groups = @(); rootFiles = @(); service = $null; error = $null }
        Write-RollbackJournal $journalPath $journal
        & $StopProcesses
        $journal.service = & $CaptureService $transaction
        foreach ($name in $targets.Keys) {
            $target = Assert-RollbackPath $targets[$name]
            $exists = Test-Path -LiteralPath $target
            $inventory = @(Get-RollbackInventory $target)
            $snapshot = Join-Path $transaction $name
            if ($exists) { Copy-RollbackTree $target $snapshot $inventory }
            # Check again to catch modifications during snapshot creation.
            Assert-RollbackInventory $target $inventory
            $acl = if ($exists) { (Get-Acl -LiteralPath $target).Sddl } else { $null }
            $journal.groups += [pscustomobject]@{ name = $name; exists = $exists; inventory = $inventory; acl = $acl }
        }
        # Migration/reset markers must match the restored database, too.
        $journal.rootFiles = @(Get-RollbackRootFiles $machine)
        Copy-RollbackTree $machine (Join-Path $transaction 'root-files') $journal.rootFiles
        $journal.state = 'prepared'
        Write-RollbackJournal $journalPath $journal
        return
    }
    if (-not $journal) { return }
    if ($Action -eq 'Arm') {
        if ($journal.state -ne 'prepared') { throw 'Snapshot is not ready' }
        & $StopProcesses
        foreach ($group in $journal.groups) {
            if ($group.exists) {
                $snapshotPath = Assert-RollbackPath (Join-Path $transaction $group.name)
                if (-not (Test-Path -LiteralPath $snapshotPath -PathType Container)) { throw 'Missing snapshot directory' }
                Assert-RollbackInventory $snapshotPath $group.inventory
                Assert-RollbackInventory $targets[$group.name] $group.inventory
            }
        }
        Assert-RollbackInventory (Join-Path $transaction 'root-files') $journal.rootFiles
        $currentRootFiles = @(Get-RollbackRootFiles $machine)
        if ($currentRootFiles.Count -ne @($journal.rootFiles).Count) { throw 'Machine metadata changed before install' }
        foreach ($entry in $journal.rootFiles) {
            if ((Get-RollbackHash (Join-Path $machine $entry.path)) -ne $entry.hash) { throw 'Machine metadata changed before install' }
        }
        $journal.state = 'installing'
        Write-RollbackJournal $journalPath $journal
        return
    }
    if ($Action -eq 'Commit') {
        if ($journal.state -notin @('installing', 'prepared')) { throw 'Cannot commit failed transaction' }
        $journal.state = 'committed'
        Write-RollbackJournal $journalPath $journal
        return
    }
    if ($Action -notin @('Restore', 'RecoverPending')) { throw 'Unknown rollback action' }
    if ($journal.state -notin @('committed', 'restored', 'prepared', 'preparing', 'installing', 'restoring', 'restore-failed')) { throw 'Invalid transaction state' }
    if ($journal.state -in @('committed', 'restored', 'prepared', 'preparing')) {
        if ($journal.state -eq 'preparing') { throw 'Snapshot incomplete; installation remains blocked' }
        return
    }
    try {
        # Refuse a foreign/changed registration before stopping it or replacing
        # application, database and credential files. Recheck at restore too.
        & $ValidateService $journal.service $transaction
        & $StopProcesses
        # Validate ALL groups before changing ANY destination.
        if (@($journal.groups).Count -ne $targets.Count) { throw 'Incomplete snapshot manifest' }
        $names = @{}
        foreach ($group in $journal.groups) {
            if (-not $targets.Contains($group.name) -or $names.ContainsKey($group.name)) { throw 'Invalid snapshot group' }
            $names[$group.name] = $true
            if ($group.exists) {
                $snapshotPath = Assert-RollbackPath (Join-Path $transaction $group.name)
                if (-not (Test-Path -LiteralPath $snapshotPath -PathType Container)) { throw 'Missing snapshot directory' }
                Assert-RollbackInventory $snapshotPath $group.inventory
            }
        }
        Assert-RollbackInventory (Join-Path $transaction 'root-files') $journal.rootFiles
        $journal.state = 'restoring'
        Write-RollbackJournal $journalPath $journal
        foreach ($group in $journal.groups) {
            $target = Assert-RollbackPath $targets[$group.name]
            $parent = Split-Path -Parent $target
            $quarantine = Join-Path $parent ((Split-Path -Leaf $target) + '.failed-' + $journal.id + '-' + [Guid]::NewGuid().ToString('N'))
            $null = Assert-RollbackPath $quarantine
            if ($group.exists) {
                $ready = Join-Path $parent ('.rollback-ready-' + [Guid]::NewGuid().ToString('N'))
                $null = Assert-RollbackPath $ready
                New-Item -ItemType Directory -Path $ready | Out-Null
                $acl = Get-Acl -LiteralPath $ready
                $acl.SetSecurityDescriptorSddlForm($group.acl)
                Set-Acl -LiteralPath $ready -AclObject $acl
                Copy-RollbackTree (Join-Path $transaction $group.name) $ready $group.inventory
                foreach ($entry in $group.inventory | Sort-Object { $_.path.Length } -Descending) {
                    $entryPath = Join-Path $ready $entry.path
                    $entryAcl = Get-Acl -LiteralPath $entryPath
                    $entryAcl.SetSecurityDescriptorSddlForm($entry.acl)
                    Set-Acl -LiteralPath $entryPath -AclObject $entryAcl
                }
                if (Test-Path -LiteralPath $target) { Move-Item -LiteralPath $target -Destination $quarantine }
                Move-Item -LiteralPath $ready -Destination $target
                Assert-RollbackInventory $target $group.inventory
            } elseif (Test-Path -LiteralPath $target) {
                $null = Get-RollbackInventory $target
                Move-Item -LiteralPath $target -Destination $quarantine
            }
        }
        # Stage the complete root-file set before moving any current markers.
        $readyFiles = Join-Path $transaction ('root-ready-' + [Guid]::NewGuid().ToString('N'))
        Copy-RollbackTree (Join-Path $transaction 'root-files') $readyFiles $journal.rootFiles
        $failedFiles = Join-Path $transaction ('root-failed-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $failedFiles | Out-Null
        foreach ($entry in @(Get-RollbackRootFiles $machine)) {
            Move-Item -LiteralPath (Join-Path $machine $entry.path) -Destination (Join-Path $failedFiles $entry.path)
        }
        foreach ($entry in $journal.rootFiles) {
            $destination = Join-Path $machine $entry.path
            Move-Item -LiteralPath (Join-Path $readyFiles $entry.path) -Destination $destination
            $acl = Get-Acl -LiteralPath $destination
            $acl.SetSecurityDescriptorSddlForm($entry.acl)
            Set-Acl -LiteralPath $destination -AclObject $acl
            if ((Get-RollbackHash $destination) -ne $entry.hash) { throw 'Restored metadata integrity mismatch' }
        }
        & $RestoreService $journal.service $transaction
        if ($journal.restart -and $journal.service.exists) { & $StartService }
        $journal.state = 'restored'
        $journal.error = $null
        Write-RollbackJournal $journalPath $journal
    } catch {
        $journal.state = 'restore-failed'
        $journal.error = $_.Exception.Message
        Write-RollbackJournal $journalPath $journal
        throw
    }
}
