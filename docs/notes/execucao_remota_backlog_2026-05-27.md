# Execução Remota — Backlog (2026-05-27)

Apenas itens **em aberto** identificados pela auditoria PR-6.
Para o que já está entregue: ver `execucao_remota_status_atual_2026-05-27.md`.
Para histórico de raciocínio: ver `plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`.

**Decisões ratificadas no PR-6** (não revisitar sem ADR):
- `QUEUE_FULL` / `503` (mantém código atual)
- `maxConcurrentBackups = 1` permanente (constante nomeada)
- `executeSchedule` legacy `@Deprecated` (remoção em PR futuro)

---

## Escopo PR-6 (em andamento)

Implementação completa do backlog em PR único. Sequência de commits e impacto em
`pr-6_estabilidade_remota_*.plan.md`.

### A1 — `enforceTransition` em `ExecutionMessageHandler`

**Por quê**: `ExecutionStateMachine.enforceTransition` está definido mas nunca é
chamado em produção. Qualquer handler pode publicar transição inválida sem alerta.

**O quê**:
- Adicionar `ErrorCode.invalidStateTransition` (`INVALID_STATE_TRANSITION` → 409).
- Em `lib/infrastructure/socket/server/execution_message_handler.dart`:
  - `_doStart` antes de enqueue: enforce `idle -> queued`.
  - `_doStart` antes de running: enforce `idle -> running` ou `queued -> running`.
  - `_doCancel`: enforce `running -> cancelled` ou `queued -> cancelled`.
  - `_drainNextFromQueue`: enforce `queued -> running`.
- Capturar `InvalidStateTransitionException` → responder `409` + log de erro.

**DoD**: testes "cancel de runId terminal retorna 409" e "start duplo retorna 409".

---

### A2 — Evento `backupCancelled` separado

**Por quê**: cancelamento manual hoje emite `backupFailed` indistinguível de falha real.
Outros clientes ouvindo o mesmo `runId` ficam órfãos.

**O quê**:
- `MessageType.backupCancelled` + `createBackupCancelledMessage(runId, scheduleId, cancelledBy, occurredAt, eventId, sequence)`.
- `IBackupProgressNotifier.onCancelled(historyId, reason)` distinto de `onFailed`.
- `SchedulerService` distingue cancel (via `_cancelRequestedSchedules`) de falha.
- `ScheduleMessageHandler` serializa o novo evento para clientes inscritos.
- `ConnectionManager._handleBackupProgressMessage` resolve completer com `cancelled`.

**DoD**: teste "cancel publica `backupCancelled` para todos os clientes inscritos no `runId`".

---

### A3 — Watchdog runtime

**Por quê**: orchestrator travado sem crash deixa `BackupHistory.status=running` por até 24h
(só reconcile no próximo boot). Em servidor que fica dias rodando, precisa watchdog em runtime.

**O quê**:
- `BackupConstants`: `runningHeartbeatTimeout=10min`, `runningMaxDuration=6h`, `watchdogCheckInterval=1min`.
- Schema v34: `BackupHistoryTable.lastProgressAt` (DateTime nullable).
- `BackupOrchestratorService.onProgress` atualiza `lastProgressAt`.
- `SchedulerService`: `Timer? _watchdogTimer` separado do `_checkTimer`.
  - A cada 1min: para cada `_runningHistoryIds`, consultar `lastProgressAt`/`startedAt`.
  - Heartbeat estourado → `cancelExecution(scheduleId, reason: 'watchdog timeout')`.
  - Hard limit estourado → `cancelExecution(scheduleId, reason: 'hard limit')`.
  - Marcar history com `errorCode=RUN_WATCHDOG_TIMEOUT` ou `RUN_HARD_TIMEOUT` (503).

**DoD**: teste unitário "scheduler com clock manipulado dispara watchdog após heartbeatTimeout".

---

### A4 — TTL em itens `queued`

**Por quê**: item enfileirado nunca expira sozinho — fica esperando dequeue manual.
Cenário: cliente desistiu e desconectou, mas o backup eventualmente roda sem necessidade.

**O quê**:
- `BackupConstants`: `queuedItemTtl=30min`, `queueHousekeepingInterval=1min`.
- Schema v34: `ExecutionQueueItemsTable.expiresAtMicros` (Int).
- `ExecutionQueueService.tryEnqueue` seta `expiresAt = now + queuedItemTtl`.
- Novo método `pruneExpired()` que remove itens vencidos e dispara `onExpired(item)`.
- Housekeeping job inicializado em `ServiceModeInitializer` step 10.
- Quando item expira:
  - `QueueEventBus.fireAndForgetDequeued(reason: 'ttlExpired')`.
  - `BackupHistory` (se houver) marcado com `errorCode=QUEUED_TTL_EXPIRED` (410).

**DoD**: teste "item enfileirado a 31min é removido + evento `backupDequeued(reason=ttlExpired)`".

---

### A5 — `runId` em `FileTransfersTable` + `FileTransferResumeMetadata`

**Por quê**: rastreabilidade ponta-a-ponta da execução remota requer `runId` no
histórico local de transferência. Resume sem validação de `runId` pode reaproveitar
parcial de execução diferente.

