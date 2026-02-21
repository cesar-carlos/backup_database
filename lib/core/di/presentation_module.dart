import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:get_it/get_it.dart';

/// Sets up presentation layer dependencies.
///
/// This module registers UI state management providers.
/// Providers are registered as factories since they may
/// be created multiple times for different widget trees.
Future<void> setupPresentationModule(GetIt getIt) async {
  // ========================================================================
  // PROVIDERS (State Management)
  // ========================================================================

  getIt.registerFactory<SchedulerProvider>(
    () => SchedulerProvider(
      repository: getIt<IScheduleRepository>(),
      schedulerService: getIt<ISchedulerService>(),
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
      emailNotificationTargetRepository:
          getIt<IEmailNotificationTargetRepository>(),
      emailTestAuditRepository: getIt<IEmailTestAuditRepository>(),
      oauthSmtpService: getIt<IOAuthSmtpService>(),
      testEmailConfiguration: getIt<TestEmailConfiguration>(),
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
      connectionManager: getIt<ConnectionManager>(),
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

  getIt.registerFactory<ServerCredentialProvider>(
    () => ServerCredentialProvider(
      getIt<IServerCredentialRepository>(),
      getIt<ISecureCredentialService>(),
    ),
  );

  getIt.registerFactory<ConnectedClientProvider>(
    () => ConnectedClientProvider(getIt<SocketServerService>()),
  );

  getIt.registerFactory<ConnectionLogProvider>(
    () => ConnectionLogProvider(getIt<IConnectionLogRepository>()),
  );

  getIt.registerFactory<RemoteSchedulesProvider>(
    () => RemoteSchedulesProvider(
      getIt<ConnectionManager>(),
      transferProvider: getIt<RemoteFileTransferProvider>(),
    ),
  );

  getIt.registerFactory<RemoteFileTransferProvider>(
    () => RemoteFileTransferProvider(
      getIt<ConnectionManager>(),
      getIt<IBackupDestinationRepository>(),
      getIt<ISendFileToDestinationService>(),
      getIt<TempDirectoryService>(),
      fileTransferDao: getIt<AppDatabase>().fileTransferDao,
    ),
  );

  getIt.registerFactory<ServerConnectionProvider>(
    () => ServerConnectionProvider(
      getIt<IServerConnectionRepository>(),
      getIt<ConnectionManager>(),
      getIt<IConnectionLogRepository>(),
    ),
  );
}
