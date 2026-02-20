# Componente - Notificacoes com Multi Config de Email

Data: 2026-02-19
Prioridade: IMEDIATA (primeira entrega no modulo de notificacoes)

## Status de execucao (atualizado em 2026-02-20)

Resumo rapido:

- Fase 1: concluida
- Fase 2: concluida
- Fase 3: concluida no fluxo principal (resta apenas telemetria fina)
- Fase 4: concluida
- Fase 5: concluida com variacao por `grid` (em vez de `list` para notificacoes)
- Fase 6: concluida (fallback removido e limpeza de legado em `schemaVersion 20`)
- Testes obrigatorios: concluido

Entregas confirmadas no codigo:

- Banco/migracao:
- `lib/infrastructure/datasources/local/tables/email_notification_targets_table.dart`
- `lib/infrastructure/datasources/local/tables/email_configs_table.dart`
- `lib/infrastructure/datasources/local/database.dart`
- `lib/infrastructure/datasources/local/database.g.dart`
- `lib/infrastructure/datasources/daos/email_notification_target_dao.dart`

- Domain/contratos:
- `lib/domain/entities/email_notification_target.dart`
- `lib/domain/entities/email_config.dart` (com `configName`)
- `lib/domain/repositories/i_email_config_repository.dart`
- `lib/domain/repositories/i_email_notification_target_repository.dart`

- Infra/servico:
- `lib/infrastructure/repositories/email_config_repository.dart`
- `lib/infrastructure/repositories/email_notification_target_repository.dart`
- `lib/application/services/notification_service.dart`
- `lib/core/di/infrastructure_module.dart`
- `lib/core/di/application_module.dart`
- `lib/core/di/domain_module.dart`

- Provider/UI:
- `lib/application/providers/notification_provider.dart`
- `lib/core/di/presentation_module.dart`
- `lib/presentation/pages/notifications_page.dart`
- `lib/presentation/widgets/notifications/email_config_grid.dart`
- `lib/presentation/widgets/notifications/email_target_grid.dart`
- `lib/presentation/widgets/notifications/email_target_dialog.dart`
- `lib/presentation/widgets/notifications/notification_config_dialog.dart`

- Grid compartilhado:
- `lib/presentation/widgets/common/app_data_grid.dart`
- Adocao em notificacoes/destinos/agendamentos/servidor/logs

Pendencias principais para fechamento total:

- nenhuma pendencia funcional aberta neste componente

Atualizacao final de validacao (2026-02-20):

- `flutter test` completo executado com sucesso.
- Resultado da suite: `00:14 +197: All tests passed!`
- Ajustes de estabilizacao de testes aplicados e validados:
- registro explicito de `SocketLoggerService` nos testes de socket/integracao
- correcoes de setup/assert em `TempDirectoryService` tests
- correcao de expectativa em `CheckDiskSpace` test

Referencia de acompanhamento complementar:

- `docs/notes/status_execucao_notificacoes_multi_config_2026-02-20.md`

## Objetivo funcional

Permitir:

- mais de uma configuracao SMTP cadastrada
- lista de destinatarios por configuracao
- personalizacao por destinatario do tipo de notificacao:
- sucesso
- erro
- aviso

## Divida tecnica encontrada no codigo atual

1. Fluxo de notificacao esta em modo "single config"
- `lib/infrastructure/datasources/daos/email_config_dao.dart` usa `getSingleOrNull()`
- `lib/infrastructure/repositories/email_config_repository.dart` salva/atualiza apenas 1 registro
- `lib/domain/repositories/i_email_config_repository.dart` so expoe `get/save/delete`

2. UI atual suporta apenas 1 destinatario pratico
- `lib/presentation/pages/notifications_page.dart` grava `recipients: [recipientEmail]`
- `lib/presentation/pages/notifications_page.dart` carrega apenas `config.recipients.first`

3. Personalizacao por tipo esta global no config, nao por email
- `lib/domain/entities/email_config.dart` concentra `notifyOnSuccess/notifyOnError/notifyOnWarning` no nivel da configuracao

4. NotificationService processa somente 1 configuracao
- `lib/application/services/notification_service.dart` usa `_emailConfigRepository.get()`

5. Bug funcional existente
- `lib/application/services/notification_service.dart` em `sendTestEmail(recipient, subject)` ignora `recipient`

6. Divida de arquitetura
- `lib/application/services/notification_service.dart` usa `service_locator` interno (acoplamento oculto)

## Decisao de arquitetura para esta feature

Manter `email_configs_table` para dados SMTP e criar uma tabela nova para regras por destinatario.

### Novo modelo de dados (proposto)

Tabela nova: `email_notification_targets_table`

