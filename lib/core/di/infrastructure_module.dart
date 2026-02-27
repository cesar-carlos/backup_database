import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/cleanup/backup_cleanup_service_impl.dart';
import 'package:backup_database/infrastructure/compression/backup_compression_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/destination/destination_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/scripts/backup_script_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:backup_database/infrastructure/transfer_staging_service.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Sets up infrastructure layer dependencies.
///
/// This module registers external services, process services,
/// backup services, destination services, and socket server components.
Future<void> setupInfrastructureModule(GetIt getIt) async {
  // ========================================================================
  // PROCESS & EXTERNAL SERVICES
  // ========================================================================

  getIt.registerLazySingleton<ProcessService>(ProcessService.new);
  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<IWindowsServiceService>(
    () => WindowsServiceService(
      getIt<ProcessService>(),
      metricsCollector: getIt<IMetricsCollector>(),
    ),
  );

  // ========================================================================
  // BACKUP SERVICES
  // ========================================================================

  getIt.registerLazySingleton<ISqlServerBackupService>(
    () => SqlServerBackupService(getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<SybaseConnectionStrategyCache>(
    SybaseConnectionStrategyCache.new,
  );
  getIt.registerLazySingleton<ISybaseBackupService>(
    () => SybaseBackupService(
      getIt<ProcessService>(),
      strategyCache: getIt<SybaseConnectionStrategyCache>(),
    ),
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

  // ========================================================================
  // ORCHESTRATORS
  // ========================================================================

  getIt.registerLazySingleton<IBackupCompressionOrchestrator>(
    () => BackupCompressionOrchestratorImpl(
      compressionService: getIt<ICompressionService>(),
    ),
  );
  getIt.registerLazySingleton<IBackupScriptOrchestrator>(
    BackupScriptOrchestratorImpl.new,
  );
  getIt.registerLazySingleton<CircuitBreakerRegistry>(
    CircuitBreakerRegistry.new,
  );
  getIt.registerLazySingleton<IDestinationOrchestrator>(
    () => DestinationOrchestratorImpl(
      localDestinationService: getIt<ILocalDestinationService>(),
      sendToFtp: getIt<SendToFtp>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      sendToDropbox: getIt<SendToDropbox>(),
      sendToNextcloud: getIt<SendToNextcloud>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      circuitBreakerRegistry: getIt<CircuitBreakerRegistry>(),
    ),
  );
  getIt.registerLazySingleton<IBackupCleanupService>(
    () => BackupCleanupServiceImpl(
      localDestinationService: getIt<ILocalDestinationService>(),
      ftpDestinationService: getIt<IFtpService>(),
      googleDriveDestinationService: getIt<IGoogleDriveDestinationService>(),
      dropboxDestinationService: getIt<IDropboxDestinationService>(),
      nextcloudDestinationService: getIt<INextcloudDestinationService>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      notificationService: getIt<INotificationService>(),
      backupLogRepository: getIt<IBackupLogRepository>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
    ),
  );

  // ========================================================================
  // DESTINATION SERVICES
  // ========================================================================

  getIt.registerLazySingleton<ILocalDestinationService>(
    LocalDestinationService.new,
  );
  getIt.registerLazySingleton<IFtpService>(FtpDestinationService.new);
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

  // ========================================================================
  // NOTIFICATION SERVICE
  // ========================================================================

  getIt.registerLazySingleton<IOAuthSmtpService>(
    () => OAuthSmtpService(getIt<ISecureCredentialService>()),
  );
  getIt.registerLazySingleton<EmailService>(
    () => EmailService(oauthSmtpService: getIt<IOAuthSmtpService>()),
  );
  getIt.registerLazySingleton<IEmailService>(getIt.get<EmailService>);
  getIt.registerLazySingleton<LogService>(
    () => LogService(getIt<IBackupLogRepository>()),
  );

  // ========================================================================
  // SCHEDULER SERVICE
  // ========================================================================

  getIt.registerLazySingleton<ITaskSchedulerService>(
    WindowsTaskSchedulerService.new,
  );

  // ========================================================================
  // WINDOWS EVENT LOG
  // ========================================================================

  getIt.registerLazySingleton<WindowsEventLogService>(
    () => WindowsEventLogService(
      processService: getIt<ProcessService>(),
    ),
  );

  getIt.registerLazySingleton<IWindowsServiceEventLogger>(
    () => getIt<WindowsEventLogService>(),
  );

  // ========================================================================
  // STORAGE CHECKER
  // ========================================================================

  getIt.registerLazySingleton<IStorageChecker>(StorageChecker.new);

  // ========================================================================
  // AUTO UPDATE SERVICE
  // ========================================================================

  getIt.registerLazySingleton<AutoUpdateService>(AutoUpdateService.new);

  // ========================================================================
  // SOCKET SERVER & CLIENT
  // ========================================================================

  getIt.registerLazySingleton<ConnectionManager>(
    () => ConnectionManager(
      serverConnectionDao: getIt<AppDatabase>().serverConnectionDao,
    ),
  );
  getIt.registerLazySingleton<ClientManager>(ClientManager.new);
  getIt.registerLazySingleton<BackupProgressProvider>(
    BackupProgressProvider.new,
  );
  getIt.registerLazySingleton<IBackupProgressNotifier>(
    getIt.get<BackupProgressProvider>,
  );
  getIt.registerLazySingleton<ScheduleMessageHandler>(
    () => ScheduleMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      schedulerService: getIt<ISchedulerService>(),
      updateSchedule: getIt<UpdateSchedule>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
    ),
  );

  final appDir = await getApplicationDocumentsDirectory();
  final transferBasePath = p.join(appDir.path, 'backups');
  final lockPath = p.join(appDir.path, 'locks');

  getIt.registerLazySingleton<IFileTransferLockService>(
    () => FileTransferLockService(lockBasePath: lockPath),
  );
  getIt.registerLazySingleton<FileTransferMessageHandler>(
    () => FileTransferMessageHandler(
      allowedBasePath: transferBasePath,
      lockService: getIt<IFileTransferLockService>(),
    ),
  );
  getIt.registerLazySingleton<ITransferStagingService>(
    () => TransferStagingService(transferBasePath: transferBasePath),
  );

  getIt.registerLazySingleton<MetricsMessageHandler>(
    () => MetricsMessageHandler(
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
      scheduleRepository: getIt<IScheduleRepository>(),
      backupRunningState: getIt<IBackupRunningState>(),
      metricsCollector: getIt<IMetricsCollector>(),
    ),
  );
  getIt.registerLazySingleton<TcpSocketServer>(
    () => TcpSocketServer(
      serverCredentialDao: getIt<AppDatabase>().serverCredentialDao,
      licenseValidationService: getIt<ILicenseValidationService>(),
      clientManager: getIt<ClientManager>(),
      connectionLogDao: getIt<AppDatabase>().connectionLogDao,
      scheduleHandler: getIt<ScheduleMessageHandler>(),
      fileTransferHandler: getIt<FileTransferMessageHandler>(),
      metricsHandler: getIt<MetricsMessageHandler>(),
    ),
  );
  getIt.registerLazySingleton<SocketServerService>(getIt.get<TcpSocketServer>);
}
