enum MessageType {
  authRequest,
  authResponse,
  authChallenge,
  listSchedules,
  scheduleList,
  updateSchedule,
  executeSchedule,
  scheduleUpdated,
  cancelSchedule,
  scheduleCancelled,
  backupProgress,
  backupStep,
  backupComplete,
  backupFailed,
  listFiles,
  fileList,
  fileTransferStart,
  fileChunk,
  fileTransferProgress,
  fileTransferComplete,
  fileTransferError,
  fileAck,
  metricsRequest,
  metricsResponse,
  heartbeat,
  disconnect,
  error,
  // Adicionados ao final do enum para preservar indices (wire-compat).
  // Cliente legado que receber esses tipos cai no fallback
  // `MessageType.error` em `BinaryProtocol.deserializeMessage`,
  // sem quebrar a deserializacao (ver ADR-003).
  capabilitiesRequest,
  capabilitiesResponse,
  healthRequest,
  healthResponse,
  sessionRequest,
  sessionResponse,
  preflightRequest,
  preflightResponse,
  executionStatusRequest,
  executionStatusResponse,
  executionQueueRequest,
  executionQueueResponse,
  // PR-2: testDatabaseConnection. Permite cliente solicitar que o
  // servidor sonde a conexao com um banco usando a `databaseConfig`
  // ja persistida no servidor (por `databaseConfigId`) ou uma config
  // ad-hoc no payload. Resposta inclui `connected: bool`,
  // `latencyMs`, mensagem de erro quando aplicavel.
  testDatabaseConnectionRequest,
  testDatabaseConnectionResponse,
  // PR-2: startBackup nao-bloqueante (M2.2). Cliente envia
  // `scheduleId` + `idempotencyKey?` e recebe IMEDIATAMENTE
  // `startBackupResponse(runId, state)` — sem aguardar conclusao.
  // Eventos `backupProgress/Complete/Failed` chegam separados via
  // stream com o mesmo `runId`. Substitui `executeSchedule` no novo
  // contrato; `executeSchedule` legacy continua existindo para
  // compat com clientes v1.
  startBackupRequest,
  startBackupResponse,
  // PR-2: cancelBackup. Cliente envia `runId` (ou `scheduleId`
  // legado) e recebe `cancelBackupResponse(state, message?)`.
  // Cancelamento e best-effort no servidor (delegado ao scheduler);
  // estado final do backup ainda chega via `backupFailed`/`Complete`.
  cancelBackupRequest,
  cancelBackupResponse,
  // PR-3: eventos de fila publicados pelo servidor para clientes
  // observarem progresso da fila em tempo real. Carregam runId,
  // scheduleId, eventId (uuid) e sequence (monotonico por servidor)
  // para reprocessamento resiliente apos reconnect.
  backupQueued,
  backupDequeued,
  backupStarted,
  // PR-3: cancelQueuedBackup. Cliente cancela uma execucao que
  // ainda esta na fila (estado=queued). Diferente de cancelBackup
  // (que cancela execucao em curso). Servidor responde com state=
  // cancelled + scheduleId + runId.
  cancelQueuedBackupRequest,
  cancelQueuedBackupResponse,
  // PR-3 commit final: diagnostico operacional. Endpoints somente
  // leitura para o cliente investigar problemas de execucao remota.
  // Implementacao concreta delegada via DI (Diagnostics provider) —
  // contratos prontos no protocolo.
  getRunLogsRequest,
  getRunLogsResponse,
  getRunErrorDetailsRequest,
  getRunErrorDetailsResponse,
  getArtifactMetadataRequest,
  getArtifactMetadataResponse,
  cleanupStagingRequest,
  cleanupStagingResponse,
  // PR-2: schedule CRUD remoto (createSchedule, deleteSchedule,
  // pauseSchedule, resumeSchedule). `updateSchedule` ja existia desde
  // antes do PR-1; aqui adicionamos os 4 que faltam para CRUD completo.
  // Resposta unificada `scheduleMutationResponse` carrega o `schedule`
  // resultante (ou nada quando delete) + envelope REST-like.
  createSchedule,
  deleteSchedule,
  pauseSchedule,
  resumeSchedule,
  scheduleMutationResponse,
  // PR-2: database config CRUD remoto. Permite cliente listar /
  // criar / atualizar / deletar configuracoes de banco (Sybase /
  // SQL Server / Postgres) sem precisar embarcar a logica de DAO no
  // cliente. Payload usa Map<String, dynamic> opaco indexado por
  // `databaseType` — cada implementacao concreta de DatabaseConfigStore
  // sabe interpretar.
  listDatabaseConfigsRequest,
  listDatabaseConfigsResponse,
  createDatabaseConfigRequest,
  updateDatabaseConfigRequest,
  deleteDatabaseConfigRequest,
  databaseConfigMutationResponse,
}
