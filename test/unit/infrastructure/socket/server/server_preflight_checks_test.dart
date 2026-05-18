import 'dart:io';

import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/domain/use_cases/storage/validate_backup_directory.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/server/server_preflight_checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockStorageChecker extends Mock implements IStorageChecker {}

void main() {
  late Directory tempStaging;
  late _MockStorageChecker storageChecker;

  setUp(() async {
    tempStaging = await Directory.systemTemp.createTemp(
      'preflight_staging_test_',
    );
    storageChecker = _MockStorageChecker();
  });

  tearDown(() async {
    if (await tempStaging.exists()) {
      await tempStaging.delete(recursive: true);
    }
  });

  Future<List<PreflightCheckResult>> runChecks() async {
    final checks = buildServerPreflightChecks(
      stagingBasePath: tempStaging.path,
      validateBackupDirectory: const ValidateBackupDirectory(),
      storageChecker: storageChecker,
    );
    final results = <PreflightCheckResult>[];
    for (final check in checks.values) {
      results.add(await check());
    }
    return results;
  }

  test('temp_dir_writable should pass for writable staging path', () async {
    when(
      () => storageChecker.checkSpace(any()),
    ).thenAnswer(
      (_) async => const rd.Success(
        DiskSpaceInfo(
          totalBytes: 100 * 1024 * 1024 * 1024,
          freeBytes: 50 * 1024 * 1024 * 1024,
          usedBytes: 50 * 1024 * 1024 * 1024,
          usedPercentage: 50,
        ),
      ),
    );

    final results = await runChecks();
    final writable = results.firstWhere((r) => r.name == 'temp_dir_writable');

    expect(writable.passed, isTrue);
    expect(writable.severity, PreflightSeverity.blocking);
  });

  test('disk_space should warn when free space below threshold', () async {
    when(
      () => storageChecker.checkSpace(tempStaging.path),
    ).thenAnswer(
      (_) async => const rd.Success(
        DiskSpaceInfo(
          totalBytes: 10 * 1024 * 1024 * 1024,
          freeBytes: 1024,
          usedBytes: 10 * 1024 * 1024 * 1024,
          usedPercentage: 99.9,
        ),
      ),
    );

    final results = await runChecks();
    final disk = results.firstWhere((r) => r.name == 'disk_space');

    expect(disk.passed, isFalse);
    expect(disk.severity, PreflightSeverity.warning);
  });

  test('compression_tool should include result', () async {
    when(
      () => storageChecker.checkSpace(any()),
    ).thenAnswer(
      (_) async => const rd.Success(
        DiskSpaceInfo(
          totalBytes: 10 * 1024 * 1024 * 1024,
          freeBytes: 10 * 1024 * 1024 * 1024,
          usedBytes: 0,
          usedPercentage: 0,
        ),
      ),
    );

    final results = await runChecks();
    final compression = results.firstWhere((r) => r.name == 'compression_tool');

    expect(compression.name, 'compression_tool');
    expect(
      compression.severity,
      anyOf(PreflightSeverity.info, PreflightSeverity.warning),
    );
  });
}
