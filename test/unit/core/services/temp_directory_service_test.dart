import 'dart:io';

import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TempDirectoryService tempService;
  late Directory testTempDir;
  late _FakeMachineSettingsRepository machineSettings;

  setUp(() async {
    machineSettings = _FakeMachineSettingsRepository();
    tempService = TempDirectoryService(machineSettings: machineSettings);
    testTempDir = await Directory.systemTemp.createTemp(
      'temp_dir_service_test_',
    );
  });

  tearDown(() async {
    if (await testTempDir.exists()) {
      await testTempDir.delete(recursive: true);
    }
    machineSettings.customTempDownloadsPath = null;
    tempService.clearCache();
  });

  group('TempDirectoryService', () {
    test('getDownloadsDirectory cria pasta se nao existir', () async {
      final downloadsDir = await tempService.getDownloadsDirectory();

      expect(await downloadsDir.exists(), isTrue);
      expect(downloadsDir.path.contains('BackupDatabase'), isTrue);
      expect(downloadsDir.path.contains('Downloads'), isTrue);
    });

    test(
      'getDownloadsDirectory retorna mesma pasta em chamadas subsequentes',
      () async {
        final dir1 = await tempService.getDownloadsDirectory();
        final dir2 = await tempService.getDownloadsDirectory();

        expect(dir1.path, equals(dir2.path));
      },
    );

    test('getTempDirectory retorna temp do sistema por padrao', () async {
      final tempDir = await tempService.getTempDirectory();

      expect(
        p.normalize(tempDir.path),
        equals(p.normalize(Directory.systemTemp.path)),
      );
    });

    test('setCustomTempPath valida e salva path customizado', () async {
      final customDir = await testTempDir.createTemp('custom_');
      final result = await tempService.setCustomTempPath(customDir.path);

      expect(result, isTrue);

      final savedPath = await tempService.getCustomTempPath();
      expect(savedPath, equals(customDir.path));
    });

    test('setCustomTempPath retorna false para path invalido', () async {
      final invalidPathAsFile = File(
        p.join(testTempDir.path, 'not_a_directory.txt'),
      );
      await invalidPathAsFile.writeAsString('invalid');
      final result = await tempService.setCustomTempPath(
        invalidPathAsFile.path,
      );

      expect(result, isFalse);
    });

    test('getTempDirectory usa custom path se configurado', () async {
      final customDir = await testTempDir.createTemp('custom_temp_');
      await tempService.setCustomTempPath(customDir.path);

      final tempDir = await tempService.getTempDirectory();

      expect(tempDir.path, equals(customDir.path));
    });

    test('clearCustomTempPath remove configuracao customizada', () async {
      final customDir = await testTempDir.createTemp('to_clear_');
      await tempService.setCustomTempPath(customDir.path);
      expect(await tempService.getCustomTempPath(), isNotNull);

      await tempService.clearCustomTempPath();

      expect(await tempService.getCustomTempPath(), isNull);
    });

    test('clearCustomTempPath volta a usar temp do sistema', () async {
      final customDir = await testTempDir.createTemp('to_clear_');
      await tempService.setCustomTempPath(customDir.path);

      await tempService.clearCustomTempPath();
      final tempDir = await tempService.getTempDirectory();

      expect(tempDir.path, isNot(equals(customDir.path)));
      expect(
        p.normalize(tempDir.path),
        equals(p.normalize(Directory.systemTemp.path)),
      );
    });

    test('clearCache limpa cache de diretorios', () async {
      await tempService.getDownloadsDirectory();
      tempService.clearCache();

      final dir = await tempService.getDownloadsDirectory();
      expect(dir, isNotNull);
    });

    test(
      '_isValidDirectory retorna true para diretorio com permissao',
      () async {
        final validDir = await testTempDir.createTemp('valid_');

        final result = await tempService.setCustomTempPath(validDir.path);

        expect(result, isTrue);
      },
    );

    test(
      'getDownloadsDirectory usa custom path na subpasta Downloads',
      () async {
        final customBase = await testTempDir.createTemp('base_');
        await tempService.setCustomTempPath(customBase.path);

        final downloadsDir = await tempService.getDownloadsDirectory();

        expect(downloadsDir.path, startsWith(customBase.path));
        expect(downloadsDir.path, contains('Downloads'));
      },
    );

    test(
      'getTempDirectory clears custom path when path is not a directory',
      () async {
        final blockingFile = File(p.join(testTempDir.path, 'not_a_directory'));
        await blockingFile.writeAsString('x');
        machineSettings.customTempDownloadsPath = blockingFile.path;

        final tempDir = await tempService.getTempDirectory();

        expect(
          p.normalize(tempDir.path),
          equals(p.normalize(Directory.systemTemp.path)),
        );
        expect(await tempService.getCustomTempPath(), isNull);
      },
    );

    test(
      'validateDownloadsDirectory returns true for writable folder',
      () async {
        final ok = await tempService.validateDownloadsDirectory();
        expect(ok, isTrue);
      },
    );
  });
}

class _FakeMachineSettingsRepository implements IMachineSettingsRepository {
  bool startWithWindows = false;
  bool startMinimized = false;
  String? customTempDownloadsPath;
  String? receivedBackupsDefaultPath;
  String? scheduleTransferDestinationsJson;

  @override
  Future<bool> getStartWithWindows() async => startWithWindows;

  @override
  Future<void> setStartWithWindows(bool value) async {
    startWithWindows = value;
  }

  @override
  Future<bool> getStartMinimized() async => startMinimized;

  @override
  Future<void> setStartMinimized(bool value) async {
    startMinimized = value;
  }

  @override
  Future<String?> getCustomTempDownloadsPath() async => customTempDownloadsPath;

  @override
  Future<void> setCustomTempDownloadsPath(String? path) async {
    customTempDownloadsPath = path;
  }

  @override
  Future<String?> getReceivedBackupsDefaultPath() async =>
      receivedBackupsDefaultPath;

  @override
  Future<void> setReceivedBackupsDefaultPath(String? path) async {
    receivedBackupsDefaultPath = path;
  }

  @override
  Future<String?> getScheduleTransferDestinationsJson() async =>
      scheduleTransferDestinationsJson;

  @override
  Future<void> setScheduleTransferDestinationsJson(String? json) async {
    scheduleTransferDestinationsJson = json;
  }
}
