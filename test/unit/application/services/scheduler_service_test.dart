import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/disk_space_info.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockStorageChecker extends Mock implements IStorageChecker {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockBackupOrchestratorService extends Mock
    implements BackupOrchestratorService {}

class _MockDestinationOrchestrator extends Mock
    implements IDestinationOrchestrator {}

class _MockBackupCleanupService extends Mock implements IBackupCleanupService {}

class _MockNotificationService extends Mock implements INotificationService {}

class _MockScheduleCalculator extends Mock implements IScheduleCalculator {}

class _MockBackupProgressNotifier extends Mock
    implements IBackupProgressNotifier {}

class _MockProcessService extends Mock implements ProcessService {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockDestinationRepository destinationRepository;
  late _MockBackupHistoryRepository backupHistoryRepository;
  late _MockBackupOrchestratorService backupOrchestratorService;
  late _MockDestinationOrchestrator destinationOrchestrator;
  late _MockBackupCleanupService cleanupService;
  late _MockNotificationService notificationService;
  late _MockScheduleCalculator scheduleCalculator;
  late _MockBackupProgressNotifier progressNotifier;
  late _MockStorageChecker storageChecker;
  late _MockProcessService processService;
  late _MockLicensePolicyService licensePolicyService;
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
        scheduleType: ScheduleType.daily.name,
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
    registerFallbackValue(
      BackupDestination(
        id: 'fallback-destination',
        name: 'Destino',
        type: DestinationType.local,
        config: '{"path":"C:/tmp"}',
      ),
    );
    registerFallbackValue(
      BackupLog(
        backupHistoryId: 'fallback-history',
        level: LogLevel.info,
        category: LogCategory.execution,
        message: 'fallback',
      ),
    );
  });

  Schedule buildSchedule() {
    return Schedule(
      id: scheduleId,
      name: 'Backup Diario',
      databaseConfigId: 'db-1',
      databaseType: DatabaseType.sqlServer,
      scheduleType: ScheduleType.daily.name,
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
    backupOrchestratorService = _MockBackupOrchestratorService();
    destinationOrchestrator = _MockDestinationOrchestrator();
    cleanupService = _MockBackupCleanupService();
    notificationService = _MockNotificationService();
    scheduleCalculator = _MockScheduleCalculator();
    progressNotifier = _MockBackupProgressNotifier();
    storageChecker = _MockStorageChecker();
    processService = _MockProcessService();

    when(
      () => storageChecker.checkSpace(any()),
    ).thenAnswer(
      (_) async => const rd.Success(
        DiskSpaceInfo(
          totalBytes: 10 * 1024 * 1024 * 1024,
          freeBytes: 5 * 1024 * 1024 * 1024,
          usedBytes: 5 * 1024 * 1024 * 1024,
          usedPercentage: 50,
        ),
      ),
    );
    when(() => processService.cancelByTag(any())).thenReturn(null);

    licensePolicyService = _MockLicensePolicyService();
    when(
      () => licensePolicyService.validateExecutionCapabilities(
        any(),
        any(),
      ),
    ).thenAnswer((_) async => const rd.Success(rd.unit));

    service = SchedulerService(
      scheduleRepository: scheduleRepository,
      destinationRepository: destinationRepository,
      backupHistoryRepository: backupHistoryRepository,
      backupOrchestratorService: backupOrchestratorService,
      destinationOrchestrator: destinationOrchestrator,
      cleanupService: cleanupService,
      notificationService: notificationService,
      scheduleCalculator: scheduleCalculator,
      progressNotifier: progressNotifier,
      storageChecker: storageChecker,
      licensePolicyService: licensePolicyService,
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
        contains('Já existe um backup em execução'),
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
          () => backupHistoryRepository.updateHistoryAndLogIfRunning(
            history: any(named: 'history'),
            logStep: any(named: 'logStep'),
            logLevel: LogLevel.warning,
            logMessage: any(named: 'logMessage'),
          ),
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
        verify(
          () => backupHistoryRepository.updateHistoryAndLogIfRunning(
            history: any(named: 'history'),
            logStep: any(named: 'logStep'),
            logLevel: LogLevel.warning,
            logMessage: any(named: 'logMessage'),
          ),
        ).called(1);
        verify(() => progressNotifier.failBackup(any())).called(1);
      },
    );

    test('cancelExecution fails when schedule is not running', () async {
      final result = await service.cancelExecution(scheduleId);

      expect(result.isError(), isTrue);
      expect(
        result.exceptionOrNull().toString(),
        contains('Não há backup em execução'),
      );
    });

    test(
      'executeNow falha quando espaco livre minimo nao e atendido',
      () async {
        final schedule = buildSchedule();

        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => storageChecker.checkSpace(any()),
        ).thenAnswer(
          (_) async => const rd.Success(
            DiskSpaceInfo(
              totalBytes: 10 * 1024 * 1024 * 1024,
              freeBytes: 100 * 1024 * 1024,
              usedBytes: 9900 * 1024 * 1024,
              usedPercentage: 99,
            ),
          ),
        );

        final result = await service.executeNow(scheduleId);

        expect(result.isError(), isTrue);
        expect(
          result.exceptionOrNull().toString(),
          contains('Espaço livre insuficiente na pasta de backup'),
        );
        verifyNever(
          () => backupOrchestratorService.executeBackup(
            schedule: any(named: 'schedule'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        );
      },
    );
  });

  group('SchedulerService notifications', () {
    test(
      'executeNow notifies completion on successful scheduled backup',
      () async {
        final schedule = buildSchedule();
        final backupPath = '${tempDir.path}${Platform.pathSeparator}ok.bak';
        final backupFile = File(backupPath)..writeAsStringSync('backup');
        final history = BackupHistory(
          id: 'history-ok',
          scheduleId: schedule.id,
          databaseName: schedule.name,
          databaseType: schedule.databaseType.name,
          backupPath: backupFile.path,
          fileSize: 1024,
          status: BackupStatus.success,
          startedAt: DateTime.now().subtract(const Duration(seconds: 5)),
        );

        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => backupOrchestratorService.executeBackup(
            schedule: any(named: 'schedule'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) async => rd.Success(history));
        when(
          () => notificationService.notifyBackupComplete(any()),
        ).thenAnswer((_) async => const rd.Success(true));
        when(
          () => destinationOrchestrator.uploadToAllDestinations(
            sourceFilePath: any(named: 'sourceFilePath'),
            destinations: any(named: 'destinations'),
            isCancelled: any(named: 'isCancelled'),
            backupId: any(named: 'backupId'),
          ),
        ).thenAnswer((invocation) async {
          final dests = invocation.namedArguments[#destinations]
              as List<BackupDestination>;
          return List.generate(
            dests.length,
            (_) => const rd.Success(()),
          );
        });
        when(
          () => cleanupService.cleanOldBackups(
            destinations: any(named: 'destinations'),
            backupHistoryId: any(named: 'backupHistoryId'),
            schedule: any(named: 'schedule'),
          ),
        ).thenAnswer((_) async => const rd.Success(rd.unit));
        when(
          () => scheduleCalculator.getNextRunTime(any()),
        ).thenReturn(DateTime.now().add(const Duration(days: 1)));
        when(
          () => scheduleRepository.update(any()),
        ).thenAnswer((_) async => rd.Success(schedule));

        final result = await service.executeNow(scheduleId);

        expect(result.isSuccess(), isTrue);
        verify(
          () => notificationService.notifyBackupComplete(history),
        ).called(1);
        verify(() => licensePolicyService.setRunContext(any())).called(1);
        verify(() => licensePolicyService.clearRunContext()).called(1);
      },
    );

    test(
      'executeNow notifies with error history when upload fails for destination',
      () async {
        final destination = BackupDestination(
          id: 'dest-1',
          name: 'Local',
          type: DestinationType.local,
          config: '{"path":"D:/dest"}',
        );
        final schedule = buildSchedule().copyWith(
          destinationIds: [destination.id],
        );
        final backupPath = '${tempDir.path}${Platform.pathSeparator}error.bak';
        final backupFile = File(backupPath)..writeAsStringSync('backup');
        final history = BackupHistory(
          id: 'history-error',
          scheduleId: schedule.id,
          databaseName: schedule.name,
          databaseType: schedule.databaseType.name,
          backupPath: backupFile.path,
          fileSize: 2048,
          status: BackupStatus.success,
          startedAt: DateTime.now().subtract(const Duration(seconds: 10)),
        );

        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => destinationRepository.getByIds(any()),
        ).thenAnswer((_) async => rd.Success([destination]));
        when(
          () => backupOrchestratorService.executeBackup(
            schedule: any(named: 'schedule'),
            outputDirectory: any(named: 'outputDirectory'),
          ),
        ).thenAnswer((_) async => rd.Success(history));
        when(
          () => destinationOrchestrator.uploadToAllDestinations(
            sourceFilePath: any(named: 'sourceFilePath'),
            destinations: any(named: 'destinations'),
            isCancelled: any(named: 'isCancelled'),
            backupId: any(named: 'backupId'),
          ),
        ).thenAnswer(
          (_) async => [
            const rd.Failure(
              ValidationFailure(message: 'falha upload'),
            ),
          ],
        );
        when(
          () => backupHistoryRepository.updateHistoryAndLogIfRunning(
            history: any(named: 'history'),
            logStep: any(named: 'logStep'),
            logLevel: LogLevel.error,
            logMessage: any(named: 'logMessage'),
          ),
        ).thenAnswer((_) async => rd.Success(history));
        when(
          () => notificationService.notifyBackupComplete(any()),
        ).thenAnswer((_) async => const rd.Success(true));
        when(() => progressNotifier.failBackup(any())).thenReturn(null);

        final result = await service.executeNow(scheduleId);

        expect(result.isError(), isTrue);
        final capturedHistory =
            verify(
                  () => notificationService.notifyBackupComplete(captureAny()),
                ).captured.single
                as BackupHistory;
        expect(capturedHistory.status, BackupStatus.error);
        expect(
          capturedHistory.errorMessage,
          contains('falhou ao enviar para destinos'),
        );
      },
    );
  });
}
