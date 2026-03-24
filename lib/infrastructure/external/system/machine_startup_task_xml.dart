const String machineLogonStartupTaskPath = r'BackupDatabase\MachineStartup';

String escapeXmlForMachineStartupTask(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}

String buildMachineLogonStartupTaskXml({
  required String command,
  required String arguments,
}) {
  final safeCommand = escapeXmlForMachineStartupTask(command);
  final safeArgs = escapeXmlForMachineStartupTask(arguments);
  const uri = r'\BackupDatabase\MachineStartup';
  return '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<Task version="1.2" '
      'xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">\n'
      '  <RegistrationInfo>\n'
      '    <URI>$uri</URI>\n'
      '    <Description>Backup Database — início ao logon (escopo máquina)</Description>\n'
      '  </RegistrationInfo>\n'
      '  <Triggers>\n'
      '    <LogonTrigger>\n'
      '      <Enabled>true</Enabled>\n'
      '    </LogonTrigger>\n'
      '  </Triggers>\n'
      '  <Principals>\n'
      '    <Principal id="Author">\n'
      '      <LogonType>InteractiveToken</LogonType>\n'
      '      <RunLevel>LeastPrivilege</RunLevel>\n'
      '    </Principal>\n'
      '  </Principals>\n'
      '  <Settings>\n'
      '    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>\n'
      '    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>\n'
      '    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>\n'
      '    <AllowHardTerminate>true</AllowHardTerminate>\n'
      '    <StartWhenAvailable>true</StartWhenAvailable>\n'
      '    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>\n'
      '    <IdleSettings>\n'
      '      <StopOnIdleEnd>false</StopOnIdleEnd>\n'
      '      <RestartOnIdle>false</RestartOnIdle>\n'
      '    </IdleSettings>\n'
      '    <AllowStartOnDemand>true</AllowStartOnDemand>\n'
      '    <Enabled>true</Enabled>\n'
      '    <Hidden>false</Hidden>\n'
      '    <RunOnlyIfIdle>false</RunOnlyIfIdle>\n'
      '    <WakeToRun>false</WakeToRun>\n'
      '    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>\n'
      '    <Priority>7</Priority>\n'
      '  </Settings>\n'
      '  <Actions Context="Author">\n'
      '    <Exec>\n'
      '      <Command>$safeCommand</Command>\n'
      '      <Arguments>$safeArgs</Arguments>\n'
      '    </Exec>\n'
      '  </Actions>\n'
      '</Task>\n';
}
