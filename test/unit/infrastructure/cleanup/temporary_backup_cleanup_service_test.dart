import 'dart:io';

import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/infrastructure/cleanup/temporary_backup_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'temporary_backup_cleanup_service_test_',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  BackupHistory history({
    required String id,
    required String path,
    required BackupStatus status,
    required DateTime startedAt,
    DateTime? finishedAt,
    String? errorMessage,
  }) {
    return BackupHistory(
      id: id,
      databaseName: 'db',
      databaseType: 'sqlServer',
      backupPath: path,
      fileSize: 0,
      status: status,
      startedAt: startedAt,
      finishedAt: finishedAt,
      errorMessage: errorMessage,
    );
  }

  test('removes old failed upload artifact and reports bytes', () async {
    final now = DateTime(2026, 5, 22, 12);
    final backupFile = File(p.join(tempDir.path, 'backup.bak'));
    await backupFile.writeAsString('12345');
    await backupFile.setLastModified(now.subtract(const Duration(days: 2)));

    final repo = _FakeBackupHistoryRepository([
      history(
        id: 'h1',
        path: backupFile.path,
        status: BackupStatus.error,
        startedAt: now.subtract(const Duration(days: 2)),
        finishedAt: now.subtract(const Duration(hours: 25)),
        errorMessage: 'Backup concluido, mas falhou ao enviar para destinos',
      ),
    ]);
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: repo,
      temporaryRoots: () async => [tempDir.path],
      isBackupActive: () => false,
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 1);
    expect(result.bytesFreed, 5);
    expect(await backupFile.exists(), isFalse);
  });

  test(
    'never recursively deletes an ancestor of another temporary root',
    () async {
      final now = DateTime.now().add(const Duration(days: 3));
      final parent = await Directory(p.join(tempDir.path, 'old_backup'))
          .create();
      final nestedRoot = await Directory(p.join(parent.path, 'other_schedule'))
          .create();
      final file = await File(p.join(nestedRoot.path, 'keep.bak'))
          .writeAsString('keep');
      final service = TemporaryBackupCleanupService(
        backupHistoryRepository: _FakeBackupHistoryRepository([
          history(
            id: 'h',
            path: parent.path,
            status: BackupStatus.error,
            startedAt: now.subtract(const Duration(days: 2)),
          ),
        ]),
        temporaryRoots: () async => [tempDir.path, nestedRoot.path],
        isBackupActive: () => false,
        clock: () => now,
      );
      expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
      expect(await file.exists(), isTrue);
    },
  );

  test('protects physical destination configured through an alias', () async {
    final now = DateTime.now().add(const Duration(days: 3));
    final target = await Directory(p.join(tempDir.path, 'destination'))
        .create();
    final alias = p.join(tempDir.path, 'alias');
    final file = await File(p.join(target.path, 'keep.bak'))
        .writeAsString('keep');
    if (Platform.isWindows) {
      // Both junction paths are created inside this test's private directory.
      expect(p.isWithin(tempDir.path, alias), isTrue);
      expect(p.isWithin(tempDir.path, target.path), isTrue);
      final result = await Process.run('cmd', [
        '/c',
        'mklink',
        '/J',
        alias,
        target.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    } else {
      await Link(alias).create(target.path);
    }
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: _FakeBackupHistoryRepository([
        history(
          id: 'h',
          path: file.path,
          status: BackupStatus.success,
          startedAt: now.subtract(const Duration(days: 2)),
        ),
      ]),
      temporaryRoots: () async => [tempDir.path],
      protectedRoots: () async => [alias],
      isBackupActive: () => false,
      clock: () => now,
    );
    expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
    expect(await file.exists(), isTrue);
  });

  for (final directory in [false, true]) {
    test(
      'revalidates ${directory ? 'directory children' : 'file'} modified during inspection',
      () async {
        final now = DateTime.now().add(const Duration(days: 3));
        final folder = await Directory(p.join(tempDir.path, 'artifact'))
            .create();
        final file = await File(p.join(folder.path, 'backup.bak'))
            .writeAsString('keep');
        var checks = 0;
        final service = TemporaryBackupCleanupService(
          backupHistoryRepository: _FakeBackupHistoryRepository([
            history(
              id: 'h',
              path: directory ? folder.path : file.path,
              status: BackupStatus.success,
              startedAt: now.subtract(const Duration(days: 2)),
            ),
          ]),
          temporaryRoots: () async => [tempDir.path],
          isBackupActive: () {
            if (++checks == 2) file.setLastModifiedSync(now);
            return false;
          },
          clock: () => now,
        );
        expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
        expect(await file.exists(), isTrue);
      },
    );
  }

  test(
    'relative history paths cannot become deletion targets via cwd',
    () async {
      final now = DateTime.now().add(const Duration(days: 3));
      // Use the working directory's drive: Windows cannot relativize C: to D:.
      final testRoot = await Directory(
        p.join(Directory.current.path, '.dart_tool'),
      ).createTemp('retention_relative_');
      addTearDown(() async {
        expect(
          p.isWithin(
            p.join(Directory.current.path, '.dart_tool'),
            testRoot.path,
          ),
          isTrue,
        );
        await testRoot.delete(recursive: true);
      });
      final file = await File(p.join(testRoot.path, 'keep.bak'))
          .writeAsString('keep');
      expect(p.isRelative(p.relative(file.path)), isTrue);
      final service = TemporaryBackupCleanupService(
        backupHistoryRepository: _FakeBackupHistoryRepository([
          history(
            id: 'h',
            path: p.relative(file.path),
            status: BackupStatus.error,
            startedAt: now.subtract(const Duration(days: 2)),
          ),
        ]),
        temporaryRoots: () async => [testRoot.path],
        isBackupActive: () => false,
        clock: () => now,
      );
      expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
      expect(await file.exists(), isTrue);
    },
  );

  for (final status in BackupStatus.values) {
    test(
      'cleans abandoned artifact after interruption with status $status',
      () async {
        final now = DateTime.now();
        final old = now.subtract(const Duration(days: 2));
        final file = File(p.join(tempDir.path, 'abandoned.bak'));
        await file.writeAsString('backup');
        await file.setLastModified(old);
        final service = TemporaryBackupCleanupService(
          backupHistoryRepository: _FakeBackupHistoryRepository([
            history(
              id: 'crashed',
              path: file.path,
              status: status,
              startedAt: old,
            ),
          ]),
          temporaryRoots: () async => [tempDir.path],
          isBackupActive: () => false,
          clock: () => now,
        );
        expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 1);
        expect(await file.exists(), isFalse);
      },
    );
  }

  for (final scenario in [
    'active',
    'recent_file',
    'outside',
    'destination',
    'root',
    'type_root',
  ]) {
    test('preserves $scenario even with stale history', () async {
      final now = DateTime.now().add(
        Duration(days: scenario == 'root' || scenario == 'type_root' ? 3 : 0),
      );
      final old = now.subtract(const Duration(days: 2));
      final file = File(p.join(tempDir.path, 'keep.bak'));
      await file.writeAsString('keep');
      if (scenario != 'recent_file') await file.setLastModified(old);
      final target = scenario == 'root'
          ? tempDir.path
          : scenario == 'type_root'
          ? p.join(tempDir.path, 'Full')
          : file.path;
      if (scenario == 'type_root') await Directory(target).create();
      final service = TemporaryBackupCleanupService(
        backupHistoryRepository: _FakeBackupHistoryRepository([
          history(
            id: 'h',
            path: target,
            status: BackupStatus.error,
            startedAt: old,
            errorMessage: 'upload',
          ),
        ]),
        temporaryRoots: () async => [
          if (scenario == 'outside')
            p.join(tempDir.path, 'other')
          else
            tempDir.path,
        ],
        protectedRoots: () async => [
          if (scenario == 'destination') tempDir.path,
        ],
        isBackupActive: () => scenario == 'active',
        clock: () => now,
      );
      expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
      expect(await file.exists(), isTrue);
    });
  }

  test(
    'rechecks activity after scanning before deleting an artifact',
    () async {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 2));
      final file = File(p.join(tempDir.path, 'active.bak'));
      await file.writeAsString('keep');
      await file.setLastModified(old);
      var checks = 0;
      final service = TemporaryBackupCleanupService(
        backupHistoryRepository: _FakeBackupHistoryRepository([
          history(
            id: 'h',
            path: file.path,
            status: BackupStatus.success,
            startedAt: old,
          ),
        ]),
        temporaryRoots: () async => [tempDir.path],
        isBackupActive: () => ++checks > 1,
        clock: () => now,
      );
      expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
      expect(await file.exists(), isTrue);
    },
  );

  test(
    'recent reference protects an old file also referenced by an older history',
    () async {
      final now = DateTime.now();
      final old = now.subtract(const Duration(days: 3));
      final file = File(p.join(tempDir.path, 'retry.bak'));
      await file.writeAsString('retry');
      await file.setLastModified(old);
      final service = TemporaryBackupCleanupService(
        backupHistoryRepository: _FakeBackupHistoryRepository([
          history(
            id: 'old',
            path: file.path,
            status: BackupStatus.error,
            startedAt: old,
          ),
          history(
            id: 'retry',
            path: file.path,
            status: BackupStatus.running,
            startedAt: now,
          ),
        ]),
        temporaryRoots: () async => [tempDir.path],
        isBackupActive: () => false,
        clock: () => now,
      );
      expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
      expect(await file.exists(), isTrue);
    },
  );

  test('keeps recent failed upload artifact', () async {
    final now = DateTime(2026, 5, 22, 12);
    final backupFile = File(p.join(tempDir.path, 'recent.bak'));
    await backupFile.writeAsString('12345');
    await backupFile.setLastModified(now.subtract(const Duration(days: 2)));

    final repo = _FakeBackupHistoryRepository([
      history(
        id: 'h1',
        path: backupFile.path,
        status: BackupStatus.error,
        startedAt: now.subtract(const Duration(hours: 2)),
        finishedAt: now.subtract(const Duration(hours: 1)),
        errorMessage: 'Falha ao enviar backup para destinos',
      ),
    ]);
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: repo,
      temporaryRoots: () async => [tempDir.path],
      isBackupActive: () => false,
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 0);
    expect(await backupFile.exists(), isTrue);
  });

  test('cleans abandoned success and generic error artifacts', () async {
    final now = DateTime(2026, 5, 22, 12);
    final successFile = File(p.join(tempDir.path, 'success.bak'));
    final dbFailureFile = File(p.join(tempDir.path, 'db_failure.bak'));
    await successFile.writeAsString('ok');
    await dbFailureFile.writeAsString('db');
    await successFile.setLastModified(now.subtract(const Duration(days: 2)));
    await dbFailureFile.setLastModified(now.subtract(const Duration(days: 2)));

    final repo = _FakeBackupHistoryRepository([
      history(
        id: 'h1',
        path: successFile.path,
        status: BackupStatus.success,
        startedAt: now.subtract(const Duration(days: 2)),
      ),
      history(
        id: 'h2',
        path: dbFailureFile.path,
        status: BackupStatus.error,
        startedAt: now.subtract(const Duration(days: 2)),
        errorMessage: 'Erro no backup agendado: banco indisponivel',
      ),
    ]);
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: repo,
      temporaryRoots: () async => [tempDir.path],
      isBackupActive: () => false,
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 2);
    expect(await successFile.exists(), isFalse);
    expect(await dbFailureFile.exists(), isFalse);
  });

  test('recent child preserves an otherwise old backup directory', () async {
    final now = DateTime.now().add(const Duration(days: 3));
    final directory = await Directory(p.join(tempDir.path, 'writing')).create();
    final file = File(p.join(directory.path, 'segment.bak'));
    await file.writeAsString('recent');
    await file.setLastModified(now);
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: _FakeBackupHistoryRepository([
        history(
          id: 'h',
          path: directory.path,
          status: BackupStatus.error,
          startedAt: now.subtract(const Duration(days: 2)),
        ),
      ]),
      temporaryRoots: () async => [tempDir.path],
      isBackupActive: () => false,
      clock: () => now,
    );
    expect((await service.cleanupOrphanedFailedUploads()).deletedCount, 0);
    expect(await file.exists(), isTrue);
  });

  test('removes old failed upload directory recursively', () async {
    final now = DateTime.now().add(const Duration(days: 3));
    final backupDir = Directory(p.join(tempDir.path, 'backup_dir'));
    await backupDir.create();
    await File(p.join(backupDir.path, 'a.bak')).writeAsString('abc');
    await File(p.join(backupDir.path, 'b.bak')).writeAsString('de');

    final repo = _FakeBackupHistoryRepository([
      history(
        id: 'h1',
        path: backupDir.path,
        status: BackupStatus.error,
        startedAt: now.subtract(const Duration(days: 2)),
        errorMessage: 'Upload excedeu timeout de 240 minutos',
      ),
    ]);
    final service = TemporaryBackupCleanupService(
      backupHistoryRepository: repo,
      temporaryRoots: () async => [tempDir.path],
      isBackupActive: () => false,
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 1);
    expect(result.bytesFreed, 5);
    expect(await backupDir.exists(), isFalse);
  });
}

