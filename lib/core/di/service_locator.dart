import 'package:dio/dio.dart';
import 'package:get_it/get_it.dart';

import '../utils/logger_service.dart';
import '../../infrastructure/http/api_client.dart';
import '../../infrastructure/datasources/local/database.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/services.dart';
import '../../infrastructure/repositories/repositories.dart';
import '../../infrastructure/external/external.dart';
import '../../domain/use_cases/use_cases.dart';
import '../../application/services/services.dart';
import '../../application/providers/providers.dart';

final getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  // Core
  getIt.registerLazySingleton<LoggerService>(() => LoggerService());

  // HTTP Client
  getIt.registerLazySingleton<Dio>(() => Dio());
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));

  // Database
  getIt.registerLazySingleton<AppDatabase>(() => AppDatabase());

  // Repositories
  getIt.registerLazySingleton<ISqlServerConfigRepository>(
    () => SqlServerConfigRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<ISybaseConfigRepository>(
    () => SybaseConfigRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IPostgresConfigRepository>(
    () => PostgresConfigRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupDestinationRepository>(
    () => BackupDestinationRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IScheduleRepository>(
    () => ScheduleRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupHistoryRepository>(
    () => BackupHistoryRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupLogRepository>(
    () => BackupLogRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IEmailConfigRepository>(
    () => EmailConfigRepository(getIt<AppDatabase>()),
  );

  // Process Services
  getIt.registerLazySingleton<ProcessService>(() => ProcessService());

  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISqlServerBackupService>(
    () => SqlServerBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISybaseBackupService>(
    () => SybaseBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<IPostgresBackupService>(
    () => PostgresBackupService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ICompressionService>(
    () => CompressionService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<ISqlScriptExecutionService>(
    () => SqlScriptExecutionService(getIt<ProcessService>()),
  );

  // Destination Services
  getIt.registerLazySingleton<LocalDestinationService>(
    () => LocalDestinationService(),
  );

  getIt.registerLazySingleton<FtpDestinationService>(
    () => FtpDestinationService(),
  );

  getIt.registerLazySingleton<GoogleAuthService>(() => GoogleAuthService());

  getIt.registerLazySingleton<GoogleDriveDestinationService>(
    () => GoogleDriveDestinationService(getIt<GoogleAuthService>()),
  );

  // Use Cases - Backup
  getIt.registerLazySingleton<ExecuteSqlServerBackup>(
    () => ExecuteSqlServerBackup(getIt<ISqlServerBackupService>()),
  );

  getIt.registerLazySingleton<ExecuteSybaseBackup>(
    () => ExecuteSybaseBackup(getIt<ISybaseBackupService>()),
  );

  // Use Cases - Destinations
  getIt.registerLazySingleton<SendToLocal>(
    () => SendToLocal(getIt<LocalDestinationService>()),
  );

  getIt.registerLazySingleton<SendToFtp>(
    () => SendToFtp(getIt<FtpDestinationService>()),
  );

  getIt.registerLazySingleton<SendToGoogleDrive>(
    () => SendToGoogleDrive(getIt<GoogleDriveDestinationService>()),
  );

  getIt.registerLazySingleton<CleanOldBackups>(
    () => CleanOldBackups(
      localService: getIt<LocalDestinationService>(),
      ftpService: getIt<FtpDestinationService>(),
      googleDriveService: getIt<GoogleDriveDestinationService>(),
    ),
  );

  // Note: CheckDiskSpace and ValidateBackupFile are instantiated directly as they have no dependencies

  // Email Service
  getIt.registerLazySingleton<EmailService>(() => EmailService());

  // Notification Service
  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      emailService: getIt<EmailService>(),
    ),
  );

  // Log Service
  getIt.registerLazySingleton<LogService>(
    () => LogService(getIt<IBackupLogRepository>()),
  );

  // Use Cases - Notifications
  getIt.registerLazySingleton<SendEmailNotification>(
    () => SendEmailNotification(getIt<NotificationService>()),
  );

  getIt.registerLazySingleton<ConfigureEmail>(
    () => ConfigureEmail(getIt<IEmailConfigRepository>()),
  );

  getIt.registerLazySingleton<TestEmailConfiguration>(
    () => TestEmailConfiguration(getIt<NotificationService>()),
  );

  // Orchestrator
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
      compressionService: getIt<ICompressionService>(),
      sqlScriptExecutionService: getIt<ISqlScriptExecutionService>(),
      notificationService: getIt<NotificationService>(),
    ),
  );

  // Scheduler
  getIt.registerLazySingleton<SchedulerService>(
    () => SchedulerService(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      backupOrchestratorService: getIt<BackupOrchestratorService>(),
      localDestinationService: getIt<LocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      ftpDestinationService: getIt<FtpDestinationService>(),
      googleDriveDestinationService: getIt<GoogleDriveDestinationService>(),
      notificationService: getIt<NotificationService>(),
    ),
  );

  // Windows Task Scheduler
  getIt.registerLazySingleton<ITaskSchedulerService>(
    () => WindowsTaskSchedulerService(),
  );

  // Auto Update Service
  getIt.registerLazySingleton<AutoUpdateService>(() => AutoUpdateService());

  // Use Cases - Scheduling
  getIt.registerLazySingleton<CreateSchedule>(
    () =>
        CreateSchedule(getIt<IScheduleRepository>(), getIt<SchedulerService>()),
  );

  getIt.registerLazySingleton<UpdateSchedule>(
    () =>
        UpdateSchedule(getIt<IScheduleRepository>(), getIt<SchedulerService>()),
  );

  getIt.registerLazySingleton<DeleteSchedule>(
    () => DeleteSchedule(getIt<IScheduleRepository>()),
  );

  getIt.registerLazySingleton<ExecuteScheduledBackup>(
    () => ExecuteScheduledBackup(getIt<SchedulerService>()),
  );

  // Providers
  getIt.registerLazySingleton<BackupProgressProvider>(
    () => BackupProgressProvider(),
  );

  getIt.registerFactory<SchedulerProvider>(
    () => SchedulerProvider(
      repository: getIt<IScheduleRepository>(),
      schedulerService: getIt<SchedulerService>(),
      createSchedule: getIt<CreateSchedule>(),
      updateSchedule: getIt<UpdateSchedule>(),
      deleteSchedule: getIt<DeleteSchedule>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressProvider: getIt<BackupProgressProvider>(),
    ),
  );

  getIt.registerFactory<LogProvider>(() => LogProvider(getIt<LogService>()));

  getIt.registerFactory<NotificationProvider>(
    () => NotificationProvider(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      notificationService: getIt<NotificationService>(),
    ),
  );

  getIt.registerFactory<SqlServerConfigProvider>(
    () => SqlServerConfigProvider(
      getIt<ISqlServerConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerFactory<SybaseConfigProvider>(
    () => SybaseConfigProvider(
      getIt<ISybaseConfigRepository>(),
      getIt<IScheduleRepository>(),
      getIt<ToolVerificationService>(),
    ),
  );

  getIt.registerFactory<PostgresConfigProvider>(
    () => PostgresConfigProvider(
      getIt<IPostgresConfigRepository>(),
      getIt<IScheduleRepository>(),
    ),
  );

  getIt.registerFactory<DestinationProvider>(
    () => DestinationProvider(
      getIt<IBackupDestinationRepository>(),
      getIt<IScheduleRepository>(),
    ),
  );

  getIt.registerFactory<DashboardProvider>(
    () => DashboardProvider(
      getIt<IBackupHistoryRepository>(),
      getIt<IScheduleRepository>(),
    ),
  );

  getIt.registerLazySingleton<GoogleAuthProvider>(
    () => GoogleAuthProvider(getIt<GoogleAuthService>()),
  );

  getIt.registerFactory<AutoUpdateProvider>(
    () => AutoUpdateProvider(autoUpdateService: getIt<AutoUpdateService>()),
  );
}
