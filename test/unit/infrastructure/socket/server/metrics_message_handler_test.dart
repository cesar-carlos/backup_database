import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_running_state.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/utils/staging_usage_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockBackupHistoryRepository extends Mock
    implements IBackupHistoryRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockBackupRunningState extends Mock implements IBackupRunningState {}

void main() {
  late _MockBackupHistoryRepository historyRepo;
  late _MockScheduleRepository scheduleRepo;
  late _MockBackupRunningState runningState;
  late RemoteExecutionRegistry registry;

  setUp(() {
    historyRepo = _MockBackupHistoryRepository();
    scheduleRepo = _MockScheduleRepository();
    runningState = _MockBackupRunningState();
    registry = RemoteExecutionRegistry();

    when(() => historyRepo.getAll(limit: any(named: 'limit')))
        .thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(() => historyRepo.getByDateRange(any(), any()))
        .thenAnswer((_) async => const rd.Success(<BackupHistory>[]));
    when(() => scheduleRepo.getEnabled())
        .thenAnswer((_) async => const rd.Success(<Schedule>[]));
    when(() => runningState.isRunning).thenReturn(false);
    when(() => runningState.currentBackupName).thenReturn(null);
  });

  Future<Map<String, dynamic>> captureMetricsPayload(
    MetricsMessageHandler handler,
  ) async {
    Message? sent;
    Future<void> capture(String clientId, Message msg) async {
      sent = msg;
    }

    await handler.handle(
      'client-1',
      createMetricsRequestMessage(),
      capture,
    );

    expect(sent, isNotNull);
    expect(sent!.header.type, MessageType.metricsResponse);
    return sent!.payload;
  }

  group('MetricsMessageHandler enriquecido (M5.3 / M7.1)', () {
    test('publica serverTimeUtc em todos os payloads', () async {
      final fixedClock = DateTime.utc(2026, 4, 19, 15, 30);
      final handler = MetricsMessageHandler(
        backupHistoryRepository: historyRepo,
        scheduleRepository: scheduleRepo,
        backupRunningState: runningState,
        clock: () => fixedClock,
      );

      final payload = await captureMetricsPayload(handler);
      expect(payload['serverTimeUtc'], '2026-04-19T15:30:00.000Z');
    });

    test(
      'sem RemoteExecutionRegistry: nao publica activeRunId nem activeRunCount',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload.containsKey('activeRunId'), isFalse);
        expect(payload.containsKey('activeRunCount'), isFalse);
      },
    );

    test(
      'com registry vazio: publica activeRunCount=0 e omite activeRunId',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          executionRegistry: registry,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['activeRunCount'], 0);
        expect(payload.containsKey('activeRunId'), isFalse);
      },
    );

    test(
      'com 1 execucao ativa: publica activeRunId + activeRunCount=1',
      () async {
        registry.register(
          runId: registry.generateRunId('schedule-X'),
          scheduleId: 'schedule-X',
          clientId: 'client-A',
          requestId: 1,
          sendToClient: (clientId, msg) async {},
        );

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          executionRegistry: registry,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['activeRunCount'], 1);
        expect(payload['activeRunId'], startsWith('schedule-X_'));
      },
    );

    test(
      'sem stagingUsageBytesProvider: nao publica o campo',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload.containsKey('stagingUsageBytes'), isFalse);
      },
    );

    test(
      'com stagingUsageBytesProvider: publica valor retornado',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async => 1234567,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageBytes'], 1234567);
        expect(
          payload['stagingUsageWarnThresholdBytes'],
          StagingUsagePolicy.warnThresholdBytes,
        );
        expect(
          payload['stagingUsageBlockThresholdBytes'],
          StagingUsagePolicy.blockThresholdBytes,
        );
        expect(payload['stagingUsageLevel'], 'ok');
      },
    );

    test(
      'stagingUsageLevel reflecte warn acima de 5 GiB',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async =>
              StagingUsagePolicy.warnThresholdBytes + 1,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageLevel'], 'warn');
      },
    );

    test(
      'com provider que retorna 0 (diretorio vazio): publica 0 explicitamente',
      () async {
        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
          stagingUsageBytesProvider: () async => 0,
        );

        final payload = await captureMetricsPayload(handler);
        expect(payload['stagingUsageBytes'], 0);
      },
    );

    test(
      'campos legados continuam presentes apos enriquecimento (zero regressao)',
      () async {
        when(() => runningState.isRunning).thenReturn(true);
        when(() => runningState.currentBackupName).thenReturn('Backup Diario');

        final handler = MetricsMessageHandler(
          backupHistoryRepository: historyRepo,
          scheduleRepository: scheduleRepo,
          backupRunningState: runningState,
        );

        final payload = await captureMetricsPayload(handler);
        // Campos pre-existentes
        expect(payload['totalBackups'], 0);
        expect(payload['backupsToday'], 0);
        expect(payload['failedToday'], 0);
        expect(payload['activeSchedules'], 0);
        expect(payload['recentBackups'], isA<List<dynamic>>());
        expect(payload['backupInProgress'], isTrue);
        expect(payload['backupScheduleName'], 'Backup Diario');
        // Campo novo (sempre publicado)
        expect(payload.containsKey('serverTimeUtc'), isTrue);
      },
    );
  });
}
