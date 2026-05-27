# AUDIT-12 — PostgreSQL backup: tool verification, métricas, PG17, cleanup

Data: 2026-05-27
Ficheiros principais:

- `lib/application/providers/postgres_config_provider.dart`
- `lib/infrastructure/external/process/tool_verification_service.dart`
- `lib/infrastructure/external/process/postgres_backup_service.dart`
- `lib/core/di/sgbd_registration.dart`
- `lib/presentation/widgets/postgres/postgres_config_dialog.dart`
- `lib/infrastructure/datasources/local/tables/postgres_configs_table.dart`

Auditoria cobrindo Domain, Application, Infrastructure, Presentation e
testes da fatia PostgreSQL. Quatro PRs lógicos aplicados em sequência
(provider tool verification → flags → mensagens PG17 → cleanup).
Implementação base já é robusta (fallback differential→full, preflight
WAL streaming, slot opcional, cleanup best-effort no delete) — auditoria
fechou gaps de paridade com SQL Server / Sybase e melhorou UX de erros.

## Achados e mitigações

### A.1 — `PostgresConfigProvider` era o ÚNICO SGBD sem validação de ferramentas (PR1)

`SqlServerConfigProvider`, `SybaseConfigProvider` e `FirebirdConfigProvider`
sobrescrevem `verifyToolsOrThrow()` chamando o `ToolVerificationService`
correspondente; o Postgres caía no no-op da classe base. Usuário podia
salvar uma config Postgres sem ter `psql`/`pg_basebackup`/`pg_dump`/
`pg_receivewal` no PATH — só descobria na primeira execução de backup.
Métodos `verifyPsql()` e `verifyPgBasebackup()` já existiam mas nunca
eram chamados.

Mitigação:

- Adicionado `verifyPgDump()`, `verifyPgReceivewal()` e o agregado
  `verifyPostgresTools()` em `ToolVerificationService` (mesmo padrão de
  `verifyFirebirdCliTools`). Curto-circuita na primeira ausência para
  evitar bombardear o usuário com 4 erros. `pg_verifybackup` é apenas
  warning (opcional, só usado quando `verifyAfterBackup=true`).
- `PostgresConfigProvider` recebe `ToolVerificationService` no construtor
  e sobrescreve `verifyToolsOrThrow()`.
- `sgbd_registration.dart` injeta o `ToolVerificationService` no
  `providerBuilder`.

Testes em `tool_verification_service_postgres_test.dart`:
sucesso completo, pg_verifybackup ausente não bloqueia, falha curto-
circuita em psql (não chama os 3 seguintes), falha em pg_dump (3ª
posição).

### A.2 — `BackupFlags` no relatório Postgres era hardcoded e divergia do real (PR2)

```dart
// Antes
flags: BackupFlags(
  compression: false,                                  // ignora --compress=gzip do WAL
  verifyPolicy: verifyAfterBackup ? 'verify' : 'none', // string ad-hoc, não verifyPolicy.name
  stripingCount: 1,
  withChecksum: false,                                 // ignora --manifest-checksums=sha256
  stopOnError: true,                                   // copy/paste do SQL Server, sem sentido em PG
),
```

Histórico/relatório divergia do CLI realmente executado. Outros SGBDs
usam `verifyPolicy.name` (`strict`/`bestEffort`/`none`) — Postgres
quebrava a leitura unificada.

Mitigação:

- Novo `_PgReceiveWalOutcome` retornado por
  `_runPgReceiveWalWithCompressionFallback` carrega o `compressionApplied`
  (null quando houve fallback ou nenhum modo foi requisitado).
- `_BackupCommandResult.compressionApplied` propaga até o orchestrator.
- `_buildPostgresMetrics` agora recebe `verifyPolicy` e
  `compressionApplied`. Derivações:
  - `compression`: `compressionApplied != null`
  - `verifyPolicy`: `verifyAfterBackup ? verifyPolicy.name : 'none'`
  - `withChecksum`: `true` para full/differential (sempre rodam
    `--manifest-checksums=sha256`), `false` para fullSingle/log
  - `stopOnError`: `false` (PG não tem esse conceito; reportar `false`
    sinaliza "N/A")

Testes: full com withChecksum=true + verifyPolicy='none' (sem verify);
fullSingle com withChecksum=false (pg_dump custom format não emite
manifest).

