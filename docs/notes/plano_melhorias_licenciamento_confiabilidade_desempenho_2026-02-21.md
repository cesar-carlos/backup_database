# Plano de Melhorias: Licenciamento, Confiabilidade e Desempenho

Data base: 2026-02-21  
Status: Em execucao  
Escopo: servidor + cliente (Flutter desktop)

## Objetivo Geral

1. Garantir enforcement de licenca no dominio (nao apenas na UI).
2. Elevar confiabilidade operacional em execucoes locais e remotas.
3. Melhorar desempenho de validacao, backup e transferencia.

## Regras do Projeto Consideradas (.cursor/rules)

- [ ] Respeitar fronteiras de Clean Architecture (domain nao depende de infrastructure/presentation).
- [ ] Manter DI via `get_it`, estado via `Provider` e erros via `result_dart`.
- [ ] Evitar duplicacao de logica de licenca (centralizar em service/policy).
- [ ] Aplicar null safety e contratos explicitos em APIs novas.
- [ ] Cobrir alteracoes com testes unitarios/integracao (padrao AAA).
- [ ] Evitar magic numbers (constantes nomeadas para timeout, retry, TTL, limites).

## Diagnostico Consolidado

- [ ] Bloqueios premium em parte concentrados na UI.
- [ ] Ausencia de gate unico de licenca em create/update/execute de schedule.
- [ ] Possivel duplicidade de licenca por `deviceKey`.
- [ ] Fallback hardcoded de segredo de licenca.
- [ ] Caminho fail-open em notificacao de e-mail.
- [ ] Oportunidade de melhorar throughput em upload para multiplos destinos.
- [ ] Consultas com potencial N+1 em carregamento de schedules e destinos relacionados.
- [ ] Scheduler busca todos os agendamentos ativos e varre em memoria a cada ciclo.
- [ ] Tabelas criticas sem plano explicito de indices para padroes de consulta frequentes.
- [ ] Pontos com `currentLicense!` podem gerar falha de runtime em cenarios de estado inconsistente.
- [ ] Conexao remota cliente -> servidor ainda sem gate explicito por licenca.

## Entrega Aplicada em 2026-02-21 (Socket/Auth)

- [x] Bloqueio de conexao remota no servidor quando a licenca nao libera `remote_control`.
- [x] Resposta clara no `authResponse` com motivo da recusa (`error` + `errorCode`).
- [x] Propagacao da mensagem de falha para o cliente (fluxo de conexao e teste de conexao).
- [x] Registro de tentativa de conexao com motivo real de bloqueio no log de conexoes.
- [x] Cobertura de testes ajustada para novo contrato de autenticacao.

## Fase 0 - Baseline e Seguranca Rapida (1-2 dias)

Objetivo: remover riscos imediatos.

- [ ] F0.1 Trocar fail-open para fail-closed em notificacoes por e-mail.  
  Arquivo alvo: `lib/application/services/notification_service.dart`
- [ ] F0.2 Remover fallback hardcoded de segredo de licenca.  
  Arquivo alvo: `lib/core/di/core_module.dart`
- [ ] F0.3 Ajustar fluxo de persistencia de licenca para update/upsert (evitar insert cego).  
  Arquivo alvo: `lib/application/providers/license_provider.dart`
- [ ] F0.4 Criar testes para F0.1-F0.3.
- [ ] F0.5 Aplicar mesma politica de licenca para `sendTestEmail` e `testEmailConfiguration`.
  Arquivo alvo: `lib/application/services/notification_service.dart`
- [ ] F0.6 Eliminar uso inseguro de `currentLicense!` em telas criticas (null-safe guard).
  Arquivos alvo:
  - `lib/presentation/pages/notifications_page.dart`
  - `lib/presentation/widgets/schedules/schedule_dialog.dart`
  - `lib/presentation/widgets/destinations/destination_dialog.dart`

DoD da Fase 0:
- [ ] Nenhum envio de e-mail ocorre quando validacao de licenca falhar por excecao.
- [ ] App nao aceita segredo de fallback fixo.
- [ ] Nao ha criacao repetida de licenca para o mesmo dispositivo no fluxo normal.
- [ ] Fluxos de teste SMTP seguem a mesma regra de licenca definida para envio operacional.
- [ ] UI nao quebra com estado nulo de licenca.

## Fase 1 - Enforcement de Dominio (3-5 dias)

Objetivo: impedir bypass por payload remoto, uso de provider ou alteracao de UI.

