import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsServiceElevationInstaller.buildElevatedInstallScript', () {
    const secret = 'S3cret-Pa55-not-in-script!';
    final planSets = NssmConfigPlan.build(
      appDir: r'C:\Program Files\Backup Database',
      logPath: r'C:\ProgramData\BackupDatabase\logs',
    ).toElevatedPowerShellSets();

    test('does not embed the service password or pass it to nssm', () {
      final script =
          WindowsServiceElevationInstaller.buildElevatedInstallScript(
            nssmPath: r'C:\Program Files\Backup Database\tools\nssm.exe',
            appPath: r'C:\Program Files\Backup Database\backup_database.exe',
            appDir: r'C:\Program Files\Backup Database',
            logPath: r'C:\ProgramData\BackupDatabase\logs',
            logDir: r'C:\ProgramData\BackupDatabase',
            configPath: r'C:\ProgramData\BackupDatabase\config',
            installLogPath: r'C:\Temp\install.log',
            serviceUser: r'CONTOSO\backupsvc',
            passwordFilePath: r'C:\Temp\locked.secret',
            planSets: planSets,
          );

      expect(script.contains(secret), isFalse);
      expect(script, isNot(contains(r"$servicePassword = '")));
      expect(script, contains('ReadAllText'));
      expect(script, contains(r'C:\Temp\locked.secret'));
      expect(script, contains('ChangeServiceConfig'));
      expect(script, contains('Set-ServiceAccountFromFile'));
      expect(
        script,
        isNot(contains('Set-NssmKeyWithRetry -KeyName "ObjectName"')),
      );
      expect(script, contains(r'Remove-Item -LiteralPath $passwordFile'));
    });

    test('local system install has no password file and no secret', () {
      final script =
          WindowsServiceElevationInstaller.buildElevatedInstallScript(
            nssmPath: r'C:\tools\nssm.exe',
            appPath: r'C:\app\backup_database.exe',
            appDir: r'C:\app',
            logPath: r'C:\logs',
            logDir: r'C:\logs',
            configPath: r'C:\config',
            installLogPath: r'C:\Temp\install.log',
            serviceUser: null,
            passwordFilePath: null,
            planSets: planSets,
          );

      expect(script.contains(secret), isFalse);
      expect(script, contains(r"$passwordFile = ''"));
      expect(script, contains('LocalSystem'));
    });
  });
}