- `id TEXT PK`
- `email_config_id TEXT NOT NULL` (FK para `email_configs_table`, `ON DELETE CASCADE`)
- `recipient_email TEXT NOT NULL`
- `notify_on_success INTEGER NOT NULL DEFAULT 1`
- `notify_on_error INTEGER NOT NULL DEFAULT 1`
- `notify_on_warning INTEGER NOT NULL DEFAULT 1`
- `enabled INTEGER NOT NULL DEFAULT 1`
- `created_at INTEGER NOT NULL`
- `updated_at INTEGER NOT NULL`
- `UNIQUE(email_config_id, recipient_email)`

Coluna nova em `email_configs_table`:

- `config_name TEXT NOT NULL DEFAULT 'Configuracao SMTP'`

Observacao:

- manter `recipients` e `notify_on_*` atuais por compatibilidade de migracao por uma versao
- apos estabilizacao, marcar campos antigos como legados e planejar remocao

## Fase 1 - Banco de dados e migracao (schema 19)

Checklist:

- [x] Criar `email_notification_targets_table` em `lib/infrastructure/datasources/local/tables/`.
- [x] Exportar nova tabela em `lib/infrastructure/datasources/local/tables/tables.dart`.
- [x] Criar `EmailNotificationTargetDao`.
- [x] Exportar novo DAO em `lib/infrastructure/datasources/daos/daos.dart`.
- [x] Registrar tabela/DAO no `@DriftDatabase` em `lib/infrastructure/datasources/local/database.dart`.
- [x] Subir `schemaVersion` de `18` para `19`.
- [x] Adicionar migracao `from < 19`:
- [x] garantir coluna `config_name` em `email_configs_table`
- [x] criar `email_notification_targets_table`
- [x] migrar dados legados:
- [x] para cada registro em `email_configs_table`, ler `recipients` JSON
- [x] criar 1 target por email usando os flags globais atuais (`notify_on_success/error/warning`)
- [x] criar indice de `email_config_id`
- [x] Manter migracao idempotente (nao duplicar targets existentes).
- [x] Rodar codegen drift.

Comandos:

```bash
dart run build_runner build --delete-conflicting-outputs
```

## Fase 2 - Domain e contratos

Checklist:

- [x] Criar entidade `EmailNotificationTarget` em `lib/domain/entities/`.
- [x] Evoluir `EmailConfig` para incluir `configName`.
- [x] Criar agregado de leitura (exemplo: `EmailNotificationProfile`) com:
- [x] dados SMTP
- [x] lista de targets
- [x] Atualizar `IEmailConfigRepository` para multi-config:
- [x] `getAll()`
- [x] `getById(String id)`
- [x] `create(EmailConfig config)`
- [x] `update(EmailConfig config)`
- [x] `delete(String id)`
- [x] operaÃ§Ãµes de target por config (ou repositorio dedicado)
- [x] Atualizar use cases de notificacao para novo contrato.

## Fase 3 - Infraestrutura e servico de notificacao

Checklist:

- [x] Refatorar `EmailConfigRepository` para operar lista de configuracoes.
- [x] Criar repositorio para targets (ou incorporar no atual com metodos claros).
- [x] Refatorar `NotificationService`:
- [x] iterar todas as configs `enabled`
- [x] para cada config, iterar targets `enabled`
- [x] enviar apenas para target que habilitou o tipo do evento (sucesso/erro/aviso)
- [x] tratamento de falha parcial sem abortar lote completo
- [x] consolidar resultado final (enviou ao menos 1, erros por destino)
- [x] Corrigir `sendTestEmail` para usar `recipient` informado.
- [x] Remover `service_locator` interno e injetar dependencia por construtor.

## Fase 4 - Provider e estado de tela

Checklist:

- [x] Evoluir `NotificationProvider` para estado multi-config:
- [x] `List<EmailConfig> configs`
- [x] `String? selectedConfigId`
- [x] `List<EmailNotificationTarget> targets` do config selecionado
- [x] Acoes:
- [x] criar/editar/excluir configuracao SMTP
- [x] criar/editar/excluir target
- [x] habilitar/desabilitar config e target
- [x] testar conexao para config selecionado
- [x] Atualizar DI em:
- [x] `lib/core/di/domain_module.dart`
- [x] `lib/core/di/application_module.dart`
- [x] `lib/core/di/presentation_module.dart`

## Fase 5 - UI componentizada (sem perder identidade visual)

Diretriz:

- reutilizar componentes existentes de `lib/presentation/widgets/common/`:
- `AppCard`, `AppTextField`, `NumericField`, `PasswordField`, `ActionButton`, `SaveButton`, `MessageModal`, `ConfigListItem`

Novos widgets propostos:

- `lib/presentation/widgets/notifications/notifications.dart` (barrel)
- `lib/presentation/widgets/notifications/email_config_list.dart`
- `lib/presentation/widgets/notifications/email_config_list_item.dart`
- `lib/presentation/widgets/notifications/email_config_form_card.dart`
- `lib/presentation/widgets/notifications/email_target_list.dart`
- `lib/presentation/widgets/notifications/email_target_list_item.dart`
- `lib/presentation/widgets/notifications/email_target_dialog.dart`
- `lib/presentation/widgets/notifications/email_target_type_toggles.dart`

Mudancas em tela:

- [x] Refatorar `lib/presentation/pages/notifications_page.dart` para layout em 2 blocos:
- [x] bloco A: lista de configuracoes SMTP
- [x] bloco B: detalhes da configuracao selecionada + lista de targets
- [x] Acoes visiveis:
- [x] nova configuracao SMTP
- [x] editar/excluir configuracao
- [x] adicionar destinatario (target)
- [x] editar/excluir destinatario
- [x] testar conexao da configuracao
- [x] salvar alteracoes

## Fase 6 - Compatibilidade e rollout

Checklist:

- [x] Compatibilidade de leitura legado (se nao houver target migrado, usar fallback temporario).
- [x] Banner/telemetria de migracao concluida.
- [x] Definir janela para remocao dos campos legados (`recipients`, `notify_on_*` globais).

Janela definida (remocao de legado):

1. 2026-02-20 ate 2026-03-05: fase de observacao com banner/telemetria e tela de revisao pos-migracao.
2. 2026-03-06 ate 2026-03-20: congelar escrita de novos dados legados (`recipients`, `notify_on_*` globais), mantendo apenas leitura fallback.
3. 2026-02-20: `schemaVersion 20` executado removendo leitura fallback no servico e iniciando limpeza dos campos legados.
4. 2026-04-04: remover definitivamente campos legados do fluxo (rollback desativado).

## Testes obrigatorios

### Banco/migracao

- [x] migracao 18 -> 19 preserva config SMTP e cria targets corretamente.
- [x] migracao idempotente nao duplica target.
- [x] delete de config remove targets (cascade).

### Repositorio/servico

- [x] `NotificationService` envia para multiplas configs.
- [x] envio respeita flags por destinatario.
- [x] falha em um destinatario nao impede demais.
- [x] `sendTestEmail` envia para recipient informado.

### Provider/UI

- [x] criar/editar/excluir config.
- [x] criar/editar/excluir target.
- [x] toggles de tipo por target persistem.
- [x] layout refatorado mantÃ©m componentes padrao do projeto.

## Criterios de aceite da entrega

- [x] Usuario consegue cadastrar N configuracoes SMTP.
- [x] Em cada configuracao, usuario consegue cadastrar N destinatarios.
- [x] Cada destinatario possui personalizacao independente de sucesso/erro/aviso.
- [x] Agendamento de backup dispara notificacao para os destinatarios corretos.
- [x] Migracao funciona em base existente sem perda de dados.
- [x] UI segue identidade visual atual por reutilizacao de widgets comuns.

## Riscos e mitigacao

Risco: regressao no envio por manter campos antigos e novos

- Mitigacao:
- [x] testes de regressao nos fluxos antigos
- [x] fallback controlado por tempo limitado

Risco: aumento de complexidade na pagina de notificacoes

- Mitigacao:
- [x] componentizacao em widgets pequenos
- [x] separacao de estados por responsabilidade no provider

Risco: migracao incompleta para recipients JSON invalido

- Mitigacao:
- [x] tratar parse com fallback vazio
- [x] log estruturado de registros nao migrados
- [x] tela de revisao pos-migracao


## Compatibilidade com o plano de confiabilidade e seguranca

Referencia: `docs/notes/plano_melhorias_confiabilidade_seguranca_2026-02-19.md`

Status: sem conflito de objetivo. Este plano e um recorte prioritario do modulo de notificacoes.

Regras de conciliacao:

- usar `schemaVersion 19` para esta entrega (multi-config notificacoes)
- migracoes de seguranca de credenciais devem iniciar em `schemaVersion 21` (apos conclusao da limpeza de legado de notificacoes em `schemaVersion 20`)
- itens sobrepostos devem ser implementados uma unica vez:
- correcao de `sendTestEmail` com recipient informado
- remocao de `service_locator` em `NotificationService`

Sequenciamento recomendado:

1. Executar este plano (multi-config notificacoes)
2. Retomar plano de confiabilidade a partir da Fase 2
3. Marcar Fase 6 (itens sobrepostos) como parcial/concluida por referencia cruzada

## Conformidade com .cursor/rules (validacao adicional)

Regras criticas aplicadas:

- `clean_architecture.mdc`: Application nao importa Infrastructure
- `project_specifics.mdc`: DI via `get_it` + DIP por construtor
- `flutter_widgets.mdc`: composicao de widgets e limite recomendado de tamanho
- `testing.mdc`: testes em estrutura espelhada + AAA

Ajustes adicionados neste plano:

- [x] Fase 3: `NotificationService` deve depender de interface (`IEmailService`) e nao de `infrastructure/external/email/email_service.dart`.
- [x] Fase 3: registrar implementacao concreta no `get_it` (modulo de DI), mantendo Application desacoplada.
- [x] Fase 5 (UI): componentes novos devem priorizar widgets menores/componentizados (meta < 150 linhas por widget) e `const` quando possivel.
- [x] Fase 5 (UI): evitar concentrar toda renderizacao em um unico `build()` da page; extrair subwidgets privados/reutilizaveis.
- [x] Testes (Fase 6): incluir unit tests para camada Application sem dependencias concretas de Infrastructure.

Status:

- com estes ajustes, o plano fica aderente as rules do projeto.

## Investigacao de grid compartilhado (telas existentes)

Resultado da analise nas telas de Destinos, Agendamentos, Servidor e Log de Conexoes:

- existe um padrao forte de lista baseado em `ConfigListItem` + `ListView.separated`
- nao existe um componente de grid unificado em `lib/presentation/widgets/common/`
- hoje existe apenas grid pontual em notificacoes (`email_config_grid.dart`), sem reuso entre modulos

Arquivos analisados:

- `lib/presentation/widgets/common/config_list_item.dart`
- `lib/presentation/widgets/destinations/destination_list_item.dart`
- `lib/presentation/widgets/schedules/schedule_list_item.dart`
- `lib/presentation/widgets/server/server_credential_list_item.dart`
- `lib/presentation/widgets/server/connection_logs_list.dart`
- `lib/presentation/widgets/server/connected_clients_list.dart`

Conclusao:

- nao existe `AppGrid`/`AppDataGrid` compartilhado com identidade visual do projeto
- ha alta oportunidade de consolidacao, pois os modulos compartilham padroes de colunas, status, toggle e acoes

## Fase 5.1 - Componente base de grid (novo)

Objetivo:

- criar componente de grid reutilizavel mantendo identidade visual atual (Fluent + AppCard + tokens)

Checklist de implementacao:

- [x] Criar `lib/presentation/widgets/common/app_data_grid.dart`.
- [x] Criar contratos de coluna/linha/acao:
- [x] `AppDataGridColumn<T>`
- [x] `AppDataGridAction<T>`
- [x] `AppDataGridCellBuilder<T>`
- [x] Suportar colunas com largura fixa/flex e alinhamento.
- [x] Suportar estado horizontal scroll para desktop sem quebrar layout.
- [x] Suportar linha de cabecalho padrao com tokens do tema Fluent.
- [x] Suportar celulas com widgets custom (badge, toggle, icone, texto truncado).
- [x] Suportar acoes por linha (editar/excluir/duplicar/executar) sem duplicar codigo por pagina.
- [x] Suportar estilo de status (ativo/inativo, sucesso/erro) por cell renderer.
- [x] Extrair estilos comuns (padding, borda, altura minima) para manter consistencia.
- [x] Garantir acessibilidade minima (focus, tooltip em acoes icon-only, labels claros).

Conformidade com rules:

- [x] Componentizar em widgets menores (< 150 linhas por widget, quando possivel).
- [x] Usar `const` onde aplicavel.
- [x] Evitar helper methods gigantes no `build()` da page.

## Fase 5.2 - Adocao gradual nas telas

Checklist:

- [x] Notificacoes: migrar `email_config_grid.dart` para usar `AppDataGrid`.
- [x] Destinos: avaliar variante em grid mantendo chips de tipo e resumo de configuracao.
- [x] Agendamentos: avaliar grid com colunas (nome, tipo, banco, proxima execucao, status, acoes).
- [x] Servidor/Credenciais: avaliar grid com colunas (nome, server id, descricao, ativo, acoes).
- [x] Log de conexoes: avaliar grid com colunas (host, timestamp, status, erro).

Estrategia de rollout UI:

1. Entregar `AppDataGrid` primeiro em Notificacoes.
2. Validar com usuarios internos (legibilidade e produtividade).
3. Migrar telas restantes em lotes pequenos para reduzir risco visual.

## Testes adicionais do componente

- [x] Widget test: renderiza cabecalho e linhas corretamente.
- [x] Widget test: aplica horizontal scroll quando excede largura.
- [x] Widget test: dispara callbacks de acoes por linha.
- [x] Widget test: respeita estados disabled/loading em acoes.
