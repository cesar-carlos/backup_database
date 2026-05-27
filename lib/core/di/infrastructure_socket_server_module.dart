import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/domain/use_cases/use_cases.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/file_transfer_lock_service.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_store.dart';
import 'package:backup_database/infrastructure/socket/server/capabilities_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/client_manager.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/database_config_store.dart';
import 'package:backup_database/infrastructure/socket/server/database_connection_prober.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_provider.dart';
import 'package:backup_database/infrastructure/socket/server/execution_event_sequencer.dart';
import 'package:backup_database/infrastructure/socket/server/execution_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/execution_queue_persistence.dart';
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
import 'package:backup_database/infrastructure/socket/server/remote_staging_artifact_ttl.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_crud_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/schedule_message_handler.dart';
import 'package:backup_database/infrastructure/socket/server/server_preflight_checks.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_service.dart';
import 'package:backup_database/infrastructure/socket/server/socket_server_telemetry.dart';
import 'package:backup_database/infrastructure/socket/server/tcp_socket_server.dart';
import 'package:backup_database/infrastructure/transfer_staging_cleanup_scheduler.dart';
import 'package:backup_database/infrastructure/transfer_staging_service.dart';
import 'package:backup_database/infrastructure/utils/staging_usage_measurer.dart';
import 'package:get_it/get_it.dart';

/// Suporte a Firebird remoto no socket server. Mesmo valor anunciado em
/// [CapabilitiesMessageHandler]. Os handlers de execucao/CRUD usam o
/// default `supportsFirebird: true`; ao desligar Firebird no processo
/// servidor, passe `supportsFirebird: false` explicitamente em
/// [ScheduleMessageHandler], [ExecutionMessageHandler] e
/// [ScheduleCrudMessageHandler] e mantenha este const coerente.
const bool _socketServerSupportsFirebird = true;

/// Sets up the socket server stack (handlers, queue, staging, TCP).
///
/// Antes ficava inline em `infrastructure_module.dart` (~290 linhas).
/// Extraído para reduzir o tamanho do módulo principal e tornar a
/// dependência socket-server explícita.
Future<void> setupSocketServerModule(GetIt getIt) async {
  await _registerExecutionRegistryAndStaging(getIt);
  await _registerHandlersAndQueueService(getIt);
  _registerTcpSocketServer(getIt);
}

Future<void> _registerExecutionRegistryAndStaging(GetIt getIt) async {
  getIt.registerLazySingleton<ClientManager>(ClientManager.new);
  // Registry compartilhado entre o ScheduleMessageHandler (que registra
  // execucoes) e o MetricsMessageHandler (que expoe activeRunId/Count
  // para observabilidade — M2.1 + M5.3 + M7.1). Singleton garante uma
  // unica fonte de verdade por servidor.
  getIt.registerLazySingleton<RemoteExecutionRegistry>(
    RemoteExecutionRegistry.new,
  );
  getIt.registerLazySingleton<ExecutionEventSequencer>(
    ExecutionEventSequencer.new,
  );

  final stagingDir = await resolveMachineStagingBackupsDirectory();
  final lockDir = await resolveMachineLocksDirectory();
  final transferBasePath = stagingDir.path;
  final lockPath = lockDir.path;

  getIt.registerLazySingleton<IFileTransferLockService>(
    () => FileTransferLockService(lockBasePath: lockPath),
  );
  getIt.registerLazySingleton<ITransferStagingService>(
    () => TransferStagingService(transferBasePath: transferBasePath),
  );
  getIt.registerLazySingleton<RemoteStagingCleanupScheduler>(
    () => RemoteStagingCleanupScheduler(getIt<ITransferStagingService>()),
  );
  getIt.registerLazySingleton<IRemoteStagingCleanupScheduler>(
    getIt.get<RemoteStagingCleanupScheduler>,
  );

  getIt.registerLazySingleton<SocketServerTelemetry>(
    () => SocketServerTelemetry(metricsCollector: getIt<IMetricsCollector>()),
  );

  // Wirings que dependem do `transferBasePath` literal ficam fechados
  // sobre essa variável local (não precisamos guardar no GetIt — é só
  // um path de configuração derivado uma vez).
  _registerStagingDependentHandlers(getIt, transferBasePath);
}

