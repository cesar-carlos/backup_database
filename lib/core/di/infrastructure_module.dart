import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/di/infrastructure_socket_server_module.dart';
import 'package:backup_database/core/di/sgbd_registration.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/cleanup/backup_cleanup_service_impl.dart';
import 'package:backup_database/infrastructure/cleanup/temporary_backup_cleanup_scheduler.dart';
import 'package:backup_database/infrastructure/cleanup/temporary_backup_cleanup_service.dart';
import 'package:backup_database/infrastructure/compression/backup_compression_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/destination/destination_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/repositories/repositories.dart';
import 'package:backup_database/infrastructure/scripts/backup_script_orchestrator_impl.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:get_it/get_it.dart';

/// Sets up infrastructure layer dependencies.
///
/// This module registers repository implementations, external services,
/// process services, backup services, destination services, and socket
/// server components.
Future<void> setupInfrastructureModule(GetIt getIt) async {
  // ========================================================================
  // REPOSITORY IMPLEMENTATIONS
  // ========================================================================

  // Config repositories (SQL Server, Sybase, PostgreSQL, Firebird) are
  // registered via [registerBackupDatabaseDefaultSgbds] below.

  getIt.registerLazySingleton<IBackupDestinationRepository>(
    () => BackupDestinationRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IScheduleRepository>(
    () => ScheduleRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupLogRepository>(
    () => BackupLogRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IBackupHistoryRepository>(
    () => CachedBackupHistoryRepository(
      repository: BackupHistoryRepository(
        getIt<AppDatabase>(),
        getIt<IBackupLogRepository>() as BackupLogRepository,
      ),
    ),
  );

  getIt.registerLazySingleton<IEmailConfigRepository>(
    () => EmailConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IEmailNotificationTargetRepository>(
    () => EmailNotificationTargetRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IEmailTestAuditRepository>(
    () => EmailTestAuditRepository(getIt<AppDatabase>()),
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
    () => ServerConnectionRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
  );
  getIt.registerLazySingleton<IMachineSettingsRepository>(
    () => MachineSettingsRepository(getIt<AppDatabase>()),
  );
  getIt.registerLazySingleton<IUserPreferencesRepository>(
    UserPreferencesRepository.new,
  );

  getIt.registerLazySingleton<IScheduleCalculator>(ScheduleCalculator.new);
  getIt.registerLazySingleton<IFileValidator>(FileValidator.new);

  // ========================================================================
  // PROCESS & EXTERNAL SERVICES
  // ========================================================================

  getIt.registerLazySingleton<ProcessService>(ProcessService.new);
  // §audit-2026-05-28 wave 4: probe de elevação/UAC para gatear o
  // auto-update silencioso (UI). Consulta `EnableLUA` no registry e
  // o token do processo via PowerShell. Não-Windows = no-op.
  getIt.registerLazySingleton<IElevationProbe>(
    () => WindowsElevationProbe(processService: getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<IBackupCancellationService>(
    () => BackupCancellationService(getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<SybaseConnectionStrategyCache>(
    SybaseConnectionStrategyCache.new,
  );
  registerBackupDatabaseDefaultSgbds(getIt);
  getIt.registerLazySingleton<IWindowsServiceService>(
    () => WindowsServiceService(
      getIt<ProcessService>(),
      metricsCollector: getIt<IMetricsCollector>(),
    ),
  );
  getIt.registerLazySingleton<IWindowsMachineStartupService>(
    WindowsMachineStartupService.new,
  );

  // ========================================================================
  // BACKUP SERVICES (SGBD ports registered via registerBackupDatabaseDefaultSgbds)
  // ========================================================================

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
      sendToGoogleDrive: getIt<SendToGoogleDrive>(),
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
  getIt.registerLazySingleton<ITemporaryBackupCleanupService>(
    () => TemporaryBackupCleanupService(
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
    ),
  );
  getIt.registerLazySingleton<TemporaryBackupCleanupScheduler>(
    () => TemporaryBackupCleanupScheduler(
      getIt<ITemporaryBackupCleanupService>(),
    ),
  );
  getIt.registerLazySingleton<ITemporaryBackupCleanupScheduler>(
    getIt.get<TemporaryBackupCleanupScheduler>,
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
      // §audit-2026-05-28 wave 2 (P0): passar o repositório (em vez do
      // DAO direto) garante que `connectToSavedConnection` leia a
      // senha do vault DPAPI. O DAO sozinho devolve `password: ''`
      // após a migração para secure storage da wave 1.
      serverConnectionRepository: getIt<IServerConnectionRepository>(),
    ),
  );
  getIt.registerLazySingleton<BackupProgressProvider>(
    BackupProgressProvider.new,
  );
  getIt.registerLazySingleton<IBackupProgressNotifier>(
    getIt.get<BackupProgressProvider>,
  );
  // O `IBackupRunningState` é apenas uma fatia read-only de
  // `BackupProgressProvider` consumida por features como auto-update
  // e cancelamento. Mantido aqui (e não no `domain_module`) porque a
  // implementação concreta vive no application layer — o módulo de
  // domain não deve importar `application/providers`.
  getIt.registerLazySingleton<IBackupRunningState>(
    getIt.get<BackupProgressProvider>,
  );

  await setupSocketServerModule(getIt);
}
