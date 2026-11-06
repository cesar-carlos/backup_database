param([string]$Scenario)
$ErrorActionPreference='Stop'
$root=Join-Path ([IO.Path]::GetTempPath()) ('winsw-update-' + [Guid]::NewGuid().ToString('N'))
function Check($condition,$message) { if (-not $condition) { throw $message } }
try {
    $app=Join-Path $root 'app'; $toolsDir=Join-Path $app 'tools'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    Copy-Item "$PSScriptRoot\..\..\installer\restore_update_state.ps1" $root
    Copy-Item "$PSScriptRoot\..\..\installer\encoding_utils.ps1" $root
    Set-Content "$toolsDir\BackupDatabaseService.exe" 'not executed'
    if ($Scenario -eq 'missing-wrapper') { Remove-Item -LiteralPath "$toolsDir\BackupDatabaseService.exe" }
    Set-Content "$toolsDir\service_utils.ps1" 'function Wait-ServiceRunning { return $true }'
    $context=Join-Path $root 'context.json'
    $origin=if ($Scenario -like 'ui-*') {'ui'} else {'service'}
    $wasRunning=$Scenario -ne 'ui-stopped'
    @{ schemaVersion=2; targetVersion='3.7.0'; origin=$origin; serviceExists=$true;
        expiresAt=[DateTime]::UtcNow.AddHours(1).ToString('o'); serviceWasRunning=$wasRunning;
        serviceConfig=@{Wrapper='winsw'; ObjectName=$(if ($Scenario -eq 'missing-account') {''} else {'CONTOSO\backup'})}; relaunchArguments=@('--mode=server') } |
        ConvertTo-Json | Set-Content -LiteralPath $context
    $global:winswTestStarts=0; $global:winswTestLaunches=0
    function global:Get-ItemProperty { [pscustomobject]@{
        ImagePath='"' + "$toolsDir\BackupDatabaseService.exe" + '"';
        ObjectName=$(if ($Scenario -eq 'account-changed') {'LocalSystem'} else {'CONTOSO\backup'})
    } }
    function global:Start-Service {
        if ($Scenario -eq 'start-fails') { throw 'Injected service start failure' }
        $global:winswTestStarts++
    }
    function global:Start-Process { $global:winswTestLaunches++ }
    function global:Get-AuthenticodeSignature { [pscustomobject]@{Status='Valid';SignerCertificate=$null;StatusMessage='test'} }
    & "$root\restore_update_state.ps1" -ContextPath $context -AppPath "$app\backup_database.exe" -AppDirectory $app -NssmPath "$root\DO-NOT-EXECUTE.exe"
    $failure=$Scenario -in @('account-changed','start-fails','missing-account','missing-wrapper')
    Check (($LASTEXITCODE -eq 0) -eq (-not $failure)) 'Wrong update result'
    Check ((Test-Path -LiteralPath $context) -eq $failure) 'Incorrect context retention'
    if (-not $failure) {
        Check ($global:winswTestStarts -eq [int]$wasRunning) 'Wrong restart policy'
        Check ($global:winswTestLaunches -eq [int]($origin -eq 'ui')) 'Wrong UI relaunch policy'
    } else {
        Check ($global:winswTestLaunches -eq 0) 'Relaunched after failed restoration'
        Check ($global:winswTestStarts -eq 0) 'Started unverified service'
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved).StartsWith('winsw-update-')) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
