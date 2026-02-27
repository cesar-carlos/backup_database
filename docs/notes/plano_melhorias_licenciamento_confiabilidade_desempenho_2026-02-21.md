# Plano de Melhorias: Licenciamento, Confiabilidade e Desempenho

Data base: 2026-02-21  
Status: Concluido (Fases 0-6)  
Escopo: servidor + cliente (Flutter desktop)

**Implementacao**: Todas as fases F0-F6 foram entregues. Restam apenas checklists operacionais (F6.3) e de qualidade por PR, a serem executados no deploy e em cada merge.

## Objetivo Geral

1. Garantir enforcement de licenca no dominio (nao apenas na UI).
2. Elevar confiabilidade operacional em execucoes locais e remotas.
3. Melhorar desempenho de validacao, backup e transferencia.

## Regras do Projeto Consideradas (.cursor/rules)

- [x] Respeitar fronteiras de Clean Architecture (domain nao depende de infrastructure/presentation).
- [x] Manter DI via `get_it`, estado via `Provider` e erros via `result_dart`.
- [x] Evitar duplicacao de logica de licenca (centralizar em service/policy).
- [x] Aplicar null safety e contratos explicitos em APIs novas.
- [x] Cobrir alteracoes com testes unitarios/integracao (padrao AAA).
- [x] Evitar magic numbers (constantes nomeadas para timeout, retry, TTL, limites).

## Diagnostico Consolidado

- [x] Bloqueios premium em parte concentrados na UI. (F1: policy em dominio)
- [x] Ausencia de gate unico de licenca em create/update/execute de schedule. (F1)
- [x] Possivel duplicidade de licenca por `deviceKey`. (F2: unicidade + upsert)
- [x] Fallback hardcoded de segredo de licenca.
- [x] Caminho fail-open em notificacao de e-mail.
- [x] Oportunidade de melhorar throughput em upload para multiplos destinos. (F5.3: paralelismo)
- [x] Consultas com potencial N+1 em carregamento de schedules e destinos relacionados. (F5.7)
- [x] Scheduler busca todos os agendamentos ativos e varre em memoria a cada ciclo. (F5.9: query no banco)
- [x] Tabelas criticas sem plano explicito de indices para padroes de consulta frequentes. (F2.5)
- [x] Pontos com `currentLicense!` podem gerar falha de runtime em cenarios de estado inconsistente.
- [x] Conexao remota cliente -> servidor ainda sem gate explicito por licenca. (F1.8)

## Entrega Aplicada em 2026-02-21 (Socket/Auth)

- [x] Bloqueio de conexao remota no servidor quando a licenca nao libera `remote_control`.
- [x] Resposta clara no `authResponse` com motivo da recusa (`error` + `errorCode`).
- [x] Propagacao da mensagem de falha para o cliente (fluxo de conexao e teste de conexao).
- [x] Registro de tentativa de conexao com motivo real de bloqueio no log de conexoes.
- [x] Cobertura de testes ajustada para novo contrato de autenticacao.

## Entrega Aplicada em 2026-02-27 (Fase 0 + Fase 1 + Fase 2)

### Fase 0 (concluída)

- [x] F0.1: Fail-closed em `_isEmailNotificationAllowed` (excecao retorna false).
- [x] F0.2: Removido fallback `BACKUP_DATABASE_LICENSE_SECRET_2024`; app falha com StateError se segredo nao obtido.
- [x] F0.3: Upsert em `validateAndSaveLicense` (getByDeviceKey -> update ou create).
- [x] F0.4: Testes para fail-closed, licenca em sendTestEmail/testEmailConfiguration, upsert de licenca.
- [x] F0.5: `sendTestEmail` e `testEmailConfiguration` verificam licenca antes de enviar.
- [x] F0.6: Eliminado `currentLicense!` em notifications_page, schedule_dialog, destination_dialog (null-safe).