- [ ] F1.1 Implementar `LicensePolicyService` na camada de aplicacao.  
  API inicial:  
  - `validateScheduleCapabilities(Schedule)`  
  - `validateDestinationCapabilities(BackupDestination)`  
  - `validateExecutionCapabilities(Schedule, List<BackupDestination>)`
- [ ] F1.2 Aplicar policy em create/update de schedule.  
  Arquivos alvo:  
  - `lib/domain/use_cases/scheduling/create_schedule.dart`  
  - `lib/domain/use_cases/scheduling/update_schedule.dart`
- [ ] F1.3 Aplicar policy no caminho remoto (socket).  
  Arquivo alvo: `lib/infrastructure/socket/server/schedule_message_handler.dart`
- [ ] F1.4 Aplicar policy em create/update de destino.  
  Arquivo alvo: `lib/application/providers/destination_provider.dart` (ou use case dedicado)
- [ ] F1.5 Aplicar policy antes da execucao real.  
  Arquivos alvo:  
  - `lib/application/services/scheduler_service.dart`  
  - `lib/application/services/backup_orchestrator_service.dart`
- [ ] F1.6 Testes unitarios e de integracao para bypass remoto.
- [ ] F1.7 Consolidar validacao de licenca para destinos em um unico ponto (evitar duplicacao de regra).
  Arquivos candidatos:
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
- [ ] Recurso premium sem licenca e rejeitado em create/update/execute.
- [ ] Fluxo remoto recebe erro consistente e nao persiste alteracao invalida.
- [ ] Mensagens de erro sao claras e rastreaveis.
- [x] Cliente recebe motivo explicito quando conexao e negada por licenca.
- [ ] Regra de licenca para destinos existe em um unico componente reutilizavel.

## Fase 2 - Integridade de Dados de Licenca (2-3 dias)

Objetivo: garantir consistencia no armazenamento local.

- [ ] F2.1 Adicionar unicidade por `deviceKey` na tabela de licenca.  
  Arquivos alvo:  
  - `lib/infrastructure/datasources/local/tables/licenses_table.dart`  
  - `lib/infrastructure/datasources/local/database.dart`
- [ ] F2.2 Criar migracao para saneamento de duplicatas existentes.
- [ ] F2.3 Implementar `upsertByDeviceKey` no DAO/repositorio.  
  Arquivos alvo:  
  - `lib/infrastructure/datasources/daos/license_dao.dart`  
  - `lib/infrastructure/repositories/license_repository.dart`
- [ ] F2.4 Cobrir migracao com teste de integracao local DB.
- [ ] F2.5 Adicionar indices para consultas criticas de scheduler, historico e logs.
  Indices alvo:
  - `schedules_table(enabled, next_run_at)`
  - `backup_history_table(schedule_id, started_at)`
  - `backup_history_table(status, started_at)`
  - `backup_logs_table(backup_history_id, created_at)`
  - `backup_logs_table(level, created_at)`

DoD da Fase 2:
- [ ] Banco nao permite duas licencas para o mesmo `deviceKey`.
- [ ] Base antiga migra sem perda da licenca valida mais recente.
- [ ] Consultas de leitura frequente apresentam plano de acesso indexado.

## Fase 3 - Hardening Criptografico (4-6 dias)

Objetivo: reduzir superficie de forja/manipulacao de licenca.

- [ ] F3.1 Migrar validacao para assinatura assimetrica (Ed25519 recomendado).
- [ ] F3.2 Embarcar somente chave publica no app.
- [ ] F3.3 Versionar formato da licenca (`licenseVersion`, `issuedAt`, `notBefore`, `issuer`, `keyId`).
- [ ] F3.4 Garantir compatibilidade de leitura v1/v2 durante transicao.
- [ ] F3.5 Definir suporte opcional a revogacao assinada.
- [ ] F3.6 Testes criptograficos: assinatura valida, invalida, expiracao e device mismatch.

DoD da Fase 3:
- [ ] Licenca assinada indevidamente nao passa na validacao.
- [ ] Licencas legadas continuam funcionando no periodo de migracao definido.

## Fase 4 - Confiabilidade Operacional (3-5 dias)

Objetivo: melhorar comportamento sob falhas intermitentes.

- [ ] F4.1 Implementar retry com backoff exponencial + jitter para destinos remotos.
- [ ] F4.2 Implementar circuit breaker por destino.
- [ ] F4.3 Padronizar timeout e cancelamento cooperativo por etapa.
- [ ] F4.4 Introduzir idempotencia por `runId` em logs/historico/upload.
- [ ] F4.5 Definir catalogo de erros com codigos estaveis.
- [ ] F4.6 Testes de resiliencia (falha transitiva, timeout, cancelamento, repeticao).
- [ ] F4.7 Formalizar maquina de estados de `BackupHistory` (running -> success/error/warning) com transicoes validas.
- [ ] F4.8 Garantir atualizacoes idempotentes e atomicas de historico + logs em pontos de falha.

