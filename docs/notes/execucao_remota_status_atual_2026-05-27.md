# Execução Remota — Status Atual (2026-05-27)

Snapshot do que está **entregue e em produção** no backup remoto orquestrado.
Substitui na prática a maior parte do `plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md` (mantido como histórico de raciocínio + checklists).

**Pendências em aberto**: ver `execucao_remota_backlog_2026-05-27.md`.

---

## Baseline factual

| Métrica | Valor |
|---|---|
| Testes | **2009** (1996 passed + 13 skipped) — AUDIT-15 adicionou cobertura de F1/F2/F3/F4/F6 e idempotência do `SingleInstanceService` |
| Drift `schemaVersion` | **33** (v32 Firebird, v33 idempotency persistence) |
| `kCurrentWireVersion` | `1` (binary header sem mudança) |
| `kCurrentProtocolVersion` | **2** (PR-G Firebird) |
| Capability flags | 6 (`supportsRunId`, `supportsResume`, `supportsArtifactRetention`, `supportsChunkAck`, `supportsExecutionQueue`, `supportsFirebird`) |

---

## Componentes entregues

### Protocolo (`lib/infrastructure/protocol/`)

| Arquivo | Responsabilidade |
|---|---|
| `binary_protocol.dart` | Wire format binário (16 bytes header + CRC32). Valida `kCurrentWireVersion`. |
| `protocol_versions.dart` | Constantes `kCurrentWireVersion`, `kCurrentProtocolVersion`. Helper `isWireVersionSupported`. |
| `message.dart`, `message_types.dart` | Envelope base + enum de tipos. |
| `error_codes.dart` | 17 `ErrorCode` cobrindo auth/IO/staging/queue/protocol/database. |
| `status_codes.dart` | Tabela `ErrorCode -> statusCode` HTTP-like + `isRetryable`. |
| `error_messages.dart` | `createErrorMessage` com `statusCode` automático. |
| `response_envelope.dart` | `wrapSuccessResponse` aplicado em 7 handlers de inspeção. |
| `payload_limits.dart` | Limite de payload por `MessageType`. |
| `idempotency_registry.dart` | TTL 5min, fail-NO-cache, race-safe, opt-in via `idempotencyKey`. |
| `idempotency_policy.dart` | `keyRequiredTypes` (8 mutáveis) + `missingKeyErrorMessage`. |
| `idempotency_store.dart` | `DriftIdempotencyStore` — persistência em SQLite (sobrevive a restart). |
| `auth_messages.dart` | `authRequest`/`authResponse` + handshake. |
| `capabilities_messages.dart` | 6 flags `supports*` + `chunkSize`/`compression`/`serverTimeUtc`. |
| `health_messages.dart` | `ServerHealth` com `stagingUsageBytes`/`Level`/thresholds. |
| `session_messages.dart` | `getSession` / `whoAmI`. |
| `preflight_messages.dart` | `PreflightStatus` + `PreflightCheckResult` agregado. |
| `database_config_messages.dart` | CRUD remoto (sybase/sqlServer/postgres/firebird) + `testDatabaseConnection`. |
| `schedule_messages.dart` | `executeSchedule`, `cancelSchedule`, eventos `backupProgress/Step/Complete/Failed` com `runId`/`eventId`/`sequence` opcionais. |
| `schedule_serialization.dart` | Serializer Schedule + types. |
| `execution_messages.dart` | `startBackup`/`cancelBackup` REST-like (202/200/409) com `XOR runId/scheduleId`. |
| `execution_status_messages.dart` | `getExecutionStatus(runId)` → `queued`/`running`/`completed`/`failed`/`cancelled`/`notFound`. |
| `execution_queue_messages.dart` | `getExecutionQueue` + `cancelQueuedBackup`. |
| `queue_events.dart` | `backupQueued`/`Dequeued`/`Started` com `eventId`+`sequence`. |
| `diagnostics_messages.dart` | `getRunLogs`/`getRunErrorDetails`/`getArtifactMetadata`/`cleanupStaging`. |
| `metrics_messages.dart` | `metricsResponse` com `serverTimeUtc`, `activeRunCount`/`Id`, `stagingUsageBytes`/`Level`, `maxQueueSize`. |
| `file_transfer_messages.dart` | Chunk-based transfer + resume metadata + lease. |

### Server handlers (`lib/infrastructure/socket/server/`)