void _registerStagingDependentHandlers(
  GetIt getIt,
  String transferBasePath,
) {
  getIt.registerLazySingleton<ScheduleMessageHandler>(
    () => ScheduleMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      schedulerService: getIt<ISchedulerService>(),
      updateSchedule: getIt<UpdateSchedule>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
      executionRegistry: getIt<RemoteExecutionRegistry>(),
      eventSequencer: getIt<ExecutionEventSequencer>(),
      stagingUsageBytesProvider: () =>
          StagingUsageMeasurer.measure(transferBasePath),
    ),
  );

  getIt.registerLazySingleton<FileTransferMessageHandler>(
    () => FileTransferMessageHandler(
      allowedBasePath: transferBasePath,
      lockService: getIt<IFileTransferLockService>(),
    ),
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
      queueService: getIt<ExecutionQueueService>(),
      // Mede o uso atual do diretorio de staging (defensivo — falhas
      // de I/O viram 0/parcial, nao crash). Usa o mesmo `transferBasePath`
      // que `TransferStagingService` ja usa para escrita.
      stagingUsageBytesProvider: () =>
          StagingUsageMeasurer.measure(transferBasePath),
      artifactExpiresAtForRunId: (runId) => RemoteStagingArtifactTtl()
          .expiresAtForRunInStaging(transferBasePath, runId),
      socketTelemetry: getIt<SocketServerTelemetry>(),
    ),
  );

  // HealthMessageHandler com checks minimos + pressao de staging (PR-4).
  // Mesmo `StagingUsageMeasurer` que `MetricsMessageHandler` / execucao.
  getIt.registerLazySingleton<HealthMessageHandler>(
    () => HealthMessageHandler(
      stagingUsageBytesProvider: () =>
          StagingUsageMeasurer.measure(transferBasePath),
    ),
  );

  // PreflightMessageHandler com mapa de checks vazio por padrao.
  // Wirings em producao podem injetar checks como `compression_tool`,
  // `temp_dir_writable`, `disk_space` reusando ToolVerificationService,
  // validate_backup_directory e StorageChecker (ver F1.8 do plano).
  getIt.registerLazySingleton<PreflightMessageHandler>(
    () => PreflightMessageHandler(
      checks: buildServerPreflightChecks(
        stagingBasePath: transferBasePath,
        validateBackupDirectory: const ValidateBackupDirectory(),
        storageChecker: getIt<IStorageChecker>(),
      ),
    ),
  );

  // ExecutionMessageHandler com todas as dependencias reais.
  getIt.registerLazySingleton<ExecutionMessageHandler>(
    () => ExecutionMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      licensePolicyService: getIt<ILicensePolicyService>(),
      schedulerService: getIt<ISchedulerService>(),
      executeBackup: getIt<ExecuteScheduledBackup>(),
      progressNotifier: getIt<IBackupProgressNotifier>(),
      executionRegistry: getIt<RemoteExecutionRegistry>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
      queueService: getIt<ExecutionQueueService>(),
      eventSequencer: getIt<ExecutionEventSequencer>(),
      stagingUsageBytesProvider: () =>
          StagingUsageMeasurer.measure(transferBasePath),
      // QueueEventBus injetado pela factory do TcpSocketServer (cabeia
      // o setter após o server existir).
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
}

