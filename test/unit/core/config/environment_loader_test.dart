import 'package:backup_database/core/config/environment_loader.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
