param([string]$Scenario)
$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('winsw-test-' + [Guid]::NewGuid().ToString('N'))
function Check($condition, $message) { if (-not $condition) { throw $message } }
try {
    $app = Join-Path $root 'app with spaces'
    $machine = Join-Path $root 'machine'
    $toolsDir = Join-Path $app 'tools'
    New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
    $env:TEST_APP = $app
    $env:TEST_SCENARIO = $Scenario
    foreach ($name in @('winsw_service.ps1','winsw_config.ps1','rollback_core.ps1')) {
        Copy-Item -LiteralPath "$PSScriptRoot\..\..\installer\$name" -Destination $toolsDir
    }
    Set-Content -LiteralPath "$app\backup_database.exe" 'fake app'
    Set-Content -LiteralPath "$toolsDir\BackupDatabaseService.exe" 'fake wrapper, never executed'
    # Inject platform adapters only. Transaction, XML generation and recovery
    # are the production implementation; no command reaches the real SCM.
    Add-Content -LiteralPath "$toolsDir\rollback_core.ps1" -Value @'
function Get-RollbackHash($Path) {
  if ($env:TEST_SCENARIO -in @('bad-hash','interrupted-bad-hash')) { return 'corrupted' }
  return '05B82D46AD331CC16BDC00DE5C6332C1EF818DF8CEEFCD49C726553209B3A0DA'
}
'@
    if ($Scenario -eq 'commit-fails') {
        Add-Content -LiteralPath "$toolsDir\rollback_core.ps1" -Value @'
$script:originalJournalWriter = ${function:Write-RollbackJournal}
function Write-RollbackJournal($Path, $Journal) {
  if ($Journal.state -eq 'complete') { throw 'Injected commit disk failure' }
  & $script:originalJournalWriter $Path $Journal
}
'@
    }
    Add-Content -LiteralPath "$toolsDir\winsw_config.ps1" -Value @'
function Read-NssmRegistrySettings($Name) {
  $result = @{Application=(Join-Path $env:TEST_APP 'backup_database.exe');
    AppParameters='--mode=server --run-as-service --label="a&b"';
    AppDirectory=$env:TEST_APP; AppEnvironmentExtra=@('SERVICE_MODE=server','CUSTOM=a=b&c');
    AppStdout='C:\custom logs\out.log'; AppStderr='D:\custom logs\err.log';
    AppRestartDelay=12345; AppExit=@{''='Restart'; '77'='Exit'; '78'='Exit'} }
  if ($env:TEST_SCENARIO -eq 'unsupported') { $result.AppAffinity=2 }
  return $result
}
'@
    Set-Content -LiteralPath "$toolsDir\service_utils.ps1" -Value @'
function Wait-ServiceStopped { return [BackupServiceScm]::Stopped }
function Wait-ServiceRunning { return (-not [BackupServiceScm]::Stopped) }
function Wait-ServiceRemoved { return (-not [BackupServiceScm]::Exists) }
'@
    Set-Content -LiteralPath "$toolsDir\service_scm.ps1" -Value @'
if (-not ('BackupServiceScm' -as [type])) {
Add-Type -TypeDefinition @"
using System;
public static class BackupServiceScm {
  public static bool Exists=true,Stopped=false,FailImage=false;
  public static string Image="\"C:\\old app\\nssm.exe\"",Account="LocalSystem";
  public static int Starts=0,Creates=0,Deletes=0;
  public class Recovery { public uint Reset=123; public string Reboot="",Command=""; public int[] Types=new int[0]; public uint[] Delays=new uint[0]; public bool NonCrash=false; }
  public static Recovery Policy=new Recovery();
  public static Recovery GetRecovery(string name) { return Policy; }
  public static void SetImage(string name,string image) { if(FailImage) { FailImage=false; throw new Exception("Injected image failure"); } Image=image; }
}
"@
}
function Set-ServiceRecoverySnapshot($Name,$Saved) { [BackupServiceScm]::Policy=$Saved }
'@
    # Typed recovery assignment needs a converter, as in the native adapter.
    Add-Content -LiteralPath "$toolsDir\service_scm.ps1" -Value @'
function Set-ServiceRecoverySnapshot($Name,$Saved) {
  $r=New-Object BackupServiceScm+Recovery
  $r.Reset=$Saved.Reset; $r.Types=[int[]]@($Saved.Types); $r.Delays=[uint32[]]@($Saved.Delays)
  $r.NonCrash=[bool]$Saved.NonCrash; $r.Reboot=$Saved.Reboot; $r.Command=$Saved.Command
  [BackupServiceScm]::Policy=$r
}
'@
    . "$toolsDir\service_scm.ps1"
    function global:Get-CimInstance {
        if ([BackupServiceScm]::Exists) {
            [pscustomobject]@{ PathName=[BackupServiceScm]::Image; StartName=[BackupServiceScm]::Account;
                State=$(if ([BackupServiceScm]::Stopped) {'Stopped'} else {'Running'}) }
        }
    }
    function global:Set-Acl { }
    function global:Stop-Service {
        if ($env:TEST_SCENARIO -eq 'stop-fails') { throw 'Injected stop failure' }
        [BackupServiceScm]::Stopped=$true
        if ($env:TEST_SCENARIO -eq 'account-changed-on-stop') { [BackupServiceScm]::Account='CONTOSO\another-account' }
    }
    function global:Start-Service {
        if ($env:TEST_SCENARIO -eq 'foreign-image') {
            [BackupServiceScm]::Image='"C:\foreign\service.exe"'
            throw 'Concurrent service reconfiguration'
        }
        if ($env:TEST_SCENARIO -eq 'start-fails' -and [BackupServiceScm]::Image -match 'BackupDatabaseService.exe') { throw 'Injected start failure' }
        [BackupServiceScm]::Starts++; [BackupServiceScm]::Stopped=$false
    }
    function global:New-Service { param($Name,$BinaryPathName,$DisplayName,$StartupType,$ErrorAction,$Credential)
        [BackupServiceScm]::Creates++; [BackupServiceScm]::Exists=$true; [BackupServiceScm]::Image=$BinaryPathName
    }
    function global:sc.exe { [BackupServiceScm]::Deletes++; [BackupServiceScm]::Exists=$false; $global:LASTEXITCODE=0 }
    if ($Scenario -eq 'stopped') { [BackupServiceScm]::Stopped=$true }
    if ($Scenario -eq 'custom-account') { [BackupServiceScm]::Account="$env:USERDOMAIN\$env:USERNAME" }
    if ($Scenario -eq 'image-fails') { [BackupServiceScm]::FailImage=$true }
    if ($Scenario -eq 'fresh') { [BackupServiceScm]::Exists=$false; [BackupServiceScm]::Stopped=$true }
    if ($Scenario -eq 'custom-recovery') {
        [BackupServiceScm]::Policy.Types=@(1,0); [BackupServiceScm]::Policy.Delays=@(9000,0)
    }
    $originalImage=[BackupServiceScm]::Image
    $originalAccount=[BackupServiceScm]::Account
    if ($Scenario -in @('interrupted','interrupted-bad-hash','interrupted-missing-app')) {
        $pending = Join-Path $machine 'staging\service-migration'
        New-Item -ItemType Directory -Path $pending -Force | Out-Null
        @{ schema=1; state='switching'; app=$app; service='BackupDatabaseService';
            image=$originalImage; account=$originalAccount; running=$true;
            recovery=[BackupServiceScm]::Policy; oldXml=$null } |
            ConvertTo-Json -Depth 8 | Set-Content -LiteralPath "$pending\journal.json"
        [BackupServiceScm]::Image='"' + "$toolsDir\BackupDatabaseService.exe" + '"'
        if ($Scenario -eq 'interrupted-missing-app') { Remove-Item -LiteralPath "$app\backup_database.exe" }
    }
    & "$toolsDir\winsw_service.ps1" -AppPath "$app\backup_database.exe" -AppDirectory $app -MachineRoot $machine -Migrate
    $code=$LASTEXITCODE
    $failure=$Scenario -in @('bad-hash','unsupported','image-fails','start-fails','stop-fails','interrupted','interrupted-bad-hash','interrupted-missing-app','commit-fails','foreign-image','account-changed-on-stop')
    Check ($code -eq $(if ($failure) {1} else {0})) "Unexpected exit: $code ($Scenario)"
    Check ([BackupServiceScm]::Account -eq $(if ($Scenario -eq 'account-changed-on-stop') {'CONTOSO\another-account'} else {$originalAccount})) 'Changed service account'
    Check ([BackupServiceScm]::Deletes -eq 0) 'Deleted existing registration'
    Check ([BackupServiceScm]::Creates -eq $(if ($Scenario -eq 'fresh') {1} else {0})) 'Recreated existing registration'
    if ($failure) {
        if ($Scenario -eq 'account-changed-on-stop') {
            Check ([BackupServiceScm]::Image -eq $originalImage) 'Migrated registration after account changed'
            Check ([BackupServiceScm]::Starts -eq 0) 'Restarted changed registration'
            Check (-not (Test-Path "$toolsDir\BackupDatabaseService.xml")) 'Wrote XML for changed account'
            Check ((Get-Content "$machine\staging\service-migration\journal.json" -Raw | ConvertFrom-Json).state -eq 'restore-failed') 'Lost pending recovery'
            return
        }
        if ($Scenario -eq 'foreign-image') {
            Check ([BackupServiceScm]::Image -eq '"C:\foreign\service.exe"') 'Overwrote concurrent service image'
            $saved = Get-Content "$machine\staging\service-migration\journal.json" -Raw | ConvertFrom-Json
            Check ($saved.state -eq 'restore-failed') 'Lost pending manual recovery'
            return
        }
        Check ([BackupServiceScm]::Image -eq $originalImage) 'Did not restore original image'
        Check ([BackupServiceScm]::Policy.Types.Length -eq 0) 'Did not restore original recovery'
        if ($Scenario -in @('image-fails','start-fails','interrupted','interrupted-bad-hash','interrupted-missing-app','commit-fails')) {
            $saved = Get-Content "$machine\staging\service-migration\journal.json" -Raw | ConvertFrom-Json
            Check ($saved.state -eq 'restored') 'Injected failure did not exercise rollback'
            Check (-not [BackupServiceScm]::Stopped) 'Original running service was not restarted'
        }
    } else {
        Check ([BackupServiceScm]::Image.Trim('"') -eq "$toolsDir\BackupDatabaseService.exe") 'Did not migrate image'
        [xml]$xml=Get-Content -LiteralPath "$toolsDir\BackupDatabaseService.xml" -Raw
        Check (-not $xml.service.serviceaccount) 'Credentials serialized into XML'
        Check ($xml.service.executable -eq "$app\backup_database.exe") 'Wrong executable'
        if ($Scenario -ne 'fresh') {
            Check ($xml.service.arguments -match 'a&b') 'Arguments changed'
            Check (($xml.service.env | Where-Object name -eq 'CUSTOM').value -eq 'a=b&c') 'Environment changed'
            Check ($xml.service.outfilepattern -eq 'C:\custom logs\out.log') 'Stdout path changed'
        }
        if ($Scenario -in @('stopped','fresh')) { Check ([BackupServiceScm]::Starts -eq 0) 'Started previously stopped service' }
        if ($Scenario -eq 'custom-recovery') { Check ([BackupServiceScm]::Policy.Delays[0] -eq 9000) 'Overwrote custom SCM recovery' }
        $before=[IO.File]::ReadAllText("$toolsDir\BackupDatabaseService.xml")
        & "$toolsDir\winsw_service.ps1" -AppPath "$app\backup_database.exe" -AppDirectory $app -MachineRoot $machine -Migrate
        Check ($LASTEXITCODE -eq 0) 'Repeated migration failed'
        Check ([IO.File]::ReadAllText("$toolsDir\BackupDatabaseService.xml") -eq $before) 'Repeated migration overwrote XML'
    }
} finally {
    $resolved=[IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $resolved).StartsWith('winsw-test-')) { Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue }
}
