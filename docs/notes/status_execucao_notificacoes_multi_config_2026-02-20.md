# Status de Execucao - Notificacoes Multi Config

Data: 2026-02-20
Referencia: `docs/notes/componente_notificacoes_multi_config_email.md`

## Concluido

- Fase 1 (Banco/Migracao):
- `schemaVersion` elevado para 19.
- Nova tabela `email_notification_targets_table` criada e registrada.
- Novo DAO `EmailNotificationTargetDao` criado e registrado.
- Coluna `config_name` adicionada em `email_configs_table`.
- Migracao com backfill legado de `recipients` para targets implementada.
- Codegen drift executado com sucesso.

- Fase 2 (Domain/Contratos):
- Entidade `EmailNotificationTarget` criada.
- `EmailConfig` evoluido com `configName`.
- `IEmailConfigRepository` evoluido para operacoes multi-config (`getAll/getById/create/update/deleteById`) mantendo compatibilidade legado (`get/save/delete`).
- Novo contrato `IEmailNotificationTargetRepository` criado.

- Fase 3 (Infra/Servico) - Parcial alto impacto:
- `EmailConfigRepository` ajustado para fluxo multi-config.
- `EmailNotificationTargetRepository` implementado.
- `NotificationService` refatorado para:
- iterar multiplas configuracoes habilitadas
- carregar targets por configuracao
- operar exclusivamente com targets por configuracao (sem fallback legado)
- envio por destinatario com flags `success/error/warning`
- tolerancia a falha parcial (sem abortar lote inteiro)
- Correcao de `sendTestEmail` para usar recipient informado.
- Remocao de acoplamento oculto com locator (injecao explicita).
- DI ajustado para injetar `IEmailNotificationTargetRepository` no `NotificationService`.

- Fase 5.1/5.2 (Grid compartilhado) - Entregue:
- Componente base `AppDataGrid` criado em `lib/presentation/widgets/common/app_data_grid.dart`.
- Adocao em Notificacoes, Destinos, Agendamentos, Servidor/Credenciais e Log de Conexoes.

## Pendente

- Nenhuma pendencia funcional aberta neste modulo.

## Atualizacao 9 - 2026-02-20 (validacao final da suite completa)

Concluido:

- `flutter test` completo executado apos os ajustes finais.
- Resultado: `00:14 +197: All tests passed!`

Ajustes finais de estabilidade de testes:

- testes de socket/integracao com registro explicito de `SocketLoggerService`
- `test/unit/core/services/temp_directory_service_test.dart` com setup/assert corrigidos
- `test/unit/domain/use_cases/check_disk_space_test.dart` com expectativa corrigida

## Atualizacao 8 - 2026-02-20 (remocao controlada do legado - schema 20)

Concluido:

- Banco/Migracao:
- `lib/infrastructure/datasources/local/database.dart`
- `schemaVersion` elevado para `20`.
- migracao `from < 20` com limpeza dos campos legados em
  `email_configs_table` (`recipients`, `notify_on_success`, `notify_on_error`,
  `notify_on_warning`), preservando targets migrados.

- Servico:
- `lib/application/services/notification_service.dart`
- fallback legado removido; falha de leitura de targets passa a retornar erro.

- Provider/UI:
- `lib/application/providers/notification_provider.dart`
- removida telemetria/estado de fallback legado.
- `lib/presentation/pages/notifications_page.dart`
- removido banner de migracao e fluxo de revisao legado.
- `lib/presentation/widgets/notifications/notification_config_dialog.dart`
- removida escrita de destinatario/flags legados (configuracao por destinatario
  permanece no grid de targets).
- `lib/presentation/widgets/notifications/notifications.dart`
- removido export do modal legado.

- Testes:
- `test/unit/application/services/notification_service_test.dart`
- atualizado para validar ausencia de fallback legado.
- `test/unit/application/providers/notification_provider_test.dart`
- atualizado para estado sem telemetria de fallback.
- `test/unit/infrastructure/datasources/local/database_migration_v20_test.dart`
- atualizado para validar limpeza dos campos legados no `schemaVersion 20`.
- removido teste do modal legado:
- `test/unit/presentation/widgets/notifications/notification_migration_review_dialog_test.dart`

