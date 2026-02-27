import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/domain/use_cases/scheduling/execute_scheduled_backup.dart';
import 'package:backup_database/domain/use_cases/scheduling/update_schedule.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class _MockSchedulerService extends Mock implements ISchedulerService {}

class _MockUpdateSchedule extends Mock implements UpdateSchedule {}

class _MockExecuteBackup extends Mock implements ExecuteScheduledBackup {}

class _MockProgressNotifier extends Mock implements IBackupProgressNotifier {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockDestinationRepository destinationRepository;
  late _MockLicensePolicyService licensePolicyService;
  late _MockSchedulerService schedulerService;
  late _MockUpdateSchedule updateSchedule;
  late _MockExecuteBackup executeBackup;
  late _MockProgressNotifier progressNotifier;
  late ScheduleMessageHandler handler;

  const scheduleId = 'schedule-1';
  final schedule = Schedule(
    id: scheduleId,
    name: 'Backup Diario',
    databaseConfigId: 'db-1',
    databaseType: DatabaseType.sqlServer,
    scheduleType: ScheduleType.daily.name,
    scheduleConfig: '{}',
    destinationIds: const ['dest-1'],
    backupFolder: r'C:\backup',
  );
  final destination = BackupDestination(
    id: 'dest-1',
    name: 'Local',
    type: DestinationType.local,
    config: '{"path":"C:/backup"}',
  );

  setUpAll(() {
    registerFallbackValue(schedule);
    registerFallbackValue(destination);
  });

  setUp(() {
    scheduleRepository = _MockScheduleRepository();
    destinationRepository = _MockDestinationRepository();
    licensePolicyService = _MockLicensePolicyService();
    schedulerService = _MockSchedulerService();
    updateSchedule = _MockUpdateSchedule();
    executeBackup = _MockExecuteBackup();
    progressNotifier = _MockProgressNotifier();

    when(() => progressNotifier.tryStartBackup()).thenReturn(true);
    when(() => progressNotifier.currentSnapshot).thenReturn(null);

    handler = ScheduleMessageHandler(
      scheduleRepository: scheduleRepository,
      destinationRepository: destinationRepository,
      licensePolicyService: licensePolicyService,
      schedulerService: schedulerService,
      updateSchedule: updateSchedule,
      executeBackup: executeBackup,
      progressNotifier: progressNotifier,
    );
  });

  tearDown(() {
    handler.dispose();
  });

  group('ScheduleMessageHandler remote bypass', () {
    test(
      'executeSchedule rejects when validateExecutionCapabilities fails',
      () async {
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => destinationRepository.getByIds(any()),
        ).thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(
            any(),
            any(),
          ),
        ).thenAnswer(
          (_) async => const rd.Failure(
            ValidationFailure(
              message: 'Backup diferencial requer licença',
            ),
          ),
        );

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        final message = createExecuteScheduleMessage(
          requestId: 1,
          scheduleId: scheduleId,
        );

        await handler.handle('client-1', message, sendToClient);

        expect(sentMessage, isNotNull);
        expect(
          sentMessage!.payload['error'],
          contains('Backup diferencial requer licença'),
        );
        verifyNever(() => executeBackup(any()));
      },
    );

    test(
      'executeSchedule proceeds when validateExecutionCapabilities succeeds',
      () async {
        when(
          () => scheduleRepository.getById(scheduleId),
        ).thenAnswer((_) async => rd.Success(schedule));
        when(
          () => destinationRepository.getByIds(any()),
        ).thenAnswer((_) async => rd.Success([destination]));
        when(
          () => licensePolicyService.validateExecutionCapabilities(
            any(),
            any(),
          ),
        ).thenAnswer((_) async => const rd.Success(rd.unit));
        when(() => executeBackup(scheduleId))
            .thenAnswer((_) async => const rd.Success(rd.unit));

        Message? sentMessage;
        Future<void> sendToClient(String clientId, Message msg) async {
          sentMessage = msg;
        }

        final message = createExecuteScheduleMessage(
          requestId: 1,
          scheduleId: scheduleId,
        );

        await handler.handle('client-1', message, sendToClient);

        expect(sentMessage, isNotNull);
        verify(() => executeBackup(scheduleId)).called(1);
      },
    );
  });
}