| Arquivo | Responsabilidade |
|---|---|
| `tcp_socket_server.dart` | Roteamento + DI dos 16 handlers. |
| `client_handler.dart` | Pré-auth guard + rate limit + payload validation + parser de mensagem. |
| `server_authentication.dart` | Validação license + senha (constant-time). |
| `socket_rate_limiter.dart` | M5.1 — janela deslizante req/s + mutações/min. |
| `socket_server_telemetry.dart` | M5.2 (parcial — memória + log) + M7.1 — `socket_request_duration_*`, `socket_error_total_*`. |
| `socket_handler_policies.dart` | DRY — `rejectIfFirebirdUnsupported`. |
| `socket_payload_validators.dart` | DRY — `requireStringField`, `readRunId`, etc. |
| `capabilities_message_handler.dart` | Anuncia 6 capability flags. |
| `health_message_handler.dart` | Required + optional checks (default: socket=true). |
| `session_message_handler.dart` | `getSession` — identidade percebida. |
| `metrics_message_handler.dart` | Métricas operacionais (queue, staging, activeRun). |
| `preflight_message_handler.dart` | Agrega `PreflightCheck`s injetáveis. |
| `server_preflight_checks.dart` | Cabea 3 checks reais: `compression_tool`, `temp_dir_writable`, `disk_space`. |
| `database_config_message_handler.dart` | List + CRUD opaco (`Map<String,dynamic>` por tipo). |
| `database_config_serializers.dart` | Map↔Entity (`includePassword=false` default). |
| `real_database_config_store.dart` | Despacha por tipo aos 3 repos concretos. |
| `database_connection_prober.dart` + `real_database_connection_prober.dart` | `testDatabaseConnection` real. |
| `schedule_message_handler.dart` | Legacy `executeSchedule`/`cancelSchedule` (bloqueante v1). |
| `schedule_crud_message_handler.dart` | `create`/`delete`/`pause`/`resume` Schedule (idempotente). |
| `execution_message_handler.dart` | `startBackup`/`cancelBackup` não-bloqueante + integração com fila + idempotency. |
| `execution_queue_message_handler.dart` | `getExecutionQueue` (snapshot da fila). |
| `execution_status_message_handler.dart` | PR-3c: registry → queue Drift → history (runId v31+). |
| `execution_queue_service.dart` | FIFO + dedup por `scheduleId` + `maxQueueSize=50`. |
| `execution_queue_persistence.dart` + `execution_queue_items_table.dart` | Drift schema v30. |
| `execution_state_machine.dart` | Tabela explícita de transições + `enforceTransition` (definida mas **NÃO chamada** em handlers — ver backlog). |
| `execution_event_sequencer.dart` | Numeração monotônica + UUID v4 compartilhado com `QueueEventBus`. |
| `queue_event_bus.dart` | Broadcast fail-soft de eventos de fila. |
| `remote_execution_registry.dart` | Contextos por `runId` (substitui singletons). |
| `diagnostics_message_handler.dart` | Logs/error/artifactMetadata/cleanupStaging. |
| `real_diagnostics_provider.dart` | Resolve `runId` → BackupHistory/Log + staging por path `remote/<runId>/` ou `remote/<scheduleId>/` (legado). |
| `file_transfer_message_handler.dart` | Chunked transfer + resume + lease lock. |
| `remote_staging_artifact_ttl.dart` | TTL 24h + `410 ARTIFACT_EXPIRED`. |

### Client (`lib/infrastructure/socket/client/` + providers)

| Arquivo | Responsabilidade |
|---|---|
| `tcp_socket_client.dart` | Conexão TCP com auto-reconnect. |
| `socket_client_service.dart` | Parser + dispatcher. |
| `connection_manager.dart` | API completa: capabilities/health/session/preflight, schedule CRUD remoto, database CRUD, `startRemoteBackup`/`executeRemoteBackup`/`cancelRemoteBackup`, `getExecutionStatus`, `getExecutionQueue`, `cancelQueuedRemoteBackup`, `getRunLogs`/`getRunErrorDetails`/`getArtifactMetadata`/`cleanupRemoteStaging`, `attachRemoteBackupListener` (M8.4). |
| `backup_event_deduplicator.dart` | Dedup por `eventId` + ordenação por `sequence`/runId. |
| `file_transfer_resume_metadata_store.dart` | Persistência de resume (hoje só com `scheduleId` — pendente PR-6). |

### Application services e bootstrap

