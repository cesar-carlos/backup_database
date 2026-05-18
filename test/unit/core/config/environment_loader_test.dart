import 'dart:io';

import 'package:backup_database/core/config/environment_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('EnvironmentLoader.resolveLoadPlan', () {
    test('prefers external machine file on Windows when present', () {
      const externalPath = r'C:\ProgramData\BackupDatabase\config\.env';

      final plan = EnvironmentLoader.resolveLoadPlan(
        isWindows: true,
        externalFileExists: true,
        externalFilePath: externalPath,
      );

      expect(plan.source, EnvironmentSource.externalMachineFile);
      expect(plan.filePath, externalPath);
    });

    test('falls back to bundled asset when external file is missing', () {
      final plan = EnvironmentLoader.resolveLoadPlan(
        isWindows: true,
        externalFileExists: false,
        externalFilePath: r'C:\ProgramData\BackupDatabase\config\.env',
      );

      expect(plan.source, EnvironmentSource.bundledAsset);
      expect(plan.description, EnvironmentLoader.bundledAssetFileName);
    });

    test(
      'uses bundled asset outside Windows even when external path exists',
      () {
        final plan = EnvironmentLoader.resolveLoadPlan(
          isWindows: false,
          externalFileExists: true,
          externalFilePath: r'C:\ProgramData\BackupDatabase\config\.env',
        );

        expect(plan.source, EnvironmentSource.bundledAsset);
      },
    );
  });

  group('EnvironmentLoader.migrateLegacyWindowsEnvironmentIfNeeded', () {
    test(
      'copies legacy app env into ProgramData and preserves a backup',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'env_migration_test',
        );
        final externalEnv = File(
          p.join(
            tempDir.path,
            'ProgramData',
            'BackupDatabase',
            'config',
            '.env',
          ),
        );
        final legacyEnv = File(p.join(tempDir.path, 'app', '.env'));
        await legacyEnv.parent.create(recursive: true);
        await legacyEnv.writeAsString(
          'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml',
        );

        final migrated =
            await EnvironmentLoader.migrateLegacyWindowsEnvironmentIfNeeded(
              isWindows: true,
              externalEnvFile: externalEnv,
              legacyEnvFile: legacyEnv,
            );

        expect(migrated, isTrue);
        expect(
          await externalEnv.readAsString(),
          contains('AUTO_UPDATE_FEED_URL'),
        );

        final backup = File(
          p.join(
            externalEnv.parent.path,
            EnvironmentLoader.migratedBackupFileName,
          ),
        );
        expect(await backup.exists(), isTrue);
        expect(await backup.readAsString(), contains('AUTO_UPDATE_FEED_URL'));
        expect(await legacyEnv.exists(), isTrue);

        await tempDir.delete(recursive: true);
      },
    );

    test('skips migration when ProgramData env already exists', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'env_migration_test',
      );
      final externalEnv = File(
        p.join(tempDir.path, 'ProgramData', 'BackupDatabase', 'config', '.env'),
      );
      final legacyEnv = File(p.join(tempDir.path, 'app', '.env'));
      await externalEnv.parent.create(recursive: true);
      await legacyEnv.parent.create(recursive: true);
      await externalEnv.writeAsString('CURRENT=1');
      await legacyEnv.writeAsString('LEGACY=1');

      final migrated =
          await EnvironmentLoader.migrateLegacyWindowsEnvironmentIfNeeded(
            isWindows: true,
            externalEnvFile: externalEnv,
            legacyEnvFile: legacyEnv,
          );

      expect(migrated, isFalse);
      expect(await externalEnv.readAsString(), 'CURRENT=1');

      await tempDir.delete(recursive: true);
    });
  });
}
