# AUDIT-13 — Sybase backup: flags, PATH detect, use case, injection hardening, cleanup

Data: 2026-05-27
Ficheiros principais:

- `lib/infrastructure/external/process/sybase_backup_service.dart`
- `lib/domain/use_cases/backup/execute_sybase_backup.dart`
- `lib/core/utils/sybase_connection_field_validator.dart` (novo)
- `lib/presentation/widgets/sybase/sybase_config_dialog.dart`
- `lib/presentation/pages/sybase_config_page.dart`
- `lib/presentation/pages/database_config/database_config_page*.dart`
- `lib/infrastructure/datasources/local/tables/sybase_configs_table.dart`

Auditoria cobrindo Domain, Application, Infrastructure, Presentation e
testes da fatia Sybase SQL Anywhere — a mais sofisticada do app
(pipeline com 3 rules + 1 enricher, cache de strategy de conexão com
TTL, fallback duplo dbisql/dbbackup e dbvalid/dbverify, arquivo
temporário de credenciais com cleanup de órfãos no boot). Cinco PRs
lógicos aplicados em sequência: flags → PATH detection → use case →
sanitização → cleanup. Implementação base é robusta — auditoria fechou
gaps de paridade com Postgres/SQL Server e adicionou hardening contra
connection-string injection.

## Achados e mitigações

### A.1 — `BackupFlags.stopOnError: true` hardcoded (PR1)

Sybase SQL Anywhere não tem conceito equivalente ao `STOP_ON_ERROR` do
SQL Server. Valor `true` era copy/paste e enganava
histórico/relatório. Mesma situação corrigida no AUDIT-12 Postgres.

Mitigação: `stopOnError: false` para sinalizar "N/A". `compression`,
`stripingCount=1`, `withChecksum=false` também são N/A em Sybase mas
não são tão enganosos — mantidos como estão. `verifyPolicy` já estava
**correto** (etiquetas semânticas `none|log_unavailable|dbvalid|
dbverify|dbvalid_falhou`).

Teste novo: `BackupFlags.stopOnError = false no relatorio (achado A.1)`.

### A.2 — `ExecuteSybaseBackup` com API limitada (PR3a)

Dead code efetivo (zero call sites na aplicação), mas se mantido pra
futuros usos CLI/IPC precisava aceitar parâmetros modernos do
`BackupExecutionContext`. Antes só recebia `truncateLog`,
`verifyAfterBackup`, `verifyPolicy`.

Mitigação: API ampliada para receber `scheduleId`,
`sybaseBackupOptions`, `backupTimeout`, `verifyTimeout`, `cancelTag` —
paridade com a evolução do orchestrator/strategy. Forward correto no
`BackupExecutionContext`.

### A.3 — Use case direto pulava `SybaseRejectDifferentialRule` (PR3a)

O service mapeia silenciosamente `differential → log` na linha 132–136
(comportamento legado). Quando o pipeline rodava via strategy, o
`SybaseRejectDifferentialRule` rejeitava antes; mas via use case
direto, o caller pedia `differential` e ganhava `log` sem aviso.

Mitigação: use case agora rejeita `BackupType.differential` e os 3
tipos convertidos (`convertedDifferential`, `convertedFullSingle`,
`convertedLog`) com `ValidationFailure`, antes de chamar o service.

Teste novo (`execute_sybase_backup_test.dart`, arquivo novo):
- rejeita differential
- rejeita 3 tipos convertidos
- forwarda options/timeouts/scheduleId/cancelTag corretamente
- scheduleId default cai em `config.id` quando omitido
- rejeita campos obrigatórios em branco

### B.1 — Sybase era o único SGBD sem `ToolPathHelp.isToolNotFoundError` (PR2)

`_pathInstructionsHint` PT-BR (`'não encontrado no PATH do sistema'`)
não casava stderr EN do shell:

```text
'dbisql' is not recognized as an internal or external command,
operable program or batch file.
```

Resultado: quando os binários Sybase estavam fora do PATH, o usuário
recebia mensagem genérica em vez do diagnóstico orientado do
`ToolPathHelp` (que orienta sobre PATH + pasta típica Bin64 do SQL
Anywhere + link para `docs/path_setup.md`).

