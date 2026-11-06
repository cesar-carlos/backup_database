$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\..\installer\migrate_startup_entries.ps1')
function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
$exe = 'C:\Program Files\Backup Database\backup_database.exe'
foreach ($old in @('"C:\Old\backup_database.exe"', '"C:\Old\backup_database.exe" --minimized', 'C:\Old\backup_database.exe --startup-launch', '"C:\Old\backup_database.exe" --mode=server --launch-origin=old --minimized')) {
    $new = Get-MigratedStartupCommand 'BackupDatabase' $old $exe 'client'
    Assert-True ($new.StartsWith('"' + $exe + '"')) 'Must use newly installed executable'
    Assert-True ($new.Contains('--launch-origin=windows-startup')) 'Missing startup origin'
    Assert-True ($new.Contains('--mode=client')) 'Wrong installed mode'
    Assert-True (-not $new.Contains('--startup-launch')) 'Legacy alias survived'
    Assert-True ((Get-MigratedStartupCommand 'BackupDatabase' $new $exe 'client') -eq $new) 'Migration must be idempotent'
}
Assert-True ($null -eq (Get-MigratedStartupCommand 'OtherApp' ('"' + $exe + '"') $exe 'client')) 'Unrelated entry was migrated'
Assert-True ($null -eq (Get-MigratedStartupCommand 'BackupDatabase' '"C:\other.exe"' $exe 'client')) 'Unrelated executable was migrated'
Assert-True ($null -eq (Get-MigratedStartupCommand 'BackupDatabase' ('"' + $exe + '" --schedule-id=job') $exe 'client')) 'Scheduled backup was changed'

# Replace all registry adapters: no real hives or startup entries are touched.
$script:events = [Collections.Generic.List[string]]::new()
$script:failUpdate = $false
$script:failMount = $false
function Get-StartupProfiles {
    @([pscustomobject]@{ Sid = 'loaded'; File = 'loaded.dat' },
      [pscustomobject]@{ Sid = 'offline'; File = 'offline.dat' },
      [pscustomobject]@{ Sid = 'last'; File = 'last.dat' })
}
function Test-StartupHiveLoaded([string]$Sid) { $Sid -ne 'offline' }
function Mount-StartupHive([string]$Name, [string]$File) {
    $script:events.Add('mount:' + $Name)
    if ($script:failMount) { throw 'load failed' }
}
function Dismount-StartupHive([string]$Name) { $script:events.Add('unload:' + $Name) }
function Update-StartupRunKey([string]$Hive, [string]$Executable, [string]$Mode) {
    $script:events.Add('update:' + $Hive)
    if ($script:failUpdate -and $Hive -like '*BackupDatabaseStartup_*') { throw 'write denied' }
}
Invoke-StartupProfileMigration $exe 'client'
Assert-True ($events.Contains('update:HKEY_USERS\loaded')) 'Loaded RDP profile omitted'
Assert-True ($events.Contains('update:HKEY_USERS\last')) 'Later profile omitted'
Assert-True (@($events | Where-Object { $_ -like 'mount:*' }).Count -eq 1) 'Only unloaded profile should be mounted'
Assert-True (@($events | Where-Object { $_ -like 'unload:*' }).Count -eq 1) 'Owned hive must be unloaded'
Assert-True (@($events | Where-Object { $_ -like 'update:HKEY_USERS\BackupDatabaseStartup_*' }).Count -eq 1) 'Offline profile omitted'

$events.Clear(); $script:failUpdate = $true
$failed = $false
try { Invoke-StartupProfileMigration $exe 'server' } catch { $failed = $true }
Assert-True $failed 'Failure must be reported'
Assert-True (@($events | Where-Object { $_ -like 'unload:*' }).Count -eq 1) 'Write failure leaked mounted hive'
Assert-True ($events.Contains('update:HKEY_USERS\last')) 'Failure skipped remaining profiles'
$events.Clear(); $script:failUpdate = $false; $script:failMount = $true
try { Invoke-StartupProfileMigration $exe 'client'; throw 'Expected failure' } catch {
    Assert-True ($_.ToString().Contains('load failed')) 'Wrong load error'
}
Assert-True (@($events | Where-Object { $_ -like 'unload:*' }).Count -eq 0) 'Must not unload a hive we did not mount'

$script:task = [pscustomobject]@{
    Actions = @([pscustomobject]@{ Execute = 'C:\Old\backup_database.exe'; Arguments = '--minimized' })
    Settings = [pscustomobject]@{ Enabled = $false }
}
$script:saved = $null
function Get-ScheduledTask { param($TaskPath, $TaskName, $ErrorAction) return $script:task }
function Set-ScheduledTask { param($InputObject, $ErrorAction) $script:saved = $InputObject }
Update-MachineStartupTask $exe 'client'
Assert-True ($saved.Actions[0].Execute -eq $exe) 'Task executable not migrated'
Assert-True ($saved.Actions[0].Arguments -eq '--mode=client --launch-origin=windows-startup --minimized') 'Task origin not migrated'
Assert-True (-not $saved.Settings.Enabled) 'Disabled task was enabled'
Write-Output 'Startup migration regression tests passed'
