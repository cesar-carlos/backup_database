import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/scheduler/cron_parser.dart';
import 'package:backup_database/infrastructure/external/system/system.dart';
import 'package:backup_database/infrastructure/repositories/repositories.dart';
import 'package:get_it/get_it.dart';

/// Sets up domain layer dependencies.
///
/// This module registers repositories, domain services,
/// and use cases. Dependencies from infrastructure are
/// provided here following the Dependency Inversion Principle.
Future<void> setupDomainModule(GetIt getIt) async {
  // ========================================================================
  // REPOSITORIES
  // ========================================================================

  // Config Repositories
  getIt.registerLazySingleton<ISqlServerConfigRepository>(
    () => SqlServerConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<ISybaseConfigRepository>(
    () => SybaseConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IPostgresConfigRepository>(
    () => PostgresConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );

  // Backup Repositories
  getIt.registerLazySingleton<IBackupDestinationRepository>(
    () => BackupDestinationRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IScheduleRepository>(
    () => ScheduleRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupHistoryRepository>(
    () => CachedBackupHistoryRepository(
      repository: BackupHistoryRepository(getIt<AppDatabase>()),
    ),
  );
  getIt.registerLazySingleton<IBackupLogRepository>(
    () => BackupLogRepository(getIt<AppDatabase>()),
  );

  // System Repositories
  getIt.registerLazySingleton<IEmailConfigRepository>(
    () => EmailConfigRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ILicenseRepository>(
    () => LicenseRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IServerCredentialRepository>(
    () => ServerCredentialRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IConnectionLogRepository>(
    () => ConnectionLogRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IServerConnectionRepository>(
    () => ServerConnectionRepository(getIt<AppDatabase>()),
  );

  // ========================================================================
  // DOMAIN SERVICES
  // ========================================================================

  getIt.registerLazySingleton<IBackupRunningState>(
    getIt.get<BackupProgressProvider>,
  );

  getIt.registerLazySingleton<IScheduleCalculator>(ScheduleCalculator.new);
  getIt.registerLazySingleton<IStorageChecker>(StorageChecker.new);
  getIt.registerLazySingleton<IFileValidator>(FileValidator.new);

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
    ),
  );
  getIt.registerLazySingleton<ValidateBackupDirectory>(
    ValidateBackupDirectory.new,
  );

  // Scheduling Use Cases
  getIt.registerLazySingleton<CreateSchedule>(
    () => CreateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
      getIt<IScheduleCalculator>(),
    ),
  );
  getIt.registerLazySingleton<UpdateSchedule>(
    () => UpdateSchedule(
      getIt<IScheduleRepository>(),
      getIt<ISchedulerService>(),
      getIt<IScheduleCalculator>(),
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