| Arquivo | Responsabilidade |
|---|---|
| `lib/application/services/scheduler_service.dart` | Timer local (configurável via `local_schedule_timer_enabled`); aceita `executionOrigin` (`local`/`remoteCommand`); reconcile stale-running 24h no boot. |
| `lib/application/services/backup_orchestrator_service.dart` | Pipeline dump/compactação/checksum/staging; preenche `BackupHistory.runId` via `LogContext.runId`. |
| `lib/presentation/boot/service_mode_initializer.dart` | 11 steps: env → app mode → instance lock → DI → IPC → event log → shutdown handler → scheduler/health/queue/staging cleanup/socket → auto-update. |
| `lib/infrastructure/transfer_staging_cleanup_scheduler.dart` | `RemoteStagingCleanupScheduler` — 1h ticks → `cleanupOldBackups`. |
| `lib/infrastructure/cleanup/temporary_backup_cleanup_scheduler.dart` | Local backup temp cleanup. |
| `lib/infrastructure/file_transfer_lock_service.dart` | Lease v1 JSON com `owner`/`runId`/`acquiredAt`/`expiresAt`. |
| `lib/application/providers/remote_file_transfer_provider.dart` | Download + cleanup **remoto** via `connectionManager.cleanupRemoteStaging`. |

### ADRs (`docs/adr/`)

| ADR | Decisão |
|---|---|
| 001 | Modelo híbrido scheduler (`executionOrigin` + `local_schedule_timer_enabled`). |
| 002 | Transferência v1 streaming sem `fileAck`. |
| 003 | Versionamento em 2 níveis (wire + lógico) + política de compat. |
| 004 | Ports hexagonais para SGBDs (template). |
| 014 | Firebird CLI assumptions. |

---

## Comportamentos garantidos (invariantes)

1. **Nenhuma mensagem operacional aceita pré-auth** (allowlist: `authRequest`/`heartbeat`/`disconnect`/`error`). Resposta: `401 NOT_AUTHENTICATED`.
2. **Toda resposta de inspeção carrega `statusCode` + `success`** (envelope F0.5 aditivo top-level).
3. **Todo erro carrega `errorCode` + `statusCode`** (F0.6).
4. **Wire version desconhecida** → `UNSUPPORTED_PROTOCOL_VERSION` + disconnect.
5. **Payload acima do limite por tipo** → `PAYLOAD_TOO_LARGE` + disconnect.
6. **Rate limit excedido** → `RATE_LIMIT_EXCEEDED` (429) com `retryAfterSeconds`.
7. **Backup já running** + `queueIfBusy=false` → `409 BACKUP_ALREADY_RUNNING`.
8. **Backup já running** + `queueIfBusy=true` → enfileira ou `503 QUEUE_FULL` (decisão PR-6 ratificada).
9. **Idempotency**: 8 comandos mutáveis exigem `idempotencyKey` (F2.14). Repetição dentro de TTL retorna mesmo resultado (sobrevive a restart via Drift).
10. **Re-sync após reconexão**: `attachRemoteBackupListener(runId)` recupera eventos pendentes do buffer + reassina stream sem perder ownership (M8.4).
11. **Artefato expirado** (>24h ou TTL custom) → `410 ARTIFACT_EXPIRED`.
12. **Staging >= 10 GiB** → `503 STAGING_FULL` em `startBackup`. >= 5 GiB → health `degraded`.
13. **Eventos `backupProgress/Complete/Failed`** carregam `runId` opcional (servidor v2+), `eventId`, `sequence` para dedup/ordenação cliente.
14. **Firebird via socket remoto** rejeitado por servidor sem `supportsFirebird` com `UNSUPPORTED_DATABASE_TYPE` (400).
15. **Cleanup de staging é remoto**: cliente NÃO chama `_transferStagingService.cleanupStaging` localmente.
16. **Stale running (>24h)** reconciliado para `error` no boot do scheduler.

---

## O que NÃO está garantido (ver backlog)

- Watchdog em **runtime** (orchestrator travado sem crash → registro `running` até próximo boot).
- TTL em **itens enfileirados** (`queued` para sempre se não drenar).
- Cancelamento publica **`backupFailed`** (não `backupCancelled` distinto).
- `runId` no **histórico local de transferência** (`FileTransfersTable.scheduleId` apenas).
- Resume metadata **valida `runId`** ao continuar download.
- Audit log **persiste em DB** (hoje só memória + log).
- Preflight Sybase log backup.
- `ExecutionStateMachine.enforceTransition` **chamada** em handlers (hoje só tabela + testes).

---

## Convenções de log e correlação

- `LoggerService.infoWithContext` propaga `clientId`/`requestId`/`runId`/`scheduleId`.
- `LogContext.setContext` no início de `_executeScheduledBackup` cobre o pipeline inteiro.
- `SocketServerTelemetry` registra histograma `socket_request_duration_<type>_ms` e contador `socket_error_total_<errorCode>` via `IMetricsCollector`.
- `BackupHistory.runId` (Drift v31+) permite reidratação por `getExecutionStatus` após registry limpo.