### Fase 1 (concluída)
- [x] F1.1: `LicensePolicyService` em application com validateScheduleCapabilities, validateDestinationCapabilities, validateExecutionCapabilities.
- [x] F1.2: Policy aplicada em CreateSchedule e UpdateSchedule (carregam destinos e validam antes de persistir).
- [x] F1.3: Policy aplicada em ScheduleMessageHandler para update (via UpdateSchedule) e execute (validacao antes de _executeBackup).
- [x] F1.4: Policy aplicada em DestinationProvider.createDestination e updateDestination (validateDestinationCapabilities antes de persistir).
- [x] F1.5: Policy aplicada em SchedulerService._executeScheduledBackup (validateExecutionCapabilities antes de executeBackup).
- [x] F1.6: Testes unitários para bypass remoto (ScheduleMessageHandler, DestinationProvider create/update).
- [x] F1.7: Validação de licença para destinos consolidada em ILicensePolicyService.validateDestinationCapabilities (SendFileToDestinationService, DestinationOrchestratorImpl, BackupCleanupServiceImpl).

### Fase 2 (concluída)

- [x] F2.1–F2.5: Unicidade por deviceKey, migração v25, upsertByDeviceKey, teste de migração, índices críticos (schedules, backup_history, backup_logs).

### Fase 3 (concluída em 2026-02-27)

- [x] F3.1–F3.6: Ed25519 para v2, chave pública via env, formato versionado, compatibilidade v1/v2, testes criptográficos.

### Fase 4 (concluída em 2026-02-27)

- [x] F4.1: Retry com backoff exponencial + jitter para destinos remotos (FTP, Google Drive, Dropbox, Nextcloud).
- [x] F4.2: Circuit breaker por destino (falhas transitivas abrem circuito; recuperação após 60s).
- [x] F4.3: Padronizar timeout e cancelamento cooperativo por etapa.
- [x] F4.4: Introduzir idempotência por runId em logs/histórico/upload.
- [x] F4.5: Definir catálogo de erros com códigos estáveis.
- [x] F4.6: Testes de resiliência (falha transitiva, timeout, cancelamento, repetição).
- [x] F4.7: Formalizar máquina de estados de BackupHistory (running → success/error/warning).
- [x] F4.8: Garantir atualizações idempotentes e atômicas de histórico + logs em pontos de falha.

### Fase 5 (concluída em 2026-02-27)

- [x] F5.1: Cache de licença com TTL e invalidação.
- [x] F5.2: Memoização de checks por runId.
- [x] F5.3: Paralelismo controlado para upload a múltiplos destinos.
- [x] F5.4: Chunk size/streaming por destino remoto.
- [x] F5.5-F5.6: Medição P95 e testes de carga.
- [x] F5.7-F5.9: Eliminar N+1, busca em lote de destinos, query vencidos no banco.

### Fase 6 (concluída em 2026-02-27)

- [x] F6.1: Instrumentação de métricas (license_denied_total, schedule_update_rejected_total, backup_run_duration_ms, destination_upload_duration_ms, destination_upload_failure_total, email_notification_skipped_license_total). IMetricsCollector, MetricsCollector, snapshot em MetricsMessageHandler.
- [x] F6.2: Logs estruturados com runId e scheduleId (LogContext, LoggerService, BackupLogRepository).
- [x] F6.3: Checklist de rollout/rollback por fase.
- [x] F6.4: Critérios de prontidão para liberar cada fase.

## Fase 0 - Baseline e Seguranca Rapida (1-2 dias)

Objetivo: remover riscos imediatos.

- [x] F0.1 Trocar fail-open para fail-closed em notificacoes por e-mail.  
  Arquivo alvo: `lib/application/services/notification_service.dart`
- [x] F0.2 Remover fallback hardcoded de segredo de licenca.  
  Arquivo alvo: `lib/core/di/core_module.dart`
- [x] F0.3 Ajustar fluxo de persistencia de licenca para update/upsert (evitar insert cego).  
  Arquivo alvo: `lib/application/providers/license_provider.dart`
- [x] F0.4 Criar testes para F0.1-F0.3.
- [x] F0.5 Aplicar mesma politica de licenca para `sendTestEmail` e `testEmailConfiguration`.
  Arquivo alvo: `lib/application/services/notification_service.dart`
- [x] F0.6 Eliminar uso inseguro de `currentLicense!` em telas criticas (null-safe guard).
  Arquivos alvo:
  - `lib/presentation/pages/notifications_page.dart`
  - `lib/presentation/widgets/schedules/schedule_dialog.dart`
  - `lib/presentation/widgets/destinations/destination_dialog.dart`