Future<void> _registerHandlersAndQueueService(GetIt getIt) async {
  // CapabilitiesMessageHandler nao tem dependencias externas (apenas
  // constantes de protocol_versions.dart). Registrado para consistencia
  // com os outros handlers e para permitir override em testes/mocks
  // futuros (ex.: clock injetado).
  getIt.registerLazySingleton<CapabilitiesMessageHandler>(
    () => CapabilitiesMessageHandler(
      supportsFirebird: _socketServerSupportsFirebird,
    ),
  );

  // IdempotencyRegistry compartilhado entre todos os handlers que aceitam
  // `idempotencyKey` (start/cancel backup, schedule CRUD, database CRUD,
  // cleanupStaging). Singleton garante que retransmissoes via reconnect
  // sejam deduplicadas mesmo se chegarem em handlers diferentes.
  getIt.registerLazySingleton<IdempotencyRegistry>(
    () => IdempotencyRegistry(
      store: DriftIdempotencyStore(getIt<AppDatabase>().idempotencyDao),
    ),
  );

  // ExecutionQueueService compartilhado: persistencia Drift (F2.16).
  // Chame `initialize()` no bootstrap antes do socket server.
  getIt.registerLazySingleton<ExecutionQueueService>(
    () => ExecutionQueueService(
      persistence: DriftExecutionQueuePersistence(
        getIt<AppDatabase>().executionQueueDao,
      ),
    ),
  );
  getIt.registerLazySingleton<IExecutionQueueBootstrap>(
    getIt.get<ExecutionQueueService>,
  );

  // PR-3c: `getExecutionStatus` reaproveita registry, fila e historico
  // (runId em backup_history apos v31).
  getIt.registerLazySingleton<ExecutionStatusMessageHandler>(
    () => ExecutionStatusMessageHandler(
      executionRegistry: getIt<RemoteExecutionRegistry>(),
      queueService: getIt<ExecutionQueueService>(),
      backupHistoryRepository: getIt<IBackupHistoryRepository>(),
    ),
  );

  // ScheduleCrudMessageHandler compartilhando idempotency com os demais.
  getIt.registerLazySingleton<ScheduleCrudMessageHandler>(
    () => ScheduleCrudMessageHandler(
      scheduleRepository: getIt<IScheduleRepository>(),
      idempotencyRegistry: getIt<IdempotencyRegistry>(),
    ),
  );

  // RealDatabaseConnectionProber: despacha por tipo aos 4 backup
  // services existentes (reusa probe sem reescrever).
  getIt.registerLazySingleton<DatabaseConnectionProber>(
    () => RealDatabaseConnectionProber(
      sybaseService: getIt<ISybaseBackupService>(),
      sqlServerService: getIt<ISqlServerBackupService>(),
      postgresService: getIt<IPostgresBackupService>(),
      firebirdService: getIt<IFirebirdBackupService>(),
      sybaseRepository: getIt<ISybaseConfigRepository>(),
      sqlServerRepository: getIt<ISqlServerConfigRepository>(),
      postgresRepository: getIt<IPostgresConfigRepository>(),
      firebirdRepository: getIt<IFirebirdConfigRepository>(),
    ),
  );

  // RealDatabaseConfigStore: despacha CRUD por tipo aos repositorios.
  // Senhas NAO sao incluidas em respostas de listagem por default
  // (controlado pelo serializer).
  getIt.registerLazySingleton<DatabaseConfigStore>(
    () => RealDatabaseConfigStore(
      sybaseRepository: getIt<ISybaseConfigRepository>(),
      sqlServerRepository: getIt<ISqlServerConfigRepository>(),
      postgresRepository: getIt<IPostgresConfigRepository>(),
      firebirdRepository: getIt<IFirebirdConfigRepository>(),
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
}

void _registerTcpSocketServer(GetIt getIt) {
  // TcpSocketServer com TODOS os handlers cabeados. Após a instanciação,
  // resolvemos a dependência circular `ExecutionMessageHandler ↔
  // QueueEventBus ↔ TcpSocketServer.sendToClient` cabeando o eventBus
  // direto no handler. O `QueueEventBus` é um colaborador interno e
  // não fica registrado no GetIt — quem precisa dele recebe via
  // construtor/setter dos handlers, sem mutar o container durante
  // factory de outro tipo.
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
      socketTelemetry: getIt<SocketServerTelemetry>(),
    );
    getIt<ExecutionMessageHandler>().eventBus = QueueEventBus(
      broadcast: server.sendToClient,
      sequencer: getIt<ExecutionEventSequencer>(),
    );
    return server;
  });

  // SocketServerService aliasing
  getIt.registerLazySingleton<SocketServerService>(getIt.get<TcpSocketServer>);
  getIt.registerLazySingleton<ISocketServerLifecycle>(
    getIt.get<SocketServerService>,
  );
}
