import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;

class _MockProcessService extends Mock implements ProcessService {}

/// Cria diretório temporário único e o registra para cleanup.
Directory _makeTempDir(String prefix) {
  return Directory.systemTemp.createTempSync(prefix);
}

void main() {
  group('WindowsServiceService.ensureServiceEnvFileForTesting', () {
    late Directory appDir;
    late Directory configDir;
    late WindowsServiceService service;

    setUp(() {
      appDir = _makeTempDir('app_');
      configDir = _makeTempDir('config_');
      service = WindowsServiceService(_MockProcessService());
    });

    tearDown(() {
      try {
        if (appDir.existsSync()) {
          appDir.deleteSync(recursive: true);
        }
      } on Object catch (_) {}
      try {
        if (configDir.existsSync()) {
          configDir.deleteSync(recursive: true);
        }
      } on Object catch (_) {}
    });

    test('returns success when .env already exists in configDir', () async {
      File(p.join(configDir.path, '.env')).writeAsStringSync('EXISTING=1');

      final result = await service.ensureServiceEnvFileForTesting(
        appDir: appDir.path,
        configDirOverride: configDir.path,
      );

      expect(result.isSuccess(), isTrue);
      expect(
        File(p.join(configDir.path, '.env')).readAsStringSync(),
        equals('EXISTING=1'),
      );
    });

    test('copies .env from appDir when present', () async {
      File(p.join(appDir.path, '.env')).writeAsStringSync('FROM_APP=1');

      final result = await service.ensureServiceEnvFileForTesting(
        appDir: appDir.path,
        configDirOverride: configDir.path,
      );

      expect(result.isSuccess(), isTrue);
      expect(
        File(p.join(configDir.path, '.env')).readAsStringSync(),
        equals('FROM_APP=1'),
      );
    });

    test(
      'falls back to .env.example when .env not in appDir',
      () async {
        File(p.join(appDir.path, '.env.example')).writeAsStringSync(
          'TEMPLATE=1',
        );

        final result = await service.ensureServiceEnvFileForTesting(
          appDir: appDir.path,
          configDirOverride: configDir.path,
        );

        expect(result.isSuccess(), isTrue);
        expect(
          File(p.join(configDir.path, '.env')).readAsStringSync(),
          equals('TEMPLATE=1'),
        );
      },
    );

    test('prefers .env over .env.example when both present', () async {
      File(p.join(appDir.path, '.env')).writeAsStringSync('REAL=1');
      File(p.join(appDir.path, '.env.example')).writeAsStringSync('TEMPLATE=1');

      final result = await service.ensureServiceEnvFileForTesting(
        appDir: appDir.path,
        configDirOverride: configDir.path,
      );

      expect(result.isSuccess(), isTrue);
      expect(
        File(p.join(configDir.path, '.env')).readAsStringSync(),
        equals('REAL=1'),
      );
    });

    test(
      'returns ValidationFailure when no template available',
      () async {
        // appDir is empty (no .env nor .env.example)
        final result = await service.ensureServiceEnvFileForTesting(
          appDir: appDir.path,
          configDirOverride: configDir.path,
        );

        expect(result.isError(), isTrue);
        result.fold(
          (_) => fail('Expected failure when no template available'),
          (failure) {
            expect(failure, isA<ValidationFailure>());
            final msg = (failure as ValidationFailure).message;
            expect(msg, contains('.env'));
            expect(msg, contains('loop'));
          },
        );
      },
    );

    test(
      'creates configDir if missing before copying',
      () async {
        File(p.join(appDir.path, '.env')).writeAsStringSync('X=1');
        // Remove configDir to simulate fresh install
        configDir.deleteSync(recursive: true);
        final freshConfigDir = p.join(configDir.parent.path, 'fresh_config');

        final result = await service.ensureServiceEnvFileForTesting(
          appDir: appDir.path,
          configDirOverride: freshConfigDir,
        );

        expect(result.isSuccess(), isTrue);
        expect(Directory(freshConfigDir).existsSync(), isTrue);
        expect(File(p.join(freshConfigDir, '.env')).existsSync(), isTrue);

        Directory(freshConfigDir).deleteSync(recursive: true);
      },
    );
  });

  // Sanity check: registra fallback necessário caso o teste use
  // `any(named: 'timeout')` no futuro.
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(<String>[]);
  });
}