DoD da Fase 0:
- [x] Nenhum envio de e-mail ocorre quando validacao de licenca falhar por excecao.
- [x] App nao aceita segredo de fallback fixo.
- [x] Nao ha criacao repetida de licenca para o mesmo dispositivo no fluxo normal.
- [x] Fluxos de teste SMTP seguem a mesma regra de licenca definida para envio operacional.
- [x] UI nao quebra com estado nulo de licenca.

## Fase 1 - Enforcement de Dominio (3-5 dias)

Objetivo: impedir bypass por payload remoto, uso de provider ou alteracao de UI.

- [x] F1.1 Implementar `LicensePolicyService` na camada de aplicacao.  
  API inicial:  
  - `validateScheduleCapabilities(Schedule)`  
  - `validateDestinationCapabilities(BackupDestination)`  
  - `validateExecutionCapabilities(Schedule, List<BackupDestination>)`
- [x] F1.2 Aplicar policy em create/update de schedule.  
  Arquivos alvo:  
  - `lib/domain/use_cases/scheduling/create_schedule.dart`  
  - `lib/domain/use_cases/scheduling/update_schedule.dart`
- [x] F1.3 Aplicar policy no caminho remoto (socket).  
  Arquivo alvo: `lib/infrastructure/socket/server/schedule_message_handler.dart`
- [x] F1.4 Aplicar policy em create/update de destino.  
  Arquivo alvo: `lib/application/providers/destination_provider.dart`
- [x] F1.5 Aplicar policy antes da execucao real.  
  Arquivo alvo: `lib/application/services/scheduler_service.dart`
- [x] F1.6 Testes unitarios para bypass remoto.
  Arquivos: `test/unit/infrastructure/socket/server/schedule_message_handler_test.dart`, `test/unit/application/providers/destination_provider_test.dart`
- [x] F1.7 Consolidar validacao de licenca para destinos em ILicensePolicyService.
  Arquivos alterados:
  - `lib/application/services/send_file_to_destination_service.dart`
  - `lib/infrastructure/destination/destination_orchestrator_impl.dart`
  - `lib/infrastructure/cleanup/backup_cleanup_service_impl.dart`
- [x] F1.8 Aplicar gate de licenca no handshake de autenticacao remota (antes de aceitar cliente).
  Arquivos alvo:
  - `lib/infrastructure/socket/server/server_authentication.dart`
  - `lib/infrastructure/socket/server/client_handler.dart`
  - `lib/infrastructure/socket/server/tcp_socket_server.dart`
  - `lib/infrastructure/socket/client/tcp_socket_client.dart`
  - `lib/infrastructure/socket/client/connection_manager.dart`
  - `lib/application/providers/server_connection_provider.dart`
  - `lib/infrastructure/protocol/auth_messages.dart`
  - `lib/infrastructure/protocol/error_codes.dart`
  - `lib/core/constants/license_features.dart`

DoD da Fase 1:
- [x] Recurso premium sem licenca e rejeitado em create/update/execute.
- [x] Fluxo remoto recebe erro consistente e nao persiste alteracao invalida.
- [x] Mensagens de erro sao claras e rastreaveis.
- [x] Cliente recebe motivo explicito quando conexao e negada por licenca.
- [x] Regra de licenca para destinos existe em um unico componente reutilizavel (ILicensePolicyService).

## Fase 2 - Integridade de Dados de Licenca (2-3 dias)

Objetivo: garantir consistencia no armazenamento local.

- [x] F2.1 Adicionar unicidade por `deviceKey` na tabela de licenca.  
  Arquivos alvo:  
  - `lib/infrastructure/datasources/local/tables/licenses_table.dart`  
  - `lib/infrastructure/datasources/local/database.dart`
- [x] F2.2 Criar migracao para saneamento de duplicatas existentes.
- [x] F2.3 Implementar `upsertByDeviceKey` no DAO/repositorio.  
  Arquivos alvo:  
  - `lib/infrastructure/repositories/license_repository.dart`  
  - `lib/application/providers/license_provider.dart`
- [x] F2.4 Cobrir migracao com teste de integracao local DB.  
  Arquivo: `test/unit/infrastructure/datasources/local/database_migration_v25_test.dart`