## Atualizacao 7 - 2026-02-20 (tela de revisao pos-migracao - historico)

Concluido:

- Tela/modal de revisao pos-migracao implementada:
- `lib/presentation/widgets/notifications/notification_migration_review_dialog.dart`
- Exibe grid com configuracoes em fallback legado e acao de revisao.

- Integracao com a tela de notificacoes:
- `lib/presentation/pages/notifications_page.dart`
- Banner de migracao agora possui acao `Revisar agora`.

- Enriquecimento do provider para auditoria de migracao:
- `legacyFallbackConfigs`
- `getTargetCountForConfig(configId)`
- persistencia em memoria de IDs/contagem para suporte ao modal de revisao.

Testes adicionados/atualizados:

- `test/unit/presentation/widgets/notifications/notification_migration_review_dialog_test.dart`
- `test/unit/application/providers/notification_provider_test.dart`

Validacao executada:

- `flutter analyze`
- `flutter test`:
- provider, scheduler, notification service, widget do modal de migracao e
  widget do grid compartilhado

Resultado: validacao concluida sem falhas.

Observacao:

- esta etapa foi descontinuada na Atualizacao 8 com a retirada definitiva do fallback legado.

## Atualizacao 6 - 2026-02-20 (criterio de aceite + componentizacao)

Concluido:

- Criterio de aceite de agendamento/notificacao validado com testes:
- `test/unit/application/services/scheduler_service_test.dart`
- novos cenarios:
- `executeNow` notifica conclusao em sucesso
- `executeNow` notifica com historico em erro quando upload falha

- Componentizacao adicional na UI de notificacoes:
- `lib/presentation/widgets/notifications/notification_config_dialog.dart`
- `lib/presentation/widgets/notifications/email_target_dialog.dart`
- dialogs quebrados em subwidgets privados para reduzir complexidade do `build()`.
- `lib/presentation/pages/notifications_page.dart`
- page refatorada com secoes privadas (`command bar`, aviso de licenca e conteudo principal),
  removendo concentracao de renderizacao em um unico `build()`.

Validacao executada:

- `flutter analyze` nos arquivos alterados
- `flutter test`:
- `test/unit/application/services/scheduler_service_test.dart`
- `test/unit/application/services/notification_service_test.dart`
- `test/unit/application/providers/notification_provider_test.dart`

Resultado: validacao concluida sem falhas.

## Conflito com plano de confiabilidade/seguranca

Arquivo: `docs/notes/plano_melhorias_confiabilidade_seguranca_2026-02-19.md`

- Sem conflito estrutural.
- Itens sobrepostos ja absorvidos nesta entrega:
- correcao de `sendTestEmail`
- remocao de service locator em `NotificationService`
- Demais fases de confiabilidade/seguranca permanecem pendentes (segredos, redaction, socket hardening, scheduler cleanup/tests).

## Atualizacao 2 - 2026-02-20

Concluido nesta iteracao:

- Fase 4 (Provider/Estado):
- `NotificationProvider` migrado para estado multi-config (`configs`, `selectedConfigId`) e targets por configuracao (`targets`).
- Adicionado carregamento/selecao de configuracao e CRUD de destinatarios (create/update/delete/toggle).
- Mantida compatibilidade temporaria com API antiga (`emailConfig`, `loadConfig`, `toggleEnabled`).

- Fase 5 (UI Notificacoes):
- `notifications_page.dart` refatorada para dois blocos:
- grid de configuracoes SMTP
- grid de destinatarios da configuracao selecionada
- Novo modal de destinatario com flags por tipo:
- `lib/presentation/widgets/notifications/email_target_dialog.dart`
- Novo grid de destinatarios:
- `lib/presentation/widgets/notifications/email_target_grid.dart`
- `email_config_grid.dart` evoluido para lista multi-config com selecao, toggle e acoes.
- `notification_config_dialog.dart` evoluido com `configName` e compatibilidade legado.

