import 'dart:convert';
import 'dart:io';

import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scenario in ['local-system', 'custom-account', 'failure']) {
    test('WinSW UAC adapter delegates securely: $scenario', () async {
      final temp = await Directory.systemTemp.createTemp("service install '& ");
      addTearDown(() => temp.delete(recursive: true));
      final tools = await Directory('${temp.path}/tools').create();
      final secret = File('${temp.path}/password.txt');
      await secret.writeAsString('test-password');
      final report = File('${temp.path}/report.json');
      await File('${tools.path}/install_service.ps1').writeAsString(r'''
param($AppPath,$AppDirectory,$ServiceUser,[SecureString]$ServicePassword,[switch]$NonInteractive)
$matches=$false
if ($ServicePassword) {
  $credential=New-Object Management.Automation.PSCredential('user',$ServicePassword)
  $matches=$credential.GetNetworkCredential().Password -eq 'test-password'
}
@{ user=$ServiceUser; passwordMatches=$matches; app=$AppPath; nonInteractive=$NonInteractive.IsPresent } |
  ConvertTo-Json | Set-Content -LiteralPath $env:TEST_REPORT
if ($env:TEST_SCENARIO -eq 'failure') { exit 31 }
exit 0
''');
      final script =
          WindowsServiceElevationInstaller.buildElevatedInstallScript(
            wrapperPath: '${tools.path}/BackupDatabaseService.exe',
            appPath: '${temp.path}/backup_database.exe',
            appDir: temp.path,
            logPath: temp.path,
            logDir: temp.path,
            configPath: temp.path,
            installLogPath: '${temp.path}/install.log',
            serviceUser: scenario == 'local-system' ? null : r'CONTOSO\backup',
            passwordFilePath: scenario == 'local-system' ? null : secret.path,
            planSets: '',
          );
      expect(script, isNot(contains('test-password')));
      expect(script, isNot(contains('nssm')));
      final generated = await File('${temp.path}/run.ps1')
          .writeAsString(script);
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          generated.path,
        ],
        environment: {'TEST_REPORT': report.path, 'TEST_SCENARIO': scenario},
      );
      expect(
        result.exitCode,
        scenario == 'failure' ? 31 : 0,
        reason: '${result.stdout}\n${result.stderr}',
      );
      final data =
          jsonDecode(await report.readAsString()) as Map<String, dynamic>;
      expect(data['app'], '${temp.path}/backup_database.exe');
      expect(data['nonInteractive'], isTrue);
      expect(data['passwordMatches'], scenario != 'local-system');
      if (scenario != 'local-system') expect(secret.existsSync(), isFalse);
    }, skip: !Platform.isWindows);
  }
}