- [x] F2.5 Adicionar indices para consultas criticas de scheduler, historico e logs.  
  Indices em `_createCriticalQueryIndexes()`:
  - `idx_schedules_enabled_next_run` em `schedules_table(enabled, next_run_at)`
  - `idx_backup_history_schedule_started` em `backup_history_table(schedule_id, started_at)`
  - `idx_backup_history_status_started` em `backup_history_table(status, started_at)`
  - `idx_backup_logs_history_created` em `backup_logs_table(backup_history_id, created_at)`
  - `idx_backup_logs_level_created` em `backup_logs_table(level, created_at)`

DoD da Fase 2:
- [x] Banco nao permite duas licencas para o mesmo `deviceKey`.
- [x] Base antiga migra sem perda da licenca valida mais recente.
- [x] Consultas de leitura frequente apresentam plano de acesso indexado.

## Fase 3 - Hardening Criptografico (4-6 dias)

Objetivo: reduzir superficie de forja/manipulacao de licenca.

- [x] F3.1 Migrar validacao para assinatura assimetrica (Ed25519 recomendado).
  - `Ed25519LicenseVerifier`, `LicenseDecoder` com suporte v1 (HMAC) e v2 (Ed25519).
- [x] F3.2 Embarcar somente chave publica no app.
  - Chave publica via env `BACKUP_DATABASE_LICENSE_PUBLIC_KEY` (base64).
- [x] F3.3 Versionar formato da licenca (`licenseVersion`, `issuedAt`, `notBefore`, `issuer`, `keyId`).
  - Formato v2: licenseVersion=2, deviceKey, allowedFeatures, expiresAt, notBefore, issuedAt, issuer, keyId.
- [x] F3.4 Garantir compatibilidade de leitura v1/v2 durante transicao.
  - Decoder tenta v2 primeiro (por licenseVersion), fallback para v1 (HMAC).
- [x] F3.5 Definir suporte opcional a revogacao assinada.
  - `IRevocationChecker` em domain; `SignedRevocationListService` em infrastructure.
  - Lista assinada Ed25519: `{ "data": { "revokedDeviceKeys": [...], "issuedAt", "expiresAt" }, "signature" }`.
  - Env: `BACKUP_DATABASE_LICENSE_REVOCATION_LIST` (base64) ou `BACKUP_DATABASE_LICENSE_REVOCATION_LIST_PATH` (arquivo).
  - Verificacao em `LicenseGenerationService.createLicenseFromKey` e `LicenseValidationService.getCurrentLicense`/`validateLicense`.
  - Testes em `signed_revocation_list_service_test.dart`.
- [x] F3.6 Testes criptograficos: assinatura valida, invalida, expiracao e device mismatch.
  - `test/unit/application/services/license_decoder_test.dart`.

DoD da Fase 3:
- [x] Licenca assinada indevidamente nao passa na validacao.
- [x] Licencas legadas continuam funcionando no periodo de migracao definido.

## Fase 4 - Confiabilidade Operacional (3-5 dias)

Objetivo: melhorar comportamento sob falhas intermitentes.

- [x] F4.1 Implementar retry com backoff exponencial + jitter para destinos remotos.
  - `executeResultWithRetry` em `lib/core/utils/retry_utils.dart`
  - `DestinationRetryConstants` em `lib/core/constants/destination_retry_constants.dart`
  - Aplicado em FTP, Google Drive, Dropbox, Nextcloud em `DestinationOrchestratorImpl`
  - Retry apenas em falhas transitivas (timeout, connection, 5xx)
- [x] F4.2 Implementar circuit breaker por destino.
  - `CircuitBreaker` e `CircuitBreakerRegistry` em `lib/core/utils/circuit_breaker.dart`
  - Estados: closed, open, halfOpen; abre após 3 falhas transitivas; recupera após 60s
  - Aplicado em FTP, Google Drive, Dropbox, Nextcloud em `DestinationOrchestratorImpl`
- [x] F4.3 Padronizar timeout e cancelamento cooperativo por etapa.
  - `StepTimeoutConstants` em `destination_retry_constants.dart` (uploadFtp, uploadHttp, compression, backupDefault, verifyDefault).
  - Timeouts padronizados em FTP, WinRAR (compressão).
  - `isCancelled` opcional em `IDestinationOrchestrator.uploadToDestination` e `uploadToAllDestinations`.
  - Cancelamento cooperativo: verificação em FTP (onProgress), início de cada upload em todos os destinos.
  - Scheduler passa `isCancelled` ao chamar `uploadToDestination`.
