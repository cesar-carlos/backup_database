import 'package:backup_database/application/providers/providers.dart';
import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
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
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/socket/server/capabilities_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_provider.dart';
import 'package:backup_database/infrastructure/socket/server/execution_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_service.dart';
import 'package:backup_database/infrastructure/socket/server/execution_status_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/file_transfer_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/health_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/metrics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/preflight_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/queue_event_bus.dart';
import 'package:backup_database/infrastructure/socket/server/real_database_config_store.dart';
import 'package:backup_database/infrastructure/socket/server/real_database_connection_prober.dart';
import 'package:backup_database/infrastructure/socket/server/real_diagnostics_provider.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_crud_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:backup_database/infrastructure/transfer_staging_service.dart';
import 'package:backup_database/infrastructure/utils/staging_usage_measurer.dart';
import 'package:get_it/get_it.dart';

/// Sets up infrastructure layer dependencies.
///
/// This module registers external services, process services,
/// backup services, destination services, and socket server components.
Future<void> setupInfrastructureModule(GetIt getIt) async {
  // ========================================================================
  // PROCESS & EXTERNAL SERVICES
  // ========================================================================

  getIt.registerLazySingleton<ProcessService>(ProcessService.new);
  getIt.registerLazySingleton<IBackupCancellationService>(
    () => BackupCancellationService(getIt<ProcessService>()),
  );
  getIt.registerLazySingleton<ToolVerificationService>(
    () => ToolVerificationService(getIt<ProcessService>()),
  );
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
  // Registry compartilhado entre o ScheduleMessageHandler (que registra
  // execucoes) e o MetricsMessageHandler (que expoe activeRunId/Count
  // para observabilidade — M2.1 + M5.3 + M7.1). Singleton garante uma
  // unica fonte de verdade por servidor.
  getIt.registerLazySingleton<RemoteExecutionRegistry>(
    RemoteExecutionRegistry.new,
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
      executionRegistry: getIt<RemoteExecutionRegistry>(),
    ),
  );

  final stagingDir = await resolveMachineStagingBackupsDirectory();
  final lockDir = await resolveMachineLocksDirectory();
  final transferBasePath = stagingDir.path;
  final lockPath = lockDir.path;

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
      // Compartilhado com ScheduleMessageHandler — registra do lado de
      // quem dispara, le do lado de quem reporta metricas (M5.3/M7.1).
      executionRegistry: getIt<RemoteExecutionRegistry>(),
      // Mede o uso atual do diretorio de staging (defensivo — falhas
      // de I/O viram 0/parcial, nao crash). Usa o mesmo `transferBasePath`
      // que `TransferStagingService` ja usa para escrita.
      stagingUsageBytesProvider: () =>
          StagingUsageMeasurer.measure(transferBasePath),
    ),
  );
  // CapabilitiesMessageHandler nao tem dependencias externas (apenas
  // constantes de protocol_versions.dart). Registrado para consistencia
  // com os outros handlers e para permitir override em testes/mocks
  // futuros (ex.: clock injetado).
  getIt.registerLazySingleton<CapabilitiesMessageHandler>(
    CapabilitiesMessageHandler.new,
  );
  // HealthMessageHandler com checks minimos. Wirings em producao podem
  // adicionar checks de banco/staging/license via override no DI ou
  // instanciacao direta no TcpSocketServer (ver M1.10).
  getIt.registerLazySingleton<HealthMessageHandler>(
    HealthMessageHandler.new,
  );
  // PreflightMessageHandler com mapa de checks vazio por padrao.
  // Wirings em producao podem injetar checks como `compression_tool`,
  // `temp_dir_writable`, `disk_space` reusando ToolVerificationService,
  // validate_backup_directory e StorageChecker (ver F1.8 do plano).
  getIt.registerLazySingleton<PreflightMessageHandler>(
    PreflightMessageHandler.new,
  );
  // ExecutionStatusMessageHandler compartilha o RemoteExecutionRegistry
  // ja registrado para o ScheduleMessageHandler (M2.1) — fonte unica
  // de verdade do estado de execucoes em curso.
  getIt.registerLazySingleton<ExecutionStatusMessageHandler>(
    () => ExecutionStatusMessageHandler(
      executionRegistry: getIt<RemoteExecutionRegistry>(),
    ),
  );
  // ========================================================================
  // PR-2 / PR-3: Wirings concretos para handlers cabeados ao dominio
  // ========================================================================

  // IdempotencyRegistry compartilhado entre todos os handlers que aceitam
  // `idempotencyKey` (start/cancel backup, schedule CRUD, database CRUD,
  // cleanupStaging). Singleton garante que retransmissoes via reconnect
  // sejam deduplicadas mesmo se chegarem em handlers diferentes.
  getIt.registerLazySingleton<IdempotencyRegistry>(IdempotencyRegistry.new);

  // ExecutionQueueService compartilhado: ExecutionMessageHandler escreve
  // (enqueue/drain), ExecutionQueueMessageHandler le (snapshot para
  // getExecutionQueue). Em PR-3 commit 5 sera trocado por implementacao
  // persistida.
  getIt.registerLazySingleton<ExecutionQueueService>(ExecutionQueueService.new);

  // ExecutionMessageHandler com todas as dependencias reais.
  getIt.registerLazySingleton<ExecutionMessageHandler>(
    () => ExecutionMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      destinationRepository: getIt<IBackupDestinationRepository>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      schedulerService: getIt<ISchedulerService>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
      executionRegistry: getIt<RemoteExecutionRegistry>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
      queueService: getIt<ExecutionQueueService>(),
      // QueueEventBus injetado mais abaixo apos TcpSocketServer existir
      // (precisa do `sendToClient` para broadcast).
    ),
  );

  // ScheduleCrudMessageHandler compartilhando idempotency com os demais.
  getIt.registerLazySingleton<ScheduleCrudMessageHandler>(
    () => ScheduleCrudMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
    ),
  );

  // RealDatabaseConnectionProber: despacha por tipo aos 3 backup
  // services existentes (que ja tem `testConnection`). Reaproveita
  // toda a infra de probe sem reescrever.
  getIt.registerLazySingleton<DatabaseConnectionProber>(
    () => RealDatabaseConnectionProber(
      sybaseService: getIt<ISybaseBackupService>(),
      sqlServerService: getIt<ISqlServerBackupService>(),
      postgresService: getIt<IPostgresBackupService>(),
      sybaseRepository: getIt<ISybaseConfigRepository>(),
      sqlServerRepository: getIt<ISqlServerConfigRepository>(),
      postgresRepository: getIt<IPostgresConfigRepository>(),
    ),
  );

  // RealDatabaseConfigStore: despacha CRUD por tipo aos 3 repositorios.
  // Senhas NAO sao incluidas em respostas de listagem por default
  // (controlado pelo serializer).
  getIt.registerLazySingleton<DatabaseConfigStore>(
    () => RealDatabaseConfigStore(
      sybaseRepository: getIt<ISybaseConfigRepository>(),
      sqlServerRepository: getIt<ISqlServerConfigRepository>(),
      postgresRepository: getIt<IPostgresConfigRepository>(),
    ),
  );

  // DatabaseConfigMessageHandler com prober + store reais + idempotency
  // compartilhada.
  getIt.registerLazySingleton<DatabaseConfigMessageHandler>(
    () => DatabaseConfigMessageHandler(
      prober: getIt<DatabaseConnectionProber>(),
      store: getIt<DatabaseConfigStore>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
    ),
  );

  // RealDiagnosticsProvider: best-effort v1, mapeia runId -> scheduleId
  // (formato `<scheduleId>_<uuid>`) para consultar BackupHistory/Log
  // existentes. Em PR final substituir por lookup direto quando coluna
  // `runId` for adicionada.
  getIt.registerLazySingleton<DiagnosticsProvider>(
    () => RealDiagnosticsProvider(
      historyRepository: getIt<IBackupHistoryRepository>(),
      logRepository: getIt<IBackupLogRepository>(),
      stagingBasePath: transferBasePath,
    ),
  );

  // DiagnosticsMessageHandler com provider real + idempotency.
  getIt.registerLazySingleton<DiagnosticsMessageHandler>(
    () => DiagnosticsMessageHandler(
      provider: getIt<DiagnosticsProvider>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
    ),
  );

  // ExecutionQueueMessageHandler compartilha snapshot da fila com
  // ExecutionMessageHandler. Wiring usa o queueService.snapshot() como
  // QueueProvider.
  getIt.registerLazySingleton<ExecutionQueueMessageHandler>(
    () => ExecutionQueueMessageHandler(
      queueProvider: () async => getIt<ExecutionQueueService>().snapshot(),
    ),
  );

  // TcpSocketServer com TODOS os handlers cabeados. Apos a instanciacao,
  // resolvemos a dependencia circular `ExecutionMessageHandler ↔
  // QueueEventBus ↔ TcpSocketServer.sendToClient` via setter no
  // handler. Lazy: o cabeamento so acontece quando o servidor e de
  // fato resolvido pela primeira vez (na chamada `start()` da app).
  getIt.registerLazySingleton<TcpSocketServer>(() {
    final server = TcpSocketServer(
      serverCredentialDao: getIt<AppDatabase>().serverCredentialDao,
      licenseValidationService: getIt<ILicenseValidationService>(),
      clientManager: getIt<ClientManager>(),
      connectionLogDao: getIt<AppDatabase>().connectionLogDao,
      scheduleHandler: getIt<ScheduleMessageHandler>(),
      fileTransferHandler: getIt<FileTransferMessageHandler>(),
      metricsHandler: getIt<MetricsMessageHandler>(),
      capabilitiesHandler: getIt<CapabilitiesMessageHandler>(),
      healthHandler: getIt<HealthMessageHandler>(),
      preflightHandler: getIt<PreflightMessageHandler>(),
      executionStatusHandler: getIt<ExecutionStatusMessageHandler>(),
      executionQueueHandler: getIt<ExecutionQueueMessageHandler>(),
      databaseConfigHandler: getIt<DatabaseConfigMessageHandler>(),
      executionHandler: getIt<ExecutionMessageHandler>(),
      scheduleCrudHandler: getIt<ScheduleCrudMessageHandler>(),
      diagnosticsHandler: getIt<DiagnosticsMessageHandler>(),
    );
    // Resolve dependencia circular pos-instanciacao:
    // QueueEventBus precisa do `sendToClient` do server; o
    // ExecutionMessageHandler ja foi construido e recebe o bus
    // por setter. Sem isso, eventos backupQueued/Dequeued/Started
    // nao seriam publicados no socket.
    final eventBus = QueueEventBus(
      broadcast: server.sendToClient,
    );
    getIt<ExecutionMessageHandler>().eventBus = eventBus;
    if (!getIt.isRegistered<QueueEventBus>()) {
      getIt.registerSingleton<QueueEventBus>(eventBus);
    }
    return server;
  });

  // SocketServerService aliasing
  getIt.registerLazySingleton<SocketServerService>(getIt.get<TcpSocketServer>);
}