class _FakeBackupHistoryRepository implements IBackupHistoryRepository {
  _FakeBackupHistoryRepository(this.histories);

  final List<BackupHistory> histories;

  @override
  Future<rd.Result<List<BackupHistory>>> getByStatus(
    BackupStatus status,
  ) async {
    return rd.Success(histories.where((h) => h.status == status).toList());
  }

  @override
  Future<rd.Result<BackupHistory>> create(BackupHistory history) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<void>> delete(String id) => throw UnimplementedError();

  @override
  Future<rd.Result<int>> deleteOlderThan(DateTime date) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<List<BackupHistory>>> getAll({int? limit, int? offset}) =>
      Future.value(rd.Success(histories));

  @override
  Future<rd.Result<BackupHistory>> getById(String id) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<BackupHistory>> getByRunId(String runId) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<List<BackupHistory>>> getByDateRange(
    DateTime start,
    DateTime end,
  ) => throw UnimplementedError();

  @override
  Future<rd.Result<List<BackupHistory>>> getBySchedule(String scheduleId) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<BackupHistory>> getLastBySchedule(String scheduleId) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<int>> reconcileStaleRunning({required Duration maxAge}) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<BackupHistory>> update(BackupHistory history) =>
      throw UnimplementedError();

  @override
  Future<rd.Result<BackupHistory>> updateHistoryAndLogIfRunning({
    required BackupHistory history,
    required String logStep,
    required LogLevel logLevel,
    required String logMessage,
    String? logDetails,
  }) => throw UnimplementedError();

  @override
  Future<rd.Result<BackupHistory>> updateIfRunning(BackupHistory history) =>
      throw UnimplementedError();
}