- [x] F4.4 Introduzir idempotencia por `runId` em logs/historico/upload.
  - `createIdempotent` em IBackupLogRepository: log com step determinístico (id = runId_step), insertOrReplace.
  - `updateIfRunning` em IBackupHistoryRepository: atualiza apenas quando status = 'running'.
  - `LogStepConstants` para steps padronizados (backup_started, upload_failed, cleanup_error_*).
  - BackupOrchestratorService, SchedulerService, BackupCleanupServiceImpl usam logs idempotentes e updateIfRunning.
- [x] F4.5 Definir catalogo de erros com codigos estaveis.
  - `FailureCodes` em `lib/core/errors/failure_codes.dart`.
  - Códigos aplicados em DestinationOrchestrator, SchedulerService, BackupOrchestrator, LicensePolicyService, BackupCleanupService, FtpDestinationService.
  - `isRetryableFailure` considera códigos não-retentáveis.
- [x] F4.6 Testes de resiliencia (falha transitiva, timeout, cancelamento, repeticao).
  - `retry_utils_test.dart`: isRetryableFailure para uploadCancelled, backupCancelled, validationFailed; executeResultWithRetry não retenta em cancelamentos.
  - `circuit_breaker_test.dart`: transição half-open após openDuration, half-open→closed em sucesso, half-open→open em falha.
  - `destination_orchestrator_resilience_test.dart`: cancelamento imediato retorna uploadCancelled; circuit breaker aberto retorna circuitBreakerOpen; falha transitiva com retry e sucesso.
- [x] F4.7 Formalizar maquina de estados de `BackupHistory` (running -> success/error/warning) com transicoes validas.
  - `BackupHistoryStateMachine` em `lib/domain/value_objects/backup_history_state_machine.dart`: isTerminal, canTransition, canTransitionFrom.
  - Transições válidas: running → success, error, warning. Estados terminais: success, error, warning.
  - `BackupHistoryRepository.updateIfRunning` valida que o status de destino é terminal; rejeita status=running.
  - Testes em `backup_history_state_machine_test.dart` e `backup_history_repository_test.dart`.
- [x] F4.8 Garantir atualizacoes idempotentes e atomicas de historico + logs em pontos de falha.
  - `updateHistoryAndLogIfRunning` em IBackupHistoryRepository: transação atômica (updateIfRunning + createIdempotent log).
  - BackupLogRepository.buildIdempotentLogCompanion para uso na transação.
  - BackupOrchestratorService e SchedulerService usam updateHistoryAndLogIfRunning nos pontos de falha (success, error, backup_file_not_found, upload_failed, backup_cancelled).
  - LogStepConstants: backupFileNotFound, backupCancelled.

Arquivos candidatos:
- `lib/application/services/scheduler_service.dart`
- `lib/application/services/send_file_to_destination_service.dart`
- `lib/infrastructure/destination/destination_orchestrator_impl.dart`
- `lib/infrastructure/cleanup/backup_cleanup_service_impl.dart`

DoD da Fase 4:
- [x] Recuperacao automatica de falhas transitivas sem duplicar efeito colateral. (F4.1 retry + F4.2 circuit breaker)
- [x] Logs e metricas permitem diagnostico rapido de causa raiz. (F6.1 metricas + F6.2 logs estruturados)
- [x] Nao existem transicoes de estado invalidas no historico de backup. (F4.7 maquina de estados + F4.8 updateIfRunning)

## Fase 5 - Desempenho e Escalabilidade (3-5 dias)

Objetivo: reduzir latencia e custo de execucao.

- [x] F5.1 Cache em memoria da licenca atual com TTL curto e invalidacao por update.
  - `LicenseCacheConstants` em `lib/core/constants/license_cache_constants.dart` (TTL 5s).
  - `CachedLicenseValidationService` em `lib/application/services/cached_license_validation_service.dart`: cache por deviceKey, TTL configurável, `invalidateLicenseCache()`.
  - `ILicenseCacheInvalidator` para invalidação explícita.
  - LicenseProvider chama `invalidateLicenseCache()` após `validateAndSaveLicense` com sucesso.
  - Testes em `cached_license_validation_service_test.dart` e `license_provider_test.dart`.
