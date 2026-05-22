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
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 1);
    expect(result.bytesFreed, 5);
    expect(await backupFile.exists(), isFalse);
  });

  test('keeps recent failed upload artifact', () async {
    final now = DateTime(2026, 5, 22, 12);
    final backupFile = File(p.join(tempDir.path, 'recent.bak'));
    await backupFile.writeAsString('12345');

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
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 0);
    expect(await backupFile.exists(), isTrue);
  });

  test('keeps non-error histories and non-upload failures', () async {
    final now = DateTime(2026, 5, 22, 12);
    final successFile = File(p.join(tempDir.path, 'success.bak'));
    final dbFailureFile = File(p.join(tempDir.path, 'db_failure.bak'));
    await successFile.writeAsString('ok');
    await dbFailureFile.writeAsString('db');

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
      clock: () => now,
    );

    final result = await service.cleanupOrphanedFailedUploads();

    expect(result.deletedCount, 0);
    expect(await successFile.exists(), isTrue);
    expect(await dbFailureFile.exists(), isTrue);
  });

  test('removes old failed upload directory recursively', () async {
    final now = DateTime(2026, 5, 22, 12);
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
      throw UnimplementedError();

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