**O quê**:
- Schema v34: `FileTransfersTable.runId` (Text nullable).
- `FileTransferResumeMetadata`: campo `final String? runId;` + propagação em `toJson`/`fromJson`.
- Resume validation: se `metadata.runId != null && metadata.runId != requestedRunId` → retornar `null` (força download do zero).
- `RemoteFileTransferProvider` propaga `runId` nas escritas de metadata e da `FileTransfersTable`.

**DoD**: teste "resume de runId B com metadata de runId A descarta parcial".

---

### A6 — Audit log persistente em DB

**Por quê**: `SocketServerTelemetry._recentMutableAudits` é só memória (cap 100) +
log de texto. Para investigação histórica de problemas (>1 dia), perde.

**O quê**:
- Schema v35 (separado da v34 para isolar): `MutableCommandAuditTable` com `id`, `clientId`, `commandType`, `requestId`, `runId?`, `idempotencyKey?`, `result`, `durationMs?`, `timestampUtc`.
- `MutableCommandAuditDao`: `insertAudit`, `deleteOlderThan`, `recentAudits(limit)`.
- `IMutableCommandAuditRepository` injetado opcional em `SocketServerTelemetry`.
- `_recordMutableAudit` chama `_auditRepository?.insertAudit(entry)` (best-effort, não falha telemetria se DB cair).
- Job de retenção: a cada dia, `deleteOlderThan(now - 30 dias)` (configurável via `BackupConstants.auditRetentionPeriod=30d`).

**DoD**: teste "audit log persiste após restart + retenção 30 dias remove antigos".

---

### A7 — Preflight Sybase log backup

**Por quê**: F1.8 do plano original previa 4 checks. Apenas 3 estão wired
(`compression_tool`, `temp_dir_writable`, `disk_space`).

**O quê**:
- Em `lib/infrastructure/socket/server/server_preflight_checks.dart::buildServerPreflightChecks`:
  - Adicionar entrada `'sybase_log_backup'`.
  - Delegar para use case `validate_sybase_log_backup_preflight` em `lib/domain/use_cases/`.
  - Severity: `warning` (não bloqueia outros backups) ou `blocking` se backup for Sybase log.
- Atualizar DI em `lib/core/di/infrastructure_socket_server_module.dart` linha 163-171.

**DoD**: teste "preflight com sybase config rejeita se prerequisites do log backup falham".

---

### A8 — 3 testes de integração faltantes

**Por quê**: cobertura formal de cenários críticos do plano original (M6.2/M6.3 + PR-4).

**O quê**:

**A8.1 — `test/integration/backup_queue_integration_test.dart`**
- 2 `TcpSocketClient` no mesmo `TcpSocketServer`.
- Ambos chamam `startRemoteBackup(scheduleId: 'X', queueIfBusy: true)`.
- Um vai `running`, outro `queued` com `queuedPosition=1`.
- Validar evento `backupQueued` recebido pelo segundo cliente.
- Após `backupComplete` do primeiro: dequeue → segundo entra em `running`.

**A8.2 — `test/integration/server_restart_recovery_test.dart`**
- Sobe server + cliente; enfileira 3 itens enquanto 1 está running.
- Mata server (`stop()`); sobe `server2` no mesmo port + Drift database.
- Cliente reconecta; `getExecutionQueue` retorna os 3; cada `getExecutionStatus(runId)` retorna `queued`.
- Validar `BackupHistory` do running pré-restart foi reconciliado para `error`.

**A8.3 — `test/integration/file_transfer_resume_integration_test.dart`**
- Cliente inicia download via `requestFile` com `enableResume: true`.
- Após N chunks, mata conexão (`socket.destroy`).
- Reconecta; validar metadata persistida com `runId`.
- Resume continua do chunk N (não do zero); hash final correto; cleanup remoto.

**DoD**: 3 testes passam consistentemente em `flutter test`.

---

## Itens fora do escopo PR-6 (backlog futuro)

- **Multi-execução concorrente** (`maxConcurrentBackups > 1`): exigirá fila por
  `scheduleId` separada + revisão de mutex no `SchedulerService`. Sem demanda
  imediata; ADR-001 ratifica `1` como permanente em v1.
- **Remoção de `executeSchedule` legacy**: depois de 2 releases com `@Deprecated`,
  PR separado para remoção real.
- **`ErrorCode`s ainda não criados**: `QUEUED_BACKUP_NOT_FOUND`, `PRECONDITION_FAILED`,
  `FEATURE_NOT_AVAILABLE`, `DB_CONNECTION_TEST_FAILED`. Avaliar caso a caso se
  realmente precisam (alguns têm equivalente: `NO_ACTIVE_EXECUTION` ≈
  `BACKUP_NOT_RUNNING`).
- **Cliente `v3+` migrar `executeRemoteBackup` para WebSocket** (eventos
  push-based em vez de stream binário): futuro distante; v1 binary continua
  satisfatório.
- **Rate limit por endpoint** (não só por cliente): hoje é global por cliente.
  Avaliar se vale a granularidade adicional.