Mitigação: `_looksLikeToolNotFound(errorLower)` delega para
`ToolPathHelp.isToolNotFoundError`. Aplicado em três caminhos:
1. `_buildNoStrategyWorkedMessage` (quando nenhuma estratégia teve
   sucesso E `result == null`)
2. `_buildProcessResultErrorMessage` (último processo retornou
   `exitCode != 0` mas `result != null`)
3. `testConnection` (probe inicial)

Testes novos:
- mensagem de erro PATH em EN → mensagem orientada do `ToolPathHelp`
  (no caminho de backup)
- mesmo, no caminho de testConnection

### C.1 — Connection string Sybase não escapava `;` e `=` (PR4)

`_buildDbisqlStrategies` e `_buildDbbackupStrategies` interpolam
`serverName`, `databaseName`, `username`, `password` em strings tipo
`ENG=...;DBN=...;UID=...;PWD=...`. Sem sanitização, valores com `;`/`=`
injetavam parâmetros adicionais — `password = "x;LOG=hack.log"`
redirecionaria logs do servidor.

`DatabaseName` value object proíbe `\n\r\t/\<>"*?|` mas permite `;` e
`=` (caso de uso original era nome de arquivo).

Mitigação: novo `SybaseConnectionFieldValidator` em
`lib/core/utils/sybase_connection_field_validator.dart`. Aplicado nos
4 campos relevantes do `SybaseConfigDialog` (`serverName`,
`databaseName`, `username`, `password`). Bases legadas que já têm `;`/
`=` permanecem intocadas — o caminho novo (save no dialog) bloqueia.

Testes novos (`sybase_connection_field_validator_test.dart`, arquivo
novo): valor válido, rejeição de `;`, rejeição de `=`, string vazia,
mensagem orientada pelo nome do campo.

### D.1 — `SybaseConfigDialog` recebia `backupService` no construtor (PR5a)

Inconsistente com `SqlServerConfigDialog`/`PostgresConfigDialog` que
usam `getIt<I*BackupService>()` no `initState`. Sybase era a única
exceção, sem ganho real.

Mitigação: dialog agora resolve via `getIt<ISybaseBackupService>()`.
Testes atualizados em `database_config_dialogs_regression_test.dart`
para registrar o mock no `getIt` antes de exibir o dialog (mesma
estratégia dos outros 3 SGBDs). `sybase_config_page.dart` e
`database_config_page_actions.dart` também atualizados; imports
mortos (`get_it`, `i_sybase_backup_service`) removidos.

### D.2 — `testConnection` timeout 10s (PR5b)

Apertado para servidor remoto/VPN. Postgres já usa 30s — alinhamos
para o mesmo limite. Reduz falsos negativos em redes lentas.

### E.1 — Comentário enganoso da coluna `password` (PR5c)

Paridade AUDIT-11/12: comentário `// Criptografado` substituído por
nota explicando que a coluna fica vazia (senha em secure storage) +
TODO de drop via migration drift.

## Validação

- `flutter analyze --no-fatal-infos` nos 13 arquivos tocados:
  **No issues found**.
- `dart format --set-exit-if-changed`: **0 changed**.
- `flutter test` nas suites afetadas: **114 testes passam**, incluindo:
  - 4 novos no `sybase_backup_service_test.dart` (A.1, B.1 em backup,
    B.1 em testConnection)
  - 5 cenários em `sybase_connection_field_validator_test.dart` (novo)
  - 5 cenários em `execute_sybase_backup_test.dart` (novo)
  - testes existentes do Sybase (~30 no service + rules + enricher +
    repository + use cases + UI) sem regressões

## Pendências não tocadas

- Drop da coluna `sybase_configs.password` via migration drift quando
  houver janela (TODO no próprio arquivo).
- Lacunas mencionadas em `docs/analise_implementacao_sybase.md`:
  testes de integração com SQL Anywhere real (binários reais), testes
  E2E orchestrator + scheduler para preflight de log, normalização de
  tipo no `ScheduleDialog` para cenários legados.
- Compressão Sybase nativa (`dbbackup -C`/`--compress`) não é exposta
  pelo `SybaseBackupOptions` atual — orchestrator faz ZIP/RAR pós-
  backup. Trade-off conhecido, sem ação imediata.