### B.1 — Backup incremental em PG <17 / sem `summarize_wal` retornava mensagem opaca (PR3)

`pg_basebackup --incremental=` foi introduzido no PostgreSQL 17. Em PG
≤16, o cliente devolve `pg_basebackup: error: unrecognized option
'--incremental'`. Em PG 17 com `summarize_wal = off`, o servidor
recusa mencionando explicitamente o GUC. Antes ambos caíam no genérico
`Backup PostgreSQL falhou: <stderr>`, sem orientação ao usuário.

Mitigação: dois pattern matches em `_handleBackupError` quando
`backupType == differential`:

- `_hasUnrecognizedIncrementalOption(outputLower)` → mensagem:
  "Backup incremental requer PostgreSQL 17+. O servidor atual não
  suporta `pg_basebackup --incremental`. Atualize o servidor PostgreSQL
  ou use backup `full` / `fullSingle`."
- `_hasSummarizeWalDisabledError(outputLower)` → mensagem:
  "Backup incremental requer `summarize_wal = on` no postgresql.conf
  do servidor. Habilite o parâmetro e reinicie o serviço PostgreSQL
  antes de tentar novamente."

Testes: dois cenários cobrindo cada mensagem (com base FULL
previamente criada para que o fallback `differential → full` não
dispare antes de chegar ao erro).

### C.1 — `typeSlug` em ternário aninhado (PR4)

Trocado por `switch` expression cobrindo todos os casos do enum
`BackupType` (inclui os convertidos que caem no slug `full` por
fallback). §5.8 do `architectural_patterns.mdc`.

### C.2 — Coluna `password` da tabela Drift com comentário enganoso (PR4)

Mesmo padrão do AUDIT-11 (SQL Server): comentário `// Criptografado`
substituído por nota explicando que a coluna fica vazia (senha em
secure storage) e sugerindo drop via migration drift.

### C.3 — Dialog Postgres com dropdown + textfield manual simultâneos (PR4)

`_buildDatabaseSection` mostrava **dois** controles para o mesmo campo
quando havia databases listados — UX inconsistente com SQL Server
(que tem só um controle alternando entre textfield e dropdown).
Substituído pelo padrão `Row(AppDropdown + spinner/refresh inline)`
do SqlServerConfigDialog. Validação cruzada removida (era confusa).

### C.4 — `pg_restore -l` chamado de "Verificação de integridade" (PR4)

`pg_restore -l` apenas lê o TOC (Table of Contents) do archive custom
format — não valida CRC do payload. Backup com bytes corrompidos no
meio passava. A mensagem antiga (`LoggerService.info('Verificação de
integridade concluída...')`) entregava garantia que não tinha.

Mitigação: trocado por `LoggerService.warning` com texto explícito —
"Esta validação NÃO confere CRC do payload. Para garantia completa,
execute um restore real em ambiente de teste."

## Validação

- `flutter analyze --no-fatal-infos` nos 13 arquivos tocados:
  **No issues found**.
- `dart format --set-exit-if-changed` nos 13: **0 changed**.
- Testes afetados:
  - `postgres_backup_service_test.dart`: 8 (4 antigos + 4 novos:
    PG17 incremental, summarize_wal, BackupFlags full, BackupFlags
    fullSingle)
  - `tool_verification_service_postgres_test.dart`: 4 (novo arquivo)
  - 3 unit + 2 widget tests com `PostgresConfigProvider` instanciado
    atualizados para o novo construtor (passam mock
    `ToolVerificationService`) — `schedule_dialog_*` + `database_config_page_*`.
  - **Total: 12 testes do escopo direto + 23 testes correlatos:
    todos verdes.**

## Pendências não tocadas

- Drop da coluna `postgres_configs.password` via migration drift
  quando houver janela (anotado como TODO no próprio arquivo).
- Lacunas de teste já documentadas em
  `docs/analise_implementacao_postgresql.md`:
  - `_findPreviousFullBackup` no diretório irmão `Full`.
  - `verifyAfterBackup` com `pg_verifybackup` real (full/differential).
  - WAL slot habilitado (`--slot`, `--create-slot`) + cleanup no delete.
  - Fallback de compressão `pg_receivewal --compress=<x>` → sem
    `--compress`.
  - Preflight WAL falhando (wal_level=minimal, max_wal_senders=0,
    rolreplication=false).
