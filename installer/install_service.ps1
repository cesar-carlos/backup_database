# Install a new WinSW service. Existing registrations are migrated only by Setup.
param(
    [string]$ServiceName = 'BackupDatabaseService',
    [string]$AppPath = '', [string]$AppDirectory = '',
    [string]$NssmPath = '', # Compatibility with older installer callers; never executed.
    [string]$DisplayName = 'Backup Database Service', [string]$Description = '',
    [string]$ServiceUser = '', [SecureString]$ServicePassword,
    [switch]$NonInteractive, [switch]$StartAfterInstall
)
if (-not $AppPath) { $AppPath = Join-Path $PSScriptRoot '..\backup_database.exe' }
if (-not $AppDirectory) { $AppDirectory = Split-Path $AppPath -Parent }
& (Join-Path $PSScriptRoot 'winsw_service.ps1') -AppPath $AppPath -AppDirectory $AppDirectory -ServiceName $ServiceName -ServiceUser $ServiceUser -ServicePassword $ServicePassword -StartAfterInstall:$StartAfterInstall
exit $LASTEXITCODE