Arquivos candidatos:
- `lib/application/services/scheduler_service.dart`
- `lib/application/services/send_file_to_destination_service.dart`
- `lib/infrastructure/destination/destination_orchestrator_impl.dart`
- `lib/infrastructure/cleanup/backup_cleanup_service_impl.dart`

DoD da Fase 4:
- [ ] Recuperacao automatica de falhas transitivas sem duplicar efeito colateral.
- [ ] Logs e metricas permitem diagnostico rapido de causa raiz.
- [ ] Nao existem transicoes de estado invalidas no historico de backup.

## Fase 5 - Desempenho e Escalabilidade (3-5 dias)

Objetivo: reduzir latencia e custo de execucao.

- [ ] F5.1 Cache em memoria da licenca atual com TTL curto e invalidacao por update.
- [ ] F5.2 Memoizacao de checks de feature por execucao (`runId`).
- [ ] F5.3 Paralelismo controlado para envio a multiplos destinos.
- [ ] F5.4 Ajustar chunk size/streaming por destino remoto.
- [ ] F5.5 Medir e otimizar P95 por etapa (backup, compressao, upload, limpeza).
- [ ] F5.6 Testes de carga basicos para comparativo antes/depois.
- [ ] F5.7 Eliminar N+1 no `ScheduleRepository` ao montar `destinationIds` (carregamento em lote).
  Arquivos alvo:
  - `lib/infrastructure/repositories/schedule_repository.dart`
  - `lib/infrastructure/datasources/daos/schedule_destination_dao.dart`
- [ ] F5.8 Otimizar obtencao de destinos no scheduler com busca em lote por IDs.
  Arquivo alvo: `lib/application/services/scheduler_service.dart`
- [ ] F5.9 Mover filtro de agendamentos vencidos para query dedicada no banco (evitar scan completo em memoria).
  Arquivos alvo:
  - `lib/infrastructure/datasources/daos/schedule_dao.dart`
  - `lib/infrastructure/repositories/schedule_repository.dart`
  - `lib/application/services/scheduler_service.dart`

DoD da Fase 5:
- [ ] Melhoria mensuravel de P95 em transferencia.
- [ ] Sem regressao funcional nos fluxos criticos.
- [ ] Reducao de consultas por ciclo do scheduler e por carregamento de schedules.

## Fase 6 - Observabilidade e Operacao (2-3 dias)

Objetivo: fechar ciclo de monitoramento e governanca tecnica.

- [ ] F6.1 Instrumentar metricas:  
  - `license_denied_total`  
  - `schedule_update_rejected_total`  
  - `backup_run_duration_ms`  
  - `destination_upload_duration_ms`  
  - `destination_upload_failure_total`  
  - `email_notification_skipped_license_total`
- [ ] F6.2 Padronizar logs estruturados com correlacao por `runId` e `scheduleId`.
- [ ] F6.3 Criar checklist de rollout/rollback por fase.
- [ ] F6.4 Definir criterios de prontidao para liberar cada fase.

DoD da Fase 6:
- [ ] Dashboard e logs suficientes para operacao sem depuracao manual extensa.

## Priorizacao

P0 (seguranca funcional imediata):
- [ ] Fase 0
- [ ] Fase 1
- [ ] Fase 2

P1 (hardening e resiliencia):
- [ ] Fase 3
- [ ] Fase 4

P2 (otimizacao e operacao):
- [ ] Fase 5
- [ ] Fase 6

## Sequencia de Execucao Recomendada

- [ ] PR-1: Fase 0 (quick wins)
- [ ] PR-2: Fase 1 (policy em dominio + remoto)
- [ ] PR-3: Fase 2 (migracao e unicidade de licenca)
- [ ] PR-4: Fase 3 (assinatura assimetrica + compatibilidade)
- [ ] PR-5: Fase 4 (retry, breaker, timeout, idempotencia)
- [ ] PR-6: Fase 5 (cache, memoizacao, paralelismo)
- [ ] PR-7: Fase 6 (metricas, logs, rollout)

## Checklist de Qualidade por PR

- [ ] Compila sem warnings novos.
- [ ] Testes da area alterada criados/atualizados e passando.
- [ ] Sem violacao de fronteira entre camadas (Clean Architecture).
- [ ] Mensagens de erro em `Failure` padronizadas.
- [ ] Sem comportamento fail-open para recursos premium.
- [ ] Plano de rollback documentado no PR.
