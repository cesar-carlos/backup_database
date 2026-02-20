import 'package:backup_database/application/services/initial_setup_service.dart';
import 'package:backup_database/application/services/service_health_checker.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:get_it/get_it.dart';

/// Sets up application layer dependencies.
///
/// This module registers application services like
/// orchestrators, initial setup, and health checkers.
Future<void> setupApplicationModule(GetIt getIt) async {
  // ========================================================================
  // APPLICATION SERVICES
  // ========================================================================

  getIt.registerLazySingleton<INotificationService>(
    () => NotificationService(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      emailNotificationTargetRepository:
          getIt<IEmailNotificationTargetRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      emailService: getIt<IEmailService>(),
      licenseValidationService: getIt<ILicenseValidationService>(),
    ),
  );

  getIt.registerLazySingleton<ISendFileToDestinationService>(
    () => SendFileToDestinationService(
      localDestinationService: getIt<ILocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      sendToDropbox: getIt<SendToDropbox>(),
      sendToNextcloud: getIt<SendToNextcloud>(),
      licenseValidationService: getIt<ILicenseValidationService>(),
    ),
  );

  getIt.registerLazySingleton<BackupOrchestratorService>(
    () => BackupOrchestratorService(
      sqlServerConfigRepository: getIt<ISqlServerConfigRepository>(),
      sybaseConfigRepository: getIt<ISybaseConfigRepository>(),
      postgresConfigRepository: getIt<IPostgresConfigRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      sqlServerBackupService: getIt<ISqlServerBackupService>(),
      sybaseBackupService: getIt<ISybaseBackupService>(),
      postgresBackupService: getIt<IPostgresBackupService>(),
      compressionOrchestrator: getIt<IBackupCompressionOrchestrator>(),
      scriptOrchestrator: getIt<IBackupScriptOrchestrator>(),
      sqlScriptExecutionService: getIt<ISqlScriptExecutionService>(),
      notificationService: getIt<INotificationService>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
      getDatabaseConfig: getIt<GetDatabaseConfig>(),
      validateBackupDirectory: getIt<ValidateBackupDirectory>(),
    ),
  );

  getIt.registerLazySingleton<ISchedulerService>(
    () => SchedulerService(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      backupOrchestratorService: getIt<BackupOrchestratorService>(),
      destinationOrchestrator: getIt<IDestinationOrchestrator>(),
      cleanupService: getIt<IBackupCleanupService>(),
      notificationService: getIt<INotificationService>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
      transferStagingService: getIt<ITransferStagingService>(),
      scheduleCalculator: getIt<IScheduleCalculator>(),
    ),
  );

  // ========================================================================
  // SETUP & HEALTH
  // ========================================================================

  getIt.registerLazySingleton<InitialSetupService>(
    () => InitialSetupService(
      getIt<IServerCredentialRepository>(),
      getIt<ISecureCredentialService>(),
    ),
  );

  getIt.registerLazySingleton<ServiceHealthChecker>(
    () => ServiceHealthChecker(
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      processService: getIt<ProcessService>(),
    ),
  );
}
