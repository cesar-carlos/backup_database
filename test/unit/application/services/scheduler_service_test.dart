import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockBackupLogRepository extends Mock implements IBackupLogRepository {}

class _MockBackupOrchestratorService extends Mock
    implements BackupOrchestratorService {}

class _MockDestinationOrchestrator extends Mock
    implements IDestinationOrchestrator {}

class _MockBackupCleanupService extends Mock implements IBackupCleanupService {}

class _MockNotificationService extends Mock implements INotificationService {}

class _MockScheduleCalculator extends Mock implements IScheduleCalculator {}

class _MockBackupProgressNotifier extends Mock
    implements IBackupProgressNotifier {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockDestinationRepository destinationRepository;
  late _MockBackupHistoryRepository backupHistoryRepository;
  late _MockBackupLogRepository backupLogRepository;
  late _MockBackupOrchestratorService backupOrchestratorService;
  late _MockDestinationOrchestrator destinationOrchestrator;
  late _MockBackupCleanupService cleanupService;
  late _MockNotificationService notificationService;
  late _MockScheduleCalculator scheduleCalculator;
  late _MockBackupProgressNotifier progressNotifier;
  late SchedulerService service;
  late Directory tempDir;

  const scheduleId = 'schedule-1';

  setUpAll(() {
    registerFallbackValue(
      Schedule(
        id: 'fallback-schedule',
        name: 'Fallback',
        databaseConfigId: 'db-fallback',
        databaseType: DatabaseType.sqlServer,
        scheduleType: ScheduleType.daily,
        scheduleConfig: '{"hour": 0, "minute": 0}',
        destinationIds: const [],
        backupFolder: r'C:\temp',
      ),
    );
    registerFallbackValue(
      BackupHistory(
        id: 'fallback-history',
        scheduleId: 'fallback-schedule',
        databaseName: 'Fallback',
        databaseType: DatabaseType.sqlServer.name,
        backupPath: r'C:\temp\fallback.bak',
        fileSize: 1,
        status: BackupStatus.running,
        startedAt: DateTime(2026),
      ),
    );
  });

  Schedule buildSchedule() {
    return Schedule(
      id: scheduleId,
      name: 'Backup Diario',
      databaseConfigId: 'db-1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: ScheduleType.daily,
      scheduleConfig: '{"hour": 0, "minute": 0}',
      destinationIds: const [],
      backupFolder: tempDir.path,
    );
  }

  BackupHistory buildHistory() {
    return BackupHistory(
      id: 'history-1',
      scheduleId: scheduleId,
      databaseName: 'Backup Diario',
      databaseType: DatabaseType.sqlServer.name,
      backupPath: r'C:\temp\backup.bak',
      fileSize: 1024,
      status: BackupStatus.success,
      startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('scheduler_service_test_');

    scheduleRepository = _MockScheduleRepository();
    destinationRepository = _MockDestinationRepository();
    backupHistoryRepository = _MockBackupHistoryRepository();
    backupLogRepository = _MockBackupLogRepository();
    backupOrchestratorService = _MockBackupOrchestratorService();
    destinationOrchestrator = _MockDestinationOrchestrator();
    cleanupService = _MockBackupCleanupService();
    notificationService = _MockNotificationService();
    scheduleCalculator = _MockScheduleCalculator();
    progressNotifier = _MockBackupProgressNotifier();

    service = SchedulerService(
      scheduleRepository: scheduleRepository,
      destinationRepository: destinationRepository,
      backupHistoryRepository: backupHistoryRepository,
      backupLogRepository: backupLogRepository,
      backupOrchestratorService: backupOrchestratorService,
      destinationOrchestrator: destinationOrchestrator,
      cleanupService: cleanupService,
      notificationService: notificationService,
      scheduleCalculator: scheduleCalculator,
      progressNotifier: progressNotifier,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('SchedulerService concurrency and cancellation', () {
    test('rejects second executeNow while first is running', () async {
      final schedule = buildSchedule();
      final backupCompleter = Completer<rd.Result<BackupHistory>>();

      when(
        () => scheduleRepository.getById(scheduleId),
      ).thenAnswer((_) async => rd.Success(schedule));
      when(
        () => backupOrchestratorService.executeBackup(
          schedule: any(named: 'schedule'),
          outputDirectory: any(named: 'outputDirectory'),
        ),
      ).thenAnswer((_) => backupCompleter.future);

      final firstExecution = service.executeNow(scheduleId);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final secondResult = await service.executeNow(scheduleId);

      expect(secondResult.isError(), isTrue);
      expect(
        secondResult.exceptionOrNull().toString(),
        contains('Ja existe um backup em execucao'),
      );

      backupCompleter.complete(
        const rd.Failure(DatabaseFailure(message: 'falha forçada')),
      );
      await firstExecution;
    });

    test(
      'cancelExecution marks running schedule and execution ends as cancelled',
      () async {
        final schedule = buildSchedule();
        final history = buildHistory();
        final backupCompleter = Completer<rd.Result<BackupHistory>>();

        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => backupOrchestratorService.executeBackup(
            schedule: any(named: 'schedule'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) => backupCompleter.future);
        when(
          () => backupHistoryRepository.update(any()),
        ).thenAnswer((_) async => rd.Success(history));
        when(() => progressNotifier.failBackup(any())).thenReturn(null);

        final execution = service.executeNow(scheduleId);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        final cancelResult = await service.cancelExecution(scheduleId);
        expect(cancelResult.isSuccess(), isTrue);

        backupCompleter.complete(rd.Success(history));
        final executionResult = await execution;

        expect(executionResult.isError(), isTrue);
        expect(
          executionResult.exceptionOrNull().toString(),
          contains('Backup cancelado pelo usuario'),
        );
        verify(() => backupHistoryRepository.update(any())).called(1);
        verify(() => progressNotifier.failBackup(any())).called(1);
      },
    );

    test('cancelExecution fails when schedule is not running', () async {
      final result = await service.cancelExecution(scheduleId);

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString(),
        contains('Nao ha backup em execucao'),
      );
    });
  });
}
