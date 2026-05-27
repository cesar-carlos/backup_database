# AUDIT-11 — SQL Server backup: timeouts, validação de opções e cleanup

Data: 2026-05-27
Ficheiros principais:

- `lib/application/services/strategies/sql_server_backup_strategy_factory.dart`
- `lib/infrastructure/external/process/sql_server_backup_service.dart`
- `lib/presentation/widgets/schedules/schedule_dialog.dart`
- `lib/domain/services/i_sql_server_backup_service.dart`
- `lib/infrastructure/datasources/local/tables/sql_server_configs_table.dart`

Auditoria cobrindo Domain, Application, Infrastructure, Presentation e
testes da fatia SQL Server. Um bug funcional confirmado (timeouts) e três
inconsistências menores. Todas mitigadas neste mesmo audit (3 PRs lógicos
aplicados em sequência: timeouts → validação → cleanup).

## Achados e mitigações

### A.1 — Timeouts do schedule não chegavam ao service (bug funcional)

`SqlServerBackupStrategyFactory.create` montava `BackupExecutionContext`
**sem** `backupTimeout`/`verifyTimeout`. Único SGBD com esse furo —
Sybase, Postgres e Firebird passam ambos. Resultado: a UI persistia os
valores escolhidos pelo usuário, mas em execução o service sempre caía
nos defaults internos (`2h` backup, `30min` verify).

Mitigação: factory agora forwarda `schedule.backupTimeout` e
`schedule.verifyTimeout`. Coberto por novo teste em
`backup_strategy_factories_test.dart` que captura o
`BackupExecutionContext` recebido pelo port via mock.

### A.2 — `SqlServerBackupOptions.validate()` ignorada no save do schedule

`ScheduleDialog._save()` validava `SybaseBackupOptions` mas instanciava
`SqlServerBackupOptions` sem `.validate()`. Quem segurava a barra era
`ScheduleRepository._parseSqlServerBackupOptions`, que cai
**silenciosamente** em defaults com `LoggerService.warning` quando a
configuração persistida é inválida. Usuário não recebia feedback.

Mitigação: `_save()` chama `.validate()` antes de criar o `Schedule` e
exibe `FluentInfoBarFeedback.showWarning` com a mensagem de erro caso
inválido.

### A.3 — Service também não validava as opções (defesa em profundidade)

`_executeBackupCore` gerava T-SQL direto a partir das opções. Valores
fora de faixa só eram pegos pelo servidor como `Msg 5009, Level 16, ...`
— correto mas opaco.

Mitigação: validação no início do `_executeBackupCore`. Falha com
`ValidationFailure` antes de chamar `sqlcmd`. Coberto por novo teste
`recusa opcoes SQL Server invalidas antes de chamar sqlcmd` em
`sql_server_backup_service_test.dart` (usa `verifyNever` para garantir
que nenhum processo é spawned).

### B.1 — `BackupFlags.stopOnError` inconsistente com o T-SQL real

Métricas reportavam `stopOnError: true` sempre, mas a cláusula
`STOP_ON_ERROR` só vai no T-SQL quando `enableChecksum == true`.

Mitigação: `stopOnError: enableChecksum`. Histórico passa a refletir o
BACKUP real daqui em diante (backups antigos no banco continuam com o
valor antigo; sem migração necessária — campo é meramente informativo).

### B.2 — Regex de severidade sem `\b` na primeira alternativa

`r'\blevel\s+1[6-9]|\blevel\s+2[0-5]\b'` casava também `level 169` e
`level 1900`. Sem impacto prático conhecido (o gating é `Msg <num>` +
`Level <num>`), mas trivial fechar.

Mitigação: `r'\blevel\s+(1[6-9]|2[0-5])\b'`.

### B.3 — `listBackupFiles` inutilizável e sem call site

API rejeita seu próprio input: `databaseValue` era reutilizado como
caminho de arquivo `.bak`, mas `DatabaseName` proíbe `/`, `\`, `:` e
afins. Único call site é a própria interface. Pronta para o próximo dev
errar.

Mitigação: removido da `ISqlServerBackupService` e do
`SqlServerBackupService`. Referências sobrantes apenas em
`docs/notes/plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`
(planejamento histórico, sem efeito no código).

### B.4 — Coluna `password` da tabela Drift com comentário enganoso

`SqlServerConfigsTable.password` é coluna `NOT NULL` sempre escrita com
`''` (a senha real fica em `SecureCredentialKeys.sqlServerPasswordKey`).
Comentário antigo dizia `// Criptografado`.

Mitigação: comentário substituído para explicar que a coluna é mantida
por compatibilidade de schema e fica vazia, com nota para drop via
migration drift quando houver janela. Sem mudança de schema neste audit.

## Validação

- `flutter analyze` nos 7 arquivos tocados: **No issues found**.
- `flutter test` das suites afetadas (SQL Server service, strategies,
  rules, entities, dialog widget): **47 testes passam**, incluindo dois
  novos:
  - `backup_strategy_factories_test.dart`: `SqlServer factory forwards
    schedule timeouts and options to service` (smoke permanente contra
    regressão do A.1).
  - `sql_server_backup_service_test.dart`: `recusa opcoes SQL Server
    invalidas antes de chamar sqlcmd` (cobertura do A.3).

## Pendências não tocadas

- Drop da coluna `sql_server_configs.password` via migration drift.
  Anotado como TODO no próprio arquivo de tabela; sem urgência.
- `docs/analise_implementacao_sql_server.md` ainda menciona “estado de
  testes” como tendo lacunas em `truncateLog COPY_ONLY` e
  `verifyPolicy=bestEffort`. Continuam abertas — não fazem parte deste
  audit, mas valem o registro.
