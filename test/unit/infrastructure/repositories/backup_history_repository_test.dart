import 'package:backup_database/core/constants/log_step_constants.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/backup_history_repository.dart';
import 'package:backup_database/infrastructure/repositories/backup_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late BackupHistoryRepository repository;
  late BackupLogRepository logRepository;

  setUp(() {
    database = AppDatabase.inMemory();
    logRepository = BackupLogRepository(database);
    repository = BackupHistoryRepository(database, logRepository);
  });

  tearDown(() async {
    await database.close();
  });

  group('BackupHistoryRepository.updateIfRunning', () {
    test('rejects history with status running', () async {
      final history = BackupHistory(
        id: 'hist-1',
        scheduleId: 'sch-1',
        databaseName: 'Test',
        databaseType: 'sqlite',
        backupPath: '/tmp/backup.bak',
        fileSize: 1024,
        status: BackupStatus.running,
        startedAt: DateTime.now(),
      );

      final createResult = await repository.create(history);
      expect(createResult.isSuccess(), isTrue);

      final updateResult = await repository.updateIfRunning(history);

      expect(updateResult.isError(), isTrue);
      expect(
        updateResult.exceptionOrNull().toString(),
        contains('status terminal'),
      );
    });

    test('accepts history with status success', () async {
      final history = BackupHistory(
        id: 'hist-2',
        scheduleId: 'sch-1',
        databaseName: 'Test',
        databaseType: 'sqlite',
        backupPath: '/tmp/backup.bak',
        fileSize: 1024,
        status: BackupStatus.running,
        startedAt: DateTime.now(),
      );

      final createResult = await repository.create(history);
      expect(createResult.isSuccess(), isTrue);

      final updatedHistory = history.copyWith(
        status: BackupStatus.success,
        finishedAt: DateTime.now(),
        durationSeconds: 10,
      );

      final updateResult = await repository.updateIfRunning(updatedHistory);

      expect(updateResult.isSuccess(), isTrue);
      final result = updateResult.getOrNull()!;
      expect(result.status, BackupStatus.success);
    });

    test('updateHistoryAndLogIfRunning atomically updates history and creates log',
        () async {
      final history = BackupHistory(
        id: 'hist-3',
        scheduleId: 'sch-1',
        databaseName: 'Test',
        databaseType: 'sqlite',
        backupPath: '/tmp/backup.bak',
        fileSize: 1024,
        status: BackupStatus.running,
        startedAt: DateTime.now(),
      );

      final createResult = await repository.create(history);
      expect(createResult.isSuccess(), isTrue);

      final updatedHistory = history.copyWith(
        status: BackupStatus.error,
        errorMessage: 'Test error',
        finishedAt: DateTime.now(),
        durationSeconds: 5,
      );

      final updateResult = await repository.updateHistoryAndLogIfRunning(
        history: updatedHistory,
        logStep: LogStepConstants.backupError,
        logLevel: LogLevel.error,
        logMessage: 'Test error',
      );

      expect(updateResult.isSuccess(), isTrue);

      final logsResult =
          await logRepository.getByBackupHistory(history.id);
      expect(logsResult.isSuccess(), isTrue);
      final logs = logsResult.getOrNull()!;
      expect(logs.any((l) => l.message == 'Test error'), isTrue);
    });
  });
}