- [x] F5.2 Memoizacao de checks de feature por execucao (`runId`).
  - `setRunContext(String? runId)` e `clearRunContext()` em ILicensePolicyService.
  - LicensePolicyService: cache por feature dentro do runId; _isFeatureAllowed usa cache quando runContext ativo.
  - SchedulerService._executeScheduledBackup: setRunContext no início, clearRunContext em finally.
  - Testes em `license_policy_service_memoization_test.dart` e `scheduler_service_test.dart`.
- [x] F5.3 Paralelismo controlado para envio a multiplos destinos.
  - `UploadParallelismConstants.maxParallelUploads` (3) em `destination_retry_constants.dart`.
  - `uploadToAllDestinations` processa em lotes paralelos (Future.wait por batch).
  - Cancelamento entre lotes preenche resultados restantes com uploadCancelled.
  - SchedulerService usa `uploadToAllDestinations` em vez de loop sequencial.
  - Testes em `destination_orchestrator_resilience_test.dart`.
- [x] F5.4 Ajustar chunk size/streaming por destino remoto.
  - `UploadChunkConstants` em `destination_retry_constants.dart`: dropboxResumableChunkSize (4MB), localCopyChunkSize (1MB), httpUploadChunkSize (512KB).
  - `chunkedFileStream` em `lib/core/utils/file_stream_utils.dart` para leitura com chunk configurável.
  - Dropbox resumable, Local copy, Nextcloud e Google Drive usam constantes centralizadas.
- [x] F5.5 Medir e otimizar P95 por etapa (backup, compressao, upload, limpeza).
- [x] F5.6 Testes de carga basicos para comparativo antes/depois.
- [x] F5.7 Eliminar N+1 no `ScheduleRepository` ao montar `destinationIds` (carregamento em lote).
  Arquivos alvo:
  - `lib/infrastructure/repositories/schedule_repository.dart`
  - `lib/infrastructure/datasources/daos/schedule_destination_dao.dart`
- [x] F5.8 Otimizar obtencao de destinos no scheduler com busca em lote por IDs.
  Arquivo alvo: `lib/application/services/scheduler_service.dart`
- [x] F5.9 Mover filtro de agendamentos vencidos para query dedicada no banco (evitar scan completo em memoria).
  Arquivos alvo:
  - `lib/infrastructure/datasources/daos/schedule_dao.dart`
  - `lib/infrastructure/repositories/schedule_repository.dart`
  - `lib/application/services/scheduler_service.dart`

DoD da Fase 5:
- [x] Melhoria mensuravel de P95 em transferencia. (F5.5 medicao + F5.3 paralelismo + F5.4 chunk)
- [x] Sem regressao funcional nos fluxos criticos. (testes F5.6)
- [x] Reducao de consultas por ciclo do scheduler e por carregamento de schedules. (F5.7-F5.9)

## Fase 6 - Observabilidade e Operacao (2-3 dias)

Objetivo: fechar ciclo de monitoramento e governanca tecnica.

### Fase 6 (concluida em 2026-02-27)

- [x] F6.1 Instrumentar metricas:  
  - `license_denied_total` (LicensePolicyService - quando retorna Failure com licenseDenied)
  - `schedule_update_rejected_total` (UpdateSchedule - quando policy falha por licenca)
  - `backup_run_duration_ms` (SchedulerService - ao concluir backup com sucesso)
  - `destination_upload_duration_ms` (SchedulerService - apos uploadToAllDestinations)
  - `destination_upload_failure_total` (SchedulerService - por cada destino com falha no upload)
  - `email_notification_skipped_license_total` (NotificationService - quando _isEmailNotificationAllowed retorna false)
  - Arquivos: `IMetricsCollector`, `MetricsCollector`, `ObservabilityMetrics`, `MetricsMessageHandler` inclui snapshot em `payload['observability']`
