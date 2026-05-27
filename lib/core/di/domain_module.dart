import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/license_policy_service.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:get_it/get_it.dart';

/// Sets up domain layer dependencies.
///
/// Registra serviços de domínio e casos de uso. Implementações de
/// repositório e adapters de infraestrutura ficam no módulo de
/// infraestrutura (`infrastructure_module.dart`).
Future<void> setupDomainModule(GetIt getIt) async {
  getIt.registerLazySingleton<TempDirectoryService>(
    () => TempDirectoryService(
      machineSettings: getIt<IMachineSettingsRepository>(),
    ),
  );

  // ========================================================================
  // DOMAIN SERVICES
  // ========================================================================

  getIt.registerLazySingleton<IBackupRunningState>(
    getIt.get<BackupProgressProvider>,
  );

  getIt.registerLazySingleton<ILicensePolicyService>(
    () => LicensePolicyService(
      licenseValidationService: getIt<ILicenseValidationService>(),
      metricsCollector: getIt<IMetricsCollector>(),
    ),
  );

  // ========================================================================
  // USE CASES
  // ========================================================================

  // Backup Use Cases
  getIt.registerLazySingleton<ExecuteSqlServerBackup>(
    () => ExecuteSqlServerBackup(getIt<ISqlServerBackupService>()),
  );
  getIt.registerLazySingleton<ExecuteSybaseBackup>(
    () => ExecuteSybaseBackup(getIt<ISybaseBackupService>()),
  );

  // Storage Use Cases
  getIt.registerLazySingleton<CheckDiskSpace>(
    () => CheckDiskSpace(getIt<IStorageChecker>()),
  );
  getIt.registerLazySingleton<ValidateBackupFile>(
    () => ValidateBackupFile(getIt<IFileValidator>()),
  );
  getIt.registerLazySingleton<GetDatabaseConfig>(
    () => GetDatabaseConfig(
      sqlServerConfigRepository: getIt<ISqlServerConfigRepository>(),
      sybaseConfigRepository: getIt<ISybaseConfigRepository>(),
      postgresConfigRepository: getIt<IPostgresConfigRepository>(),
      firebirdConfigRepository: getIt<IFirebirdConfigRepository>(),
    ),
  );
  getIt.registerLazySingleton<ValidateBackupDirectory>(
    ValidateBackupDirectory.new,
  );
  getIt.registerLazySingleton<ValidateSybaseLogBackupPreflight>(
    () => ValidateSybaseLogBackupPreflight(
      getIt<IBackupHistoryRepository>(),
    ),
  );
  getIt.registerLazySingleton<GetSybaseBackupHealth>(
    () => GetSybaseBackupHealth(getIt<IBackupHistoryRepository>()),
  );

  // Scheduling Use Cases
  getIt.registerLazySingleton<CreateSchedule>(
    () => CreateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
      getIt<IScheduleCalculator>(),
      getIt<ILicensePolicyService>(),
      getIt<IBackupDestinationRepository>(),
    ),
  );
  getIt.registerLazySingleton<UpdateSchedule>(
    () => UpdateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
      getIt<IScheduleCalculator>(),
      getIt<ILicensePolicyService>(),
      getIt<IBackupDestinationRepository>(),
      metricsCollector: getIt<IMetricsCollector>(),
    ),
  );
  getIt.registerLazySingleton<GetNextRunTime>(
    () => GetNextRunTime(getIt<IScheduleCalculator>()),
  );
  getIt.registerLazySingleton<DeleteSchedule>(
    () => DeleteSchedule(getIt<IScheduleRepository>()),
  );
  getIt.registerLazySingleton<ExecuteScheduledBackup>(
    () => ExecuteScheduledBackup(getIt<ISchedulerService>()),
  );

  // Notification Use Cases
  getIt.registerLazySingleton<SendEmailNotification>(
    () => SendEmailNotification(getIt<INotificationService>()),
  );
  getIt.registerLazySingleton<ConfigureEmail>(
    () => ConfigureEmail(getIt<IEmailConfigRepository>()),
  );
  getIt.registerLazySingleton<ListEmailConfigurations>(
    () => ListEmailConfigurations(getIt<IEmailConfigRepository>()),
  );
  getIt.registerLazySingleton<DeleteEmailConfiguration>(
    () => DeleteEmailConfiguration(getIt<IEmailConfigRepository>()),
  );
  getIt.registerLazySingleton<ListEmailNotificationTargets>(
    () => ListEmailNotificationTargets(
      getIt<IEmailNotificationTargetRepository>(),
    ),
  );
  getIt.registerLazySingleton<ConfigureEmailNotificationTarget>(
    () => ConfigureEmailNotificationTarget(
      getIt<IEmailNotificationTargetRepository>(),
    ),
  );
  getIt.registerLazySingleton<DeleteEmailNotificationTarget>(
    () => DeleteEmailNotificationTarget(
      getIt<IEmailNotificationTargetRepository>(),
    ),
  );
  getIt.registerLazySingleton<GetEmailNotificationProfiles>(
    () => GetEmailNotificationProfiles(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      targetRepository: getIt<IEmailNotificationTargetRepository>(),
    ),
  );
  getIt.registerLazySingleton<TestEmailConfiguration>(
    () => TestEmailConfiguration(getIt<INotificationService>()),
  );

  // Destination Use Cases
  getIt.registerLazySingleton<SendToLocal>(
    () => SendToLocal(getIt<ILocalDestinationService>()),
  );
  getIt.registerLazySingleton<SendToFtp>(
    () => SendToFtp(getIt<IFtpService>()),
  );
  getIt.registerLazySingleton<SendToGoogleDrive>(
    () => SendToGoogleDrive(getIt<IGoogleDriveDestinationService>()),
  );
  getIt.registerLazySingleton<SendToDropbox>(
    () => SendToDropbox(getIt<IDropboxDestinationService>()),
  );
  getIt.registerLazySingleton<SendToNextcloud>(
    () => SendToNextcloud(getIt<INextcloudDestinationService>()),
  );
  getIt.registerLazySingleton<CleanOldBackups>(
    () => CleanOldBackups(
      localService: getIt<ILocalDestinationService>(),
      ftpService: getIt<IFtpService>(),
      googleDriveService: getIt<IGoogleDriveDestinationService>(),
      dropboxService: getIt<IDropboxDestinationService>(),
      nextcloudService: getIt<INextcloudDestinationService>(),
    ),
  );
}
