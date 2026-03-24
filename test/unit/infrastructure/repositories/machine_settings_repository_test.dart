import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/machine_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MachineSettingsRepository', () {
    AppDatabase? database;

    tearDown(() async {
      await database?.close();
      database = null;
    });

    test(
      'should seed singleton from SharedPreferences and remove legacy keys',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'start_with_windows': true,
          'start_minimized': true,
          'custom_temp_downloads_path': r'C:\TempCustom',
          AppConstants.receivedBackupsDefaultPathKey: r'D:\received',
          AppConstants.scheduleTransferDestinationsKey: '{"x":1}',
        });
        database = AppDatabase.inMemory();
        final repository = MachineSettingsRepository(database!);

        expect(await repository.getStartWithWindows(), isTrue);
        expect(await repository.getStartMinimized(), isTrue);
        expect(
          await repository.getCustomTempDownloadsPath(),
          r'C:\TempCustom',
        );
        expect(
          await repository.getReceivedBackupsDefaultPath(),
          r'D:\received',
        );
        expect(
          await repository.getScheduleTransferDestinationsJson(),
          '{"x":1}',
        );

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('start_with_windows'), isFalse);
        expect(prefs.containsKey('start_minimized'), isFalse);
        expect(prefs.containsKey('custom_temp_downloads_path'), isFalse);
        expect(
          prefs.containsKey(AppConstants.receivedBackupsDefaultPathKey),
          isFalse,
        );
        expect(
          prefs.containsKey(AppConstants.scheduleTransferDestinationsKey),
          isFalse,
        );
      },
    );

    test(
      'should use defaults when SharedPreferences has no machine keys',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
        database = AppDatabase.inMemory();
        final repository = MachineSettingsRepository(database!);

        expect(await repository.getStartWithWindows(), isFalse);
        expect(await repository.getStartMinimized(), isFalse);
        expect(await repository.getCustomTempDownloadsPath(), isNull);
        expect(await repository.getReceivedBackupsDefaultPath(), isNull);
        expect(await repository.getScheduleTransferDestinationsJson(), isNull);
      },
    );

    test('should persist updates after seed', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      database = AppDatabase.inMemory();
      final repository = MachineSettingsRepository(database!);

      await repository.setStartWithWindows(true);
      await repository.setStartMinimized(true);
      await repository.setCustomTempDownloadsPath(r'E:\tmp');
      await repository.setReceivedBackupsDefaultPath(r'F:\in');
      await repository.setScheduleTransferDestinationsJson('[]');

      expect(await repository.getStartWithWindows(), isTrue);
      expect(await repository.getStartMinimized(), isTrue);
      expect(await repository.getCustomTempDownloadsPath(), r'E:\tmp');
      expect(await repository.getReceivedBackupsDefaultPath(), r'F:\in');
      expect(await repository.getScheduleTransferDestinationsJson(), '[]');
    });

    test('should not re-seed from prefs when row already exists', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      database = AppDatabase.inMemory();
      final repository = MachineSettingsRepository(database!);

      await repository.setStartWithWindows(true);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('start_with_windows', false);
      expect(await repository.getStartWithWindows(), isTrue);
    });

    test('should clear nullable string fields', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      database = AppDatabase.inMemory();
      final repository = MachineSettingsRepository(database!);

      await repository.setCustomTempDownloadsPath('before');
      expect(await repository.getCustomTempDownloadsPath(), 'before');
      await repository.setCustomTempDownloadsPath(null);
      expect(await repository.getCustomTempDownloadsPath(), isNull);
    });

    test('should seed only once across concurrent first reads', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'start_with_windows': true,
        'start_minimized': true,
        'custom_temp_downloads_path': r'C:\TempConcurrent',
        AppConstants.receivedBackupsDefaultPathKey: r'D:\concurrent',
      });
      database = AppDatabase.inMemory();
      final repository = MachineSettingsRepository(database!);

      final results = await Future.wait<Object?>(<Future<Object?>>[
        repository.getStartWithWindows(),
        repository.getStartMinimized(),
        repository.getCustomTempDownloadsPath(),
        repository.getReceivedBackupsDefaultPath(),
      ]);

      expect(results[0], isTrue);
      expect(results[1], isTrue);
      expect(results[2], r'C:\TempConcurrent');
      expect(results[3], r'D:\concurrent');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('start_with_windows'), isFalse);
      expect(prefs.containsKey('start_minimized'), isFalse);
      expect(prefs.containsKey('custom_temp_downloads_path'), isFalse);
      expect(
        prefs.containsKey(AppConstants.receivedBackupsDefaultPathKey),
        isFalse,
      );
    });
  });
}
