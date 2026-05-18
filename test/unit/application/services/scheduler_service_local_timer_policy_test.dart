import 'package:backup_database/application/services/backup_orchestrator_service.dart';
import 'package:backup_database/application/services/scheduler_service.dart';
import 'package:backup_database/core/constants/backup_constants.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_backup_cleanup_service.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:backup_database/domain/services/i_schedule_calculator.dart';
import 'package:backup_database/domain/services/i_storage_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

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

class _MockStorageChecker extends Mock implements IStorageChecker {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

class _MockUserPreferencesRepository extends Mock
    implements IUserPreferencesRepository {}

void main() {
  late _MockScheduleRepository scheduleRepository;
  late _MockBackupHistoryRepository backupHistoryRepository;
  late _MockUserPreferencesRepository userPreferencesRepository;
  late SchedulerService service;

  setUp(() {
    scheduleRepository = _MockScheduleRepository();
    backupHistoryRepository = _MockBackupHistoryRepository();
    userPreferencesRepository = _MockUserPreferencesRepository();

    when(() => scheduleRepository.getEnabled()).thenAnswer(
      (_) async => const rd.Success(<Schedule>[]),
    );
    when(
      () => scheduleRepository.getEnabledDueForExecution(any()),
    ).thenAnswer((_) async => const rd.Success(<Schedule>[]));
    when(
      () => userPreferencesRepository.getLocalScheduleTimerEnabled(),
    ).thenAnswer((_) async => false);
    when(
      () => backupHistoryRepository.reconcileStaleRunning(
        maxAge: BackupConstants.staleRunningBackupMaxAge,
      ),
    ).thenAnswer((_) async => const rd.Success(0));

    service = SchedulerService(
      scheduleRepository: scheduleRepository,
      destinationRepository: _MockDestinationRepository(),
      backupHistoryRepository: backupHistoryRepository,
      backupOrchestratorService: _MockBackupOrchestratorService(),
      destinationOrchestrator: _MockDestinationOrchestrator(),
      cleanupService: _MockBackupCleanupService(),
      notificationService: _MockNotificationService(),
      scheduleCalculator: _MockScheduleCalculator(),
      progressNotifier: _MockBackupProgressNotifier(),
      storageChecker: _MockStorageChecker(),
      licensePolicyService: _MockLicensePolicyService(),
      userPreferencesRepository: userPreferencesRepository,
    );
  });

  test(
    'start skips periodic timer when local schedule timer preference is false',
    () async {
      await service.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      verify(() => scheduleRepository.getEnabled()).called(1);
      verifyNever(() => scheduleRepository.getEnabledDueForExecution(any()));
    },
  );
}
