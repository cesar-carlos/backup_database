# Execucao remota (servidor socket)

Contrato vivo do modo `server` / `client`: protocolo TCP, handlers e
invariantes. Leia isto para saber **como o produto funciona hoje**.

Planos datados em `docs/notes/` sao historico. ADRs 001–003 e 017
explicam o *por que*; este arquivo descreve o *o que esta no codigo*.

Atualizado em: 2026-08-30.

## Baseline

| Metrica | Valor |
| --- | --- |
| Drift `schemaVersion` | **36** (v34 watchdog/fila/`runId` em transferencias; v35 audit persistente; v36 `licenses.not_before`) |
| `kCurrentWireVersion` | `1` (header binario 16 bytes + CRC32) |
| `kCurrentProtocolVersion` | **2** (aditivo Firebird remoto; PR-6 nao bumpou versao logica) |
| Capability flags | 6 (`supportsRunId`, `supportsResume`, `supportsArtifactRetention`, `supportsChunkAck`, `supportsExecutionQueue`, `supportsFirebird`) + `supportsAsyncStart` |
| `maxConcurrentBackups` | `1` (constante permanente em v1; mudar exige ADR) |
| Idempotency TTL | 1 h (`IdempotencyPolicy.defaultTtl`), persistido em Drift |

`supportsChunkAck` e anunciado pelo servidor, mas o cliente **nao**
implementa janela deslizante — ver [ADR-017](../adr/017-defer-file-transfer-sliding-window.md).

## Como o servidor se organiza

Tres pastas, uma responsabilidade cada:

| Pasta | Papel |
| --- | --- |
| `lib/infrastructure/protocol/` | Contrato: `MessageType`, payloads, `ErrorCode`, envelope, versoes, idempotencia |
| `lib/infrastructure/socket/server/` | Aceita conexoes, autentica, roteia, executa, filas, staging, telemetria |
| `lib/infrastructure/socket/client/` | Cliente: `ConnectionManager` (fachada) + RPCs por dominio |

A fachada GetIt **nao muda** quando um handler interno e extraido.
Novos tipos de protocolo entram no fim do `MessageType` (wire-compat).

### Protocolo

| Arquivo | Responsabilidade |
| --- | --- |
| `binary_protocol.dart` | Wire format. Rejeita wire version desconhecida. |
| `protocol_versions.dart` | `kCurrentWireVersion`, `kCurrentProtocolVersion`, `isWireVersionSupported` |
| `message.dart`, `message_types.dart` | Envelope + enum (70 tipos; `backupCancelled` e o mais recente) |
| `error_codes.dart` | 30 `ErrorCode` (auth, IO, staging, fila, watchdog, estado, protocolo) |
| `status_codes.dart` | `ErrorCode` → HTTP-like + `isRetryable` |
| `response_envelope.dart` | `wrapSuccessResponse` nas respostas de inspecao |
| `idempotency_policy.dart` | 8 tipos mutaveis exigem `idempotencyKey` |
| `idempotency_store.dart` | `DriftIdempotencyStore` — sobrevive a restart |
| `capabilities_messages.dart` | Flags `supports*` + `chunkSize` / `compression` / `serverTimeUtc` |
| `execution_messages.dart` | `startBackup` / `cancelBackup` nao-bloqueantes |
| `schedule_messages.dart` | Eventos de progresso, inclusive `backupCancelled` |
| `file_transfer_messages.dart` | Chunks + resume + `runId` opcional |
| `diagnostics_messages.dart` | Logs, erro, metadata de artefato, cleanup de staging |

### Servidor

`TcpSocketServer` roteia para handlers. Autenticacao, rate limit e
validacao de payload ficam no `ClientHandler` **antes** do dispatch.

| Area | Arquivos |
| --- | --- |
| Handshake | `server_authentication.dart`, `capabilities_message_handler.dart`, `session_message_handler.dart`, `health_message_handler.dart`, `preflight_message_handler.dart` |
| Execucao | `execution_message_handler.dart`, `execution_state_machine.dart` (`enforceTransition` **e chamado**), `remote_execution_registry.dart`, `execution_event_sequencer.dart` |
| Fila | `execution_queue_service.dart` (FIFO, dedup por `scheduleId`, `maxQueueSize=50`, TTL 30 min), `execution_queue_housekeeping_scheduler.dart`, `queue_event_bus.dart` |
| Schedule | `schedule_message_handler.dart` (legado bloqueante `executeSchedule`), `schedule_crud_message_handler.dart` |
| Banco remoto | `database_config_message_handler.dart`, `real_database_config_store.dart`, `real_database_connection_prober.dart` |
| Transferencia | `file_transfer_message_handler.dart`, `remote_staging_artifact_ttl.dart` (TTL 24 h → `410 ARTIFACT_EXPIRED`) |
| Diagnostico | `diagnostics_message_handler.dart`, `real_diagnostics_provider.dart` |
| Observabilidade | `socket_server_telemetry.dart`, `audit_retention_scheduler.dart` (30 dias), `socket_rate_limiter.dart` |
| Preflight | `server_preflight_checks.dart`: `compression_tool`, `temp_dir_writable`, `disk_space`, `sybase_log_backup` |

### Cliente

`ConnectionManager` continua sendo a API de UI/providers. A implementacao
esta fatiada em:

- `remote_session_rpc.dart` — capabilities, health, session, preflight
- `remote_schedule_rpc.dart` — CRUD de schedule remoto
- `remote_database_config_rpc.dart` — CRUD de config de banco
- `remote_backup_stream_client.dart` — `startRemoteBackup`, eventos, cancel
- `remote_diagnostics_rpc.dart` — logs, artifact, cleanup de staging
- `remote_file_transfer_client.dart` — download com resume
- `backup_event_deduplicator.dart` — dedup por `eventId` + `sequence`
- `file_transfer_resume_metadata_store.dart` — resume valida `runId`

Fluxo moderno: `startRemoteBackup` (nao-bloqueante). `executeSchedule`
legado permanece para servidor/cliente `v1` sem `supportsRunId`.

### Scheduler no host servidor

- `SchedulerService` + `scheduler/scheduler_watchdog.dart`: heartbeat
  10 min sem progresso → `RUN_WATCHDOG_TIMEOUT`; duracao > 6 h →
  `RUN_HARD_TIMEOUT`.
- Reconcile de `running` > 24 h no boot.
- `executionOrigin` `local` vs `remoteCommand` (ADR-001).
- Timer local desligavel via `local_schedule_timer_enabled`.

## Invariantes

1. Mensagem operacional pre-auth → `401 NOT_AUTHENTICATED` (allowlist:
   `authRequest`, `heartbeat`, `disconnect`, `error`).
2. Resposta de inspecao carrega `statusCode` + `success`.
3. Todo erro carrega `errorCode` + `statusCode`.
4. Wire version desconhecida → `UNSUPPORTED_PROTOCOL_VERSION` + disconnect.
5. Payload acima do limite do tipo → `PAYLOAD_TOO_LARGE` + disconnect.
6. Rate limit → `429 RATE_LIMIT_EXCEEDED` com `retryAfterSeconds`.
7. Backup ja `running` + `queueIfBusy=false` → `409 BACKUP_ALREADY_RUNNING`.
8. Backup ja `running` + `queueIfBusy=true` → enfileira ou `503 QUEUE_FULL`.
9. Oito comandos mutaveis exigem `idempotencyKey`; repeticao no TTL
   devolve o mesmo resultado (sobrevive a restart).
10. `attachRemoteBackupListener(runId)` reconstroi eventos apos reconnect.
11. Artefato > 24 h (ou TTL custom) → `410 ARTIFACT_EXPIRED`.
12. Staging ≥ 10 GiB → `503 STAGING_FULL` em `startBackup`. ≥ 5 GiB →
    health `degraded`.
13. Eventos de backup carregam `runId`, `eventId`, `sequence`. Cancel
    manual publica **`backupCancelled`**, nao `backupFailed`.
14. Firebird remoto sem `supportsFirebird` → `400 UNSUPPORTED_DATABASE_TYPE`.
15. Cleanup de staging e **remoto** (`cleanupRemoteStaging`). O cliente
    nao apaga staging local do servidor.
16. Transicao invalida de execucao → `409 INVALID_STATE_TRANSITION`.
17. Item `queued` sem drain em 30 min → `410 QUEUED_TTL_EXPIRED`.
18. Resume de download descarta parcial se `runId` da metadata diferir.

## PR-6 (entregue)

A auditoria de 2026-05-27 listou A1–A8 como abertos. Todos estao no
codigo (schema v34–v35 + testes em `test/integration/pr6_resilience_test.dart`):

| Item | Entrega |
| --- | --- |
| A1 `enforceTransition` | Chamado em start/cancel/drain de `ExecutionMessageHandler` |
| A2 `backupCancelled` | `MessageType.backupCancelled` + notifier `onCancelled` |
| A3 Watchdog runtime | `SchedulerWatchdog` + `lastProgressAt` |
| A4 TTL da fila | `expiresAt` + housekeeping no bootstrap do servico |
| A5 `runId` em transferencia | Coluna Drift + validacao no resume metadata |
| A6 Audit persistente | `MutableCommandAuditTable` + retencao 30 dias |
| A7 Preflight Sybase log | Check `sybase_log_backup` em `buildServerPreflightChecks` |
| A8 Testes de resiliencia | Fila concorrente, restart da fila, resume com `runId` distinto |

## Fora do contrato atual

Nao implementar sem ADR (ou PR dedicado, no caso de remocao ja
ratificada):

- `maxConcurrentBackups > 1`
- Remover `executeSchedule` legado (ainda necessario para cliente v1)
- Sliding window / `fileAck` (ADR-017, adiado)
- Rate limit por endpoint (hoje e por cliente)
- Cliente v3 com WebSocket no lugar do stream binario
- `ErrorCode`s do plano original sem equivalente real:
  `QUEUED_BACKUP_NOT_FOUND`, `PRECONDITION_FAILED`,
  `FEATURE_NOT_AVAILABLE`, `DB_CONNECTION_TEST_FAILED`

## Onde aprofundar

| Assunto | Documento |
| --- | --- |
| Scheduler hibrido | [ADR-001](../adr/001-modelo-hibrido-scheduler.md) |
| Transferencia sem `fileAck` | [ADR-002](../adr/002-transferencia-v1-streaming-sem-fileack.md) |
| Versionamento wire vs logico | [ADR-003](../adr/003-versionamento-protocolo.md) |
| Sliding window adiado | [ADR-017](../adr/017-defer-file-transfer-sliding-window.md) |
| Goldens do envelope JSON | `test/golden/protocol/README.md` |
| Plano original (historico) | `docs/notes/archive/` |