- [x] F6.2 Padronizar logs estruturados com correlacao por `runId` e `scheduleId`.
  - `LogContext` em `lib/core/logging/log_context.dart`: setContext/clearContext com runId e scheduleId.
  - `LoggerService`: logs em arquivo incluem prefixo `[runId=...] [scheduleId=...]` quando contexto ativo.
  - `SchedulerService._executeScheduledBackup`: setContext no inicio, clearContext em finally.
  - `BackupLogRepository.createIdempotent` e `buildIdempotentLogCompanion`: details incluem runId e scheduleId quando LogContext ativo.
- [x] F6.3 Criar checklist de rollout/rollback por fase.
- [x] F6.4 Definir criterios de prontidao para liberar cada fase.

DoD da Fase 6:
- [x] Metricas expostas via MetricsMessageHandler.
- [x] Logs estruturados com runId e scheduleId (arquivo e DB).
- [x] Checklist de rollout/rollback e criterios de prontidao documentados.

## Priorizacao

P0 (seguranca funcional imediata):
- [x] Fase 0
- [x] Fase 1
- [x] Fase 2

P1 (hardening e resiliencia):
- [x] Fase 3
- [x] Fase 4

P2 (otimizacao e operacao):
- [x] Fase 5
- [x] Fase 6

## Sequencia de Execucao Recomendada

- [x] PR-1: Fase 0 (quick wins)
- [x] PR-2: Fase 1 (policy em dominio + remoto)
- [x] PR-3: Fase 2 (migracao e unicidade de licenca)
- [x] PR-4: Fase 3 (assinatura assimetrica + compatibilidade)
- [x] PR-5: Fase 4 (retry, breaker, timeout, idempotencia)
- [x] PR-6: Fase 5 (cache, memoizacao, paralelismo)
- [x] PR-7: Fase 6 (metricas, logs, rollout)

## F6.3 - Checklist de Rollout/Rollback por Fase

> **Nota**: Itens abaixo sao checklists operacionais a executar no momento do deploy, nao tarefas de implementacao.

### Antes do Rollout (por fase)
- [ ] Testes unitarios e de integracao passando.
- [ ] `flutter analyze` sem erros.
- [ ] Backup de banco de dados e configuracoes.
- [ ] Documentar variaveis de ambiente novas (ex: BACKUP_DATABASE_LICENSE_PUBLIC_KEY).
- [ ] Validar migracoes em ambiente de homologacao.

### Durante o Rollout
- [ ] Deploy em horario de baixo uso.
- [ ] Monitorar logs e metricas (MetricsMessageHandler).
- [ ] Ter janela de rollback definida (ex: 30 min).

### Rollback (por fase)
- [ ] Restaurar backup do banco se migracao aplicada.
- [ ] Reverter binario para versao anterior.
- [ ] Verificar que licencas e agendamentos continuam funcionando.
- [ ] Documentar incidente e causa raiz.

### Fases com migracao de banco (F2, F3)
- [ ] Migracao deve ser reversivel ou ter script de rollback.
- [ ] Testar rollback em homologacao antes do producao.

## F6.4 - Criterios de Prontidao para Liberar Cada Fase

| Fase | Criterio de Prontidao |
|------|------------------------|
| F0 | Fail-closed em email; sem fallback de segredo; upsert de licenca; testes passando. |
| F1 | Policy aplicada em create/update/execute; gate remoto; testes de bypass. |
| F2 | Unicidade deviceKey; migracao v25; indices criticos; teste de migracao. |
| F3 | Ed25519 v2; chave publica via env; compatibilidade v1/v2; testes criptograficos. |
| F4 | Retry, circuit breaker, timeout; idempotencia runId; maquina de estados; testes resiliencia. |
| F5 | Cache licenca; memoizacao runId; paralelismo upload; N+1 eliminado; query vencidos no banco. |
| F6 | Metricas instrumentadas; logs com runId/scheduleId; checklist rollout/rollback documentado. |

## Checklist de Qualidade por PR

> **Nota**: Itens a verificar em cada PR antes do merge.

- [ ] Compila sem warnings novos.
- [ ] Testes da area alterada criados/atualizados e passando.
- [ ] Sem violacao de fronteira entre camadas (Clean Architecture).
- [ ] Mensagens de erro em `Failure` padronizadas.
- [ ] Sem comportamento fail-open para recursos premium.
- [ ] Plano de rollback documentado no PR.
