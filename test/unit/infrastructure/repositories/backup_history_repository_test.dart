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

    test(
      'updateHistoryAndLogIfRunning atomically updates history and creates log',
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

        final logsResult = await logRepository.getByBackupHistory(history.id);
        expect(logsResult.isSuccess(), isTrue);
        final logs = logsResult.getOrNull()!;
        expect(logs.any((l) => l.message == 'Test error'), isTrue);
      },
    );
  });

  group('BackupHistoryRepository.reconcileStaleRunning', () {
    test(
      'NÃO sobrescreve histórico que já saiu de running (success), '
      'mesmo após cutoff',
      () async {
        // Cria histórico que JÁ está em status success mas startedAt
        // antigo (simula: backup terminou OK, mas crashou antes do
        // proxy/scheduler atualizar; agora reconcile vai escanear).
        final old = DateTime.now().subtract(const Duration(hours: 2));
        final history = BackupHistory(
          id: 'hist-success-old',
          scheduleId: 'sch-1',
          databaseName: 'Test',
          databaseType: 'sqlite',
          backupPath: '/tmp/backup.bak',
          fileSize: 1024,
          status: BackupStatus.success,
          startedAt: old,
          finishedAt: old.add(const Duration(minutes: 5)),
        );
        await repository.create(history);

        final result = await repository.reconcileStaleRunning(
          maxAge: const Duration(minutes: 30),
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 0, reason: 'success row must be untouched');

        final fetched = await repository.getById('hist-success-old');
        expect(fetched.getOrNull()!.status, BackupStatus.success);
      },
    );

    test(
      'marca running antigo como error (caminho feliz da reconciliação)',
      () async {
        final old = DateTime.now().subtract(const Duration(hours: 2));
        final history = BackupHistory(
          id: 'hist-running-old',
          scheduleId: 'sch-1',
          databaseName: 'Test',
          databaseType: 'sqlite',
          backupPath: '/tmp/backup.bak',
          fileSize: 1024,
          status: BackupStatus.running,
          startedAt: old,
        );
        // `create` preserva startedAt da entity — útil para reproduzir
        // backup-running antigo sem custom SQL.
        final createResult = await repository.create(history);
        expect(createResult.isSuccess(), isTrue);

        final result = await repository.reconcileStaleRunning(
          maxAge: const Duration(minutes: 30),
        );

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 1);

        final fetched = await repository.getById('hist-running-old');
        expect(fetched.getOrNull()!.status, BackupStatus.error);
      },
    );
  });
}
