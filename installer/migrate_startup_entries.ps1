param(
    [string]$AppExePath,
    [ValidateSet('server', 'client')][string]$AppMode = 'server'
)

$ErrorActionPreference = 'Stop'

function Get-MigratedStartupCommand {
    param([string]$Name, [string]$Command, [string]$Executable, [string]$Mode)
    if ($Name -notin @('BackupDatabase', 'Backup Database')) { return $null }
    if ($Command -notmatch '^\s*"?(.+?\.exe)"?(?:\s+(.*))?\s*$') { return $null }
    $oldExecutable = [Environment]::ExpandEnvironmentVariables($Matches[1])
    $arguments = $Matches[2]
    if ([IO.Path]::GetFileName($oldExecutable) -ine [IO.Path]::GetFileName($Executable)) { return $null }
    if ($arguments -match '(?i)--schedule-id=') { return $null }
    # These entries are known logon triggers, so the origin is unambiguous.
    $arguments = ($arguments -replace '(?i)(^|\s)--(?:launch-origin=\S+|startup-launch|mode=\S+)(?=\s|$)', ' ').Trim()
    return ('"{0}" --mode={1} --launch-origin=windows-startup {2}' -f $Executable, $Mode, $arguments).Trim()
}

function Update-StartupRunKey {
    param([string]$Hive, [string]$Executable, [string]$Mode)
    foreach ($relative in @('Software\Microsoft\Windows\CurrentVersion\Run', 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')) {
        $path = 'Registry::' + $Hive + '\' + $relative
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $key = Get-Item -LiteralPath $path
        try {
            foreach ($name in @('BackupDatabase', 'Backup Database')) {
                $old = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                if ($null -eq $old) { continue }
                $updated = Get-MigratedStartupCommand $name ([string]$old) $Executable $Mode
                if ($null -ne $updated -and $updated -cne $old) {
                    Set-ItemProperty -LiteralPath $path -Name $name -Value $updated -ErrorAction Stop
                }
            }
        } finally { $key.Close() }
    }
}

function Get-StartupProfiles {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
        Where-Object { $_.PSChildName -match '^S-1-(5-21|12-1)-\d+(?:-\d+)+$' } |
        ForEach-Object {
            [pscustomobject]@{ Sid = $_.PSChildName; File = Join-Path ([Environment]::ExpandEnvironmentVariables($_.ProfileImagePath)) 'NTUSER.DAT' }
        }
}
function Test-StartupHiveLoaded { param([string]$Sid) Test-Path -LiteralPath ('Registry::HKEY_USERS\' + $Sid) }
function Mount-StartupHive {
    param([string]$Name, [string]$File)
    & reg.exe load "HKU\$Name" $File | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cannot load profile hive: $Name (exit $LASTEXITCODE)" }
}
function Dismount-StartupHive {
    param([string]$Name)
    & reg.exe unload "HKU\$Name" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Cannot unload profile hive: $Name (exit $LASTEXITCODE)" }
}

function Invoke-StartupProfileMigration {
    param([string]$Executable, [string]$Mode)
    $failures = [Collections.Generic.List[string]]::new()
    foreach ($hive in @('HKEY_LOCAL_MACHINE', 'HKEY_CURRENT_USER')) {
        try { Update-StartupRunKey $hive $Executable $Mode }
        catch { $failures.Add("${hive}: $_") }
    }
    foreach ($profile in @(Get-StartupProfiles)) {
        $mountedName = $null
        try {
            if (Test-StartupHiveLoaded $profile.Sid) {
                $hive = 'HKEY_USERS\' + $profile.Sid
            } else {
                $name = 'BackupDatabaseStartup_' + [Guid]::NewGuid().ToString('N')
                Mount-StartupHive $name $profile.File
                $mountedName = $name
                $hive = 'HKEY_USERS\' + $name
            }
            Update-StartupRunKey $hive $Executable $Mode
        } catch { $failures.Add("$($profile.Sid): $_") }
        finally {
            if ($null -ne $mountedName) {
                try { Dismount-StartupHive $mountedName }
                catch { $failures.Add("${mountedName}: $_") }
            }
        }
    }
    if ($failures.Count -gt 0) { throw ($failures -join "`n") }
}

function Update-MachineStartupTask {
    param([string]$Executable, [string]$Mode)
    $task = Get-ScheduledTask -TaskPath '\BackupDatabase\' -TaskName 'MachineStartup' -ErrorAction SilentlyContinue
    if ($null -eq $task) { return }
    $changed = $false
    foreach ($action in $task.Actions) {
        if ([IO.Path]::GetFileName($action.Execute) -ine [IO.Path]::GetFileName($Executable)) { continue }
        $command = Get-MigratedStartupCommand 'BackupDatabase' ('"{0}" {1}' -f $action.Execute, $action.Arguments) $Executable $Mode
        if ($null -eq $command) { continue }
        $action.Execute = $Executable
        $action.Arguments = $command.Substring($Executable.Length + 3)
        $changed = $true
    }
    if ($changed) { Set-ScheduledTask -InputObject $task -ErrorAction Stop | Out-Null }
}

# Dot sourcing only defines functions, allowing tests without registry access.
if ($MyInvocation.InvocationName -ne '.') {
    if ([string]::IsNullOrWhiteSpace($AppExePath) -or -not [IO.Path]::IsPathRooted($AppExePath)) {
        throw 'An absolute AppExePath is required.'
    }
    $failed = $false
    try { Invoke-StartupProfileMigration $AppExePath $AppMode }
    catch { Write-Warning "Startup profile migration failed: $_"; $failed = $true }
    try { Update-MachineStartupTask $AppExePath $AppMode }
    catch { Write-Warning "Startup task migration failed: $_"; $failed = $true }
    if ($failed) { exit 1 }
}