- DI de Presentation atualizado para injetar `IEmailNotificationTargetRepository` no `NotificationProvider`.

Validacao:

- `dart analyze` sem erros nos arquivos alterados.

Pendencias remanescentes principais:

- Testes obrigatorios (migracao 18->19, NotificationService multi-target, provider/UI).
- Fase 6 de rollout/retirada de campos legados (banner/telemetria e plano de remocao).

## Atualizacao 3 - 2026-02-20 (testes)

Concluido:

- Novos testes unitarios de Application (sem dependencias concretas de Infrastructure):
- `test/unit/application/services/notification_service_test.dart`
- `test/unit/application/providers/notification_provider_test.dart`

Cobertura adicionada:

- NotificationService:
- bloqueio por licenca
- envio multi-target com falha parcial (continua lote)
- fallback legado quando consulta de targets falha
- filtro de aviso por `notifyOnWarning`
- `sendTestEmail` usando recipient informado

- NotificationProvider:
- carregamento multi-config com selecao e targets
- `saveConfig` com create + refresh de selecao
- `addTarget` com recarga de lista
- `testConfiguration` sem config selecionada
- `toggleTargetEnabled` quando target nao existe

Validacao executada:

- `dart analyze` nos dois arquivos de teste (sem issues)
- `flutter test` nos dois arquivos (todos passando)

Pendencias de teste ainda abertas no plano:

- testes de migracao 18 -> 19 (preservacao/idempotencia/cascade)
- widget tests do `AppDataGrid`

## Atualizacao 4 - 2026-02-20 (migracao + grid)

Concluido:

- Testes de migracao v18 -> v19:
- `test/unit/infrastructure/datasources/local/database_migration_v19_test.dart`
- cenarios cobertos:
- preservacao de dados SMTP + criacao de targets
- idempotencia do backfill (nao duplica target existente)
- cascade delete de targets ao remover config

- Testes de widget do grid compartilhado:
- `test/unit/presentation/widgets/common/app_data_grid_test.dart`
- cenarios cobertos:
- render de cabecalho e linhas
- suporte a scroll horizontal
- callback de acao por linha
- estado disabled de acao

Ajuste tecnico para testabilidade:

- novo construtor de teste no banco:
- `AppDatabase.forTesting(super.executor)` em `lib/infrastructure/datasources/local/database.dart`

Dependencia de teste adicionada:

- `sqlite3` em `dev_dependencies` do `pubspec.yaml`

Validacao executada:

- `dart analyze` dos arquivos alterados
- `flutter test`:
- `test/unit/infrastructure/datasources/local/database_migration_v19_test.dart`
- `test/unit/presentation/widgets/common/app_data_grid_test.dart`
- `test/unit/application/services/notification_service_test.dart`
- `test/unit/application/providers/notification_provider_test.dart`

Resultado: todos os testes acima passando.

## Atualizacao 5 - 2026-02-20 (rollout de migracao)

Concluido:

- Fase 6 (parcial): banner e telemetria de migracao adicionados.
- `NotificationProvider` agora calcula e expone `legacyFallbackConfigCount`.
- Telemetria de migracao registrada em log:
- `[NotificationMigration] totalConfigs=..., legacyFallbackConfigs=...`
- `notifications_page.dart` agora exibe `InfoBar` quando ainda existem
  configuracoes em fallback legado (com `recipients` e sem targets).

Arquivos alterados:

- `lib/application/providers/notification_provider.dart`
- `lib/presentation/pages/notifications_page.dart`
- `test/unit/application/providers/notification_provider_test.dart`

Validacao executada:

- `flutter analyze` dos arquivos alterados
- `flutter test`:
- `test/unit/application/providers/notification_provider_test.dart`
- `test/unit/application/services/notification_service_test.dart`

Resultado: validacao concluida sem falhas.
