$ErrorActionPreference = 'Stop'

function ConvertTo-WinSWConfig {
    param([string]$ServiceName, [string]$AppPath, [string]$AppDirectory,
        [string]$LogDirectory, [hashtable]$Legacy = @{})
    # Refuse unsupported NSSM settings rather than silently lose behavior.
    $supported = @('Application','AppDirectory','AppParameters','AppEnvironmentExtra',
        'AppStdout','AppStderr','AppRestartDelay','AppNoConsole','AppExit')
    foreach ($key in $Legacy.Keys) {
        if ($key -notin $supported) { throw "NSSM setting requires manual migration: $key" }
    }
    if ($Legacy.Application -and [IO.Path]::GetFullPath($Legacy.Application) -ne [IO.Path]::GetFullPath($AppPath)) {
        throw 'NSSM Application points to another installation'
    }
    if ($Legacy.AppExit) {
        foreach ($key in $Legacy.AppExit.Keys) {
            $value = $Legacy.AppExit[$key]
            if (($key -eq '' -and $value -notin @('Restart','Exit')) -or
                ($key -in @('77','78') -and $value -ne 'Exit') -or
                $key -notin @('','77','78')) { throw "Unsupported NSSM exit policy: $key" }
        }
    }
    $doc = New-Object Xml.XmlDocument
    $root = $doc.CreateElement('service'); $null = $doc.AppendChild($root)
    $values = [ordered]@{
        id = $ServiceName; name = $ServiceName; description = 'Backup Database service';
        executable = $AppPath;
        arguments = $(if ($Legacy.ContainsKey('AppParameters')) { $Legacy.AppParameters } else { '--mode=server --minimized --run-as-service' });
        workingdirectory = $(if ($Legacy.AppDirectory) { $Legacy.AppDirectory } else { $AppDirectory });
        hidewindow = $(if ($Legacy.ContainsKey('AppNoConsole') -and -not $Legacy.AppNoConsole) {'false'} else {'true'});
        stoptimeout = '60sec'; logpath = $LogDirectory;
        logname = 'service'; outfilepattern = '_stdout.log'; errfilepattern = '_stderr.log'
    }
    foreach ($pair in @(@('AppStdout','outfilepattern'), @('AppStderr','errfilepattern'))) {
        if ($Legacy[$pair[0]]) {
            $path = [string]$Legacy[$pair[0]]
            # WinSW prefixes the pattern with logname, so use an empty logname
            # and absolute patterns to preserve each original output path.
            $values.logname = ''
            $values[$pair[1]] = $path
        }
    }
    if ($values.logname -eq '') {
        if (-not $Legacy.AppStdout) { $values.outfilepattern = Join-Path $LogDirectory 'service_stdout.log' }
        if (-not $Legacy.AppStderr) { $values.errfilepattern = Join-Path $LogDirectory 'service_stderr.log' }
    }
    foreach ($key in $values.Keys) {
        $node = $doc.CreateElement($key); $node.InnerText = [string]$values[$key]; $null = $root.AppendChild($node)
    }
    $environment = [ordered]@{ SERVICE_MODE = 'server'; BACKUP_SERVICE_WRAPPER = 'winsw' }
    foreach ($entry in @($Legacy.AppEnvironmentExtra)) {
        if (-not $entry) { continue }
        $parts = ([string]$entry) -split '=', 2
        if ($parts.Count -ne 2 -or -not $parts[0]) { throw 'Invalid NSSM environment entry' }
        if ($parts[0] -eq 'BACKUP_SERVICE_WRAPPER' -and $parts[1] -ne 'winsw') { throw 'Reserved wrapper environment variable' }
        $environment[$parts[0]] = $parts[1]
    }
    foreach ($key in $environment.Keys) {
        $node = $doc.CreateElement('env'); $node.SetAttribute('name',$key); $node.SetAttribute('value',$environment[$key]); $null = $root.AppendChild($node)
    }
    $node = $doc.CreateElement('log'); $node.SetAttribute('mode','append'); $null = $root.AppendChild($node)
    return $doc.OuterXml
}

function Read-NssmRegistrySettings([string]$ServiceName) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Services\$ServiceName\Parameters"
    $key = Get-Item -LiteralPath $path -ErrorAction Stop
    $settings = @{}
    foreach ($name in $key.GetValueNames()) { $settings[$name] = $key.GetValue($name) }
    foreach ($child in $key.GetSubKeyNames()) {
        if ($child -ne 'AppExit') { throw "Unsupported NSSM subkey: $child" }
        $exitKey = $key.OpenSubKey($child)
        try {
            $settings.AppExit = @{}
            foreach ($name in $exitKey.GetValueNames()) { $settings.AppExit[$name] = $exitKey.GetValue($name) }
        } finally { $exitKey.Dispose() }
    }
    return $settings
}
