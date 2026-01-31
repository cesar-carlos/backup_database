import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/http/api_client.dart';
import 'package:backup_database/infrastructure/repositories/repositories.dart';
import 'package:backup_database/infrastructure/security/secure_credential_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';

final GetIt getIt = GetIt.instance;

Future<void> setupServiceLocator() async {
  getIt.registerLazySingleton<LoggerService>(LoggerService.new);
  getIt.registerLazySingleton<ClipboardService>(ClipboardService.new);

  getIt.registerLazySingleton<Dio>(Dio.new);
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));

  getIt.registerLazySingleton<AppDatabase>(AppDatabase.new);

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
  getIt.registerLazySingleton<ILicenseRepository>(
    () => LicenseRepository(getIt<AppDatabase>()),
  );

  getIt.registerLazySingleton<IDeviceKeyService>(DeviceKeyService.new);

  getIt.registerLazySingleton<ISecureCredentialService>(
    SecureCredentialService.new,
  );

  getIt.registerLazySingleton<ILicenseValidationService>(
    () => LicenseValidationService(
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
    ),
  );
  getIt.registerLazySingleton<LicenseGenerationService>(() {
    final secretKey =
        dotenv.env['LICENSE_SECRET_KEY'] ??
        'BACKUP_DATABASE_LICENSE_SECRET_2024';
    if (secretKey.isEmpty) {
      LoggerService.warning(
        'LICENSE_SECRET_KEY não configurada no .env, usando fallback',
      );
    }
    return LicenseGenerationService(secretKey: secretKey);
  });

  getIt.registerLazySingleton<ProcessService>(ProcessService.new);

  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );

  getIt.registerLazySingleton<IWindowsServiceService>(
    () => WindowsServiceService(getIt<ProcessService>()),
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

  getIt.registerLazySingleton<ILocalDestinationService>(
    LocalDestinationService.new,
  );

  getIt.registerLazySingleton<IFtpService>(
    FtpDestinationService.new,
  );

  getIt.registerLazySingleton<GoogleAuthService>(
    () => GoogleAuthService(getIt<ISecureCredentialService>()),
  );

  getIt.registerLazySingleton<IGoogleDriveDestinationService>(
    () => GoogleDriveDestinationService(getIt<GoogleAuthService>()),
  );

  getIt.registerLazySingleton<DropboxAuthService>(
    () => DropboxAuthService(getIt<ISecureCredentialService>()),
  );

  getIt.registerLazySingleton<IDropboxDestinationService>(
    () => DropboxDestinationService(getIt<DropboxAuthService>()),
  );

  getIt.registerLazySingleton<INextcloudDestinationService>(
    NextcloudDestinationService.new,
  );

  getIt.registerLazySingleton<ExecuteSqlServerBackup>(
    () => ExecuteSqlServerBackup(getIt<ISqlServerBackupService>()),
  );

  getIt.registerLazySingleton<ExecuteSybaseBackup>(
    () => ExecuteSybaseBackup(getIt<ISybaseBackupService>()),
  );

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

  getIt.registerLazySingleton<EmailService>(EmailService.new);

  getIt.registerLazySingleton<NotificationService>(
    () => NotificationService(
      emailConfigRepository: getIt<IEmailConfigRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      emailService: getIt<EmailService>(),
    ),
  );

  getIt.registerLazySingleton<LogService>(
    () => LogService(getIt<IBackupLogRepository>()),
  );

  getIt.registerLazySingleton<SendEmailNotification>(
    () => SendEmailNotification(getIt<NotificationService>()),
  );

  getIt.registerLazySingleton<ConfigureEmail>(
    () => ConfigureEmail(getIt<IEmailConfigRepository>()),
  );

  getIt.registerLazySingleton<TestEmailConfiguration>(
    () => TestEmailConfiguration(getIt<NotificationService>()),
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
      compressionService: getIt<ICompressionService>(),
      sqlScriptExecutionService: getIt<ISqlScriptExecutionService>(),
      notificationService: getIt<NotificationService>(),
    ),
  );

  getIt.registerLazySingleton<SchedulerService>(
    () => SchedulerService(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      backupOrchestratorService: getIt<BackupOrchestratorService>(),
      localDestinationService: getIt<ILocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      ftpDestinationService: getIt<IFtpService>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      dropboxDestinationService: getIt<IDropboxDestinationService>(),
      sendToDropbox: getIt<SendToDropbox>(),
      nextcloudDestinationService: getIt<INextcloudDestinationService>(),
      sendToNextcloud: getIt<SendToNextcloud>(),
      notificationService: getIt<NotificationService>(),
      licenseValidationService: getIt<ILicenseValidationService>(),
    ),
  );

  getIt.registerLazySingleton<ITaskSchedulerService>(
    WindowsTaskSchedulerService.new,
  );

  getIt.registerLazySingleton<AutoUpdateService>(AutoUpdateService.new);

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

  getIt.registerLazySingleton<BackupProgressProvider>(
    BackupProgressProvider.new,
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

  getIt.registerLazySingleton<DropboxAuthProvider>(
    () => DropboxAuthProvider(getIt<DropboxAuthService>()),
  );

  getIt.registerFactory<AutoUpdateProvider>(
    () => AutoUpdateProvider(autoUpdateService: getIt<AutoUpdateService>()),
  );

  getIt.registerFactory<LicenseProvider>(
    () => LicenseProvider(
      validationService: getIt<ILicenseValidationService>(),
      generationService: getIt<LicenseGenerationService>(),
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
    ),
  );

  getIt.registerFactory<WindowsServiceProvider>(
    () => WindowsServiceProvider(getIt<IWindowsServiceService>()),
  );
}
