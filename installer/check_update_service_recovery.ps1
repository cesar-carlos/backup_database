# Read-only: exit 0 = restart on pre-install abort; 1 = keep stopped; 2 = error.
param([string]$ContextPath, [string]$ServiceName = 'BackupDatabaseService')
$ErrorActionPreference = 'Stop'
try {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $service) { exit 1 }
    if ($service.Status -eq 'Running') { exit 0 }
    if (-not (Test-Path -LiteralPath $ContextPath)) { exit 1 }
    $context = Get-Content -LiteralPath $ContextPath -Raw | ConvertFrom-Json
    if ([int]$context.schemaVersion -lt 2) { exit 1 }
    $expires = [DateTime]::Parse([string]$context.expiresAt).ToUniversalTime()
    if ($expires -lt [DateTime]::UtcNow) { exit 1 }
    # The service updater already exited with 78 before Setup reached this step.
    if ([bool]$context.serviceExists -and
        ($context.origin -eq 'service' -or [bool]$context.serviceWasRunning)) { exit 0 }
    exit 1
} catch {
    [Console]::Error.WriteLine($_)
    exit 2
}
