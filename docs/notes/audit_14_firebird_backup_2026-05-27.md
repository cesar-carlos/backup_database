# AUDIT-14 — Firebird backup: paridade final de BackupFlags

Data: 2026-05-27
Ficheiros principais:

- `lib/infrastructure/external/process/firebird_backup_service.dart`

Auditoria completa da fatia Firebird (gbak / nbackup / gstat / isql),
fechando a série SQL Server (AUDIT-11) + Postgres (AUDIT-12) + Sybase
(AUDIT-13). Firebird é a fatia **mais robusta** das quatro graças ao
ADR-014 que já documentava as decisões CLI corretas, e ao trabalho
prévio do MVP que já tinha aplicado a maioria das correções que os
outros SGBDs precisaram nos audits anteriores.

Resultado: **apenas 1 PR** aplicado neste audit (paridade de
`stopOnError`) — todos os outros padrões já estavam corretos.

## Estado pré-AUDIT-14 (paridade já atingida)

| Achado típico dos audits 11/12/13 | Estado Firebird |
| --- | --- |
| Provider valida ferramentas no save | ✅ pré-existente (`verifyFirebirdCliTools`) |
| Dialog usa `getIt` no `initState` | ✅ pré-existente |
| Strategy factory passa `backupTimeout`/`verifyTimeout`/`verifyPolicy`/`firebirdNbackupPhysicalLevel` | ✅ pré-existente |
| `ToolPathHelp.isToolNotFoundError` (PT+EN) | ✅ pré-existente |
| Comentário `// Criptografado` na coluna password | ✅ já limpo + bonus: `cryptKey` ainda tem migração transparente do SQLite legado para secure storage em `rowToEntity` |
| Connection string injection (`;`/`=`) | (não aplicável — Firebird usa args separados `-user`/`-pas`, não interpola em string única) |
| Use case dead code / desatualizado | (não existe `ExecuteFirebirdBackup`) |

Pontos adicionais que reforçam a qualidade:

- ADR-014 explícito documentando o que **não fazer** (`-PROVIDER Engine12`
  retry, `nbackup -SE`, `gbak -key`).
- `_rejectCryptKeyIfPresent` rejeita upfront em vez de gerar comando
  inválido.
- `_gbakServiceManagerSwitch` aplica `-SE` **apenas em gbak** (nunca
  em nbackup), respeitando `serviceManagerMode` + `serverVersionHint`.
- `_failureFromProcess` tem matriz de mensagens orientadas (WireCrypt,
  auth com remediação `AuthServer = Legacy_Auth, Srp`, not found,
  connection). Trunca em 200 chars com word boundary.
- `_clientLibEnvironment` injeta diretório do `fbclient.dll` no
  `Path`/`PATH`.
- `FirebirdEmbeddedSupport.validateEmbeddedEnginePlugins` valida
  `engine12.dll`/`engine13.dll` em `bin/plugins` E `plugins` (ambos
  layouts).
- `_resolveNbackupBArgument` + `firebirdRuntimeSupportsNbackupGuidMode`:
  em FB 4.0 usa GUID do parent via `RDB$BACKUP_HISTORY` (mais robusto);
  FB <4 cai no chain file-based com pré-validação por
  `missingFirebirdNbackupChainPattern`.
- AUDIT-10 já corrigiu o stub `listDatabases` para retornar `Failure`.

## Achados e mitigações

### A.1 — `BackupFlags.stopOnError: true` hardcoded (PR1)

Único achado de paridade que ainda faltava. Firebird não tem conceito
equivalente ao `STOP_ON_ERROR` do SQL Server — `gbak`/`nbackup` apenas
falham com exit code não-zero. Valor `true` era copy/paste enganoso no
relatório/histórico, mesmo padrão já corrigido em AUDIT-12 (Postgres)
e AUDIT-13 (Sybase).

Mitigação: `stopOnError: false` em `_flagsForFirebirdBackup`. Outros
flags do mesmo bloco (`compression`, `stripingCount=1`,
`withChecksum=false`) também são N/A em Firebird mas menos enganosos —
mantidos como estão. O campo realmente significativo é
`firebirdVersion` (Auto + tagline `WI-V*` detectada via `gbak -z`, ou
hint manual `v25`/`v30`/`v40`).

Teste novo em `firebird_backup_service_test.dart`: `BackupFlags.stopOnError
= false no relatorio (achado A.1 AUDIT-14)` — exercita o caminho
nbackup (físico) e verifica que `metrics.flags.stopOnError == false`,
plus sanity checks de `compression`, `stripingCount`, `withChecksum` e
`tool`.

## Achados deixados intencionalmente sem ação

### A.2 — `FirebirdBackupStrategyStub` é dead code completo

`lib/application/services/strategies/firebird_backup_strategy_stub.dart`
— definido mas zero call sites (`grep` confirmou). Diferente do
`FirebirdBackupServiceStub` que pelo menos é referenciado em
`real_database_connection_prober_test.dart` para acesso à constante
`notImplementedMessage`.

Decisão do user: **manter como safety net** (eventual cenário de DI
parcial onde `IDatabaseBackupStrategy<FirebirdConfig>` é resolvido
sem o service real registrado). Não é dead code em sentido estrito
quando considerado como contrato implementado mas não exposto. Risco
de manter é baixo (36 linhas, sem dependências cíclicas).

Se posteriormente decidir limpar: simples `Delete` do arquivo + grep
para confirmar ausência de import.

## Validação

- `flutter analyze --no-fatal-infos` nos 2 arquivos tocados: **No issues
  found**.
- `dart format --set-exit-if-changed`: **0 changed**.
- `flutter test test/unit/infrastructure/external/process/firebird_backup_service_test.dart`:
  **65 testes passam** (64 pré-existentes + 1 novo).

## Pendências não tocadas (registo histórico)

- `FirebirdBackupStrategyStub` continua presente como safety net
  (decisão acima).
- Encriptação `gbak` (trio `-CRYPT` + `-KEYHOLDER` + `-KEYNAME`) com UI
  dedicada ainda é roadmap — `_rejectCryptKeyIfPresent` rejeita upfront
  com mensagem clara até lá. Doc em ADR-014 §"Mitigações para roadmap".
- `nbackup` remoto via Services Manager (`fbsvcmgr`) continua roadmap
  (estimativa 200–300 linhas + testes). Doc em ADR-014.

## Encerramento da série SQL Server / Postgres / Sybase / Firebird

| Audit | Commit | PRs aplicados |
| --- | --- | --- |
| AUDIT-11 (SQL Server) | `ee1561d` | 4 PRs: timeouts no factory, validação de options, cleanup |
| AUDIT-12 (Postgres) | `6706009` | 4 PRs: tool verification, BackupFlags accurate, PG17 incremental errors, cleanup |
| AUDIT-13 (Sybase) | `079c050` | 5 PRs: stopOnError, ToolPathHelp PT+EN, use case API + reject differential, connection string injection hardening, cleanup |
| **AUDIT-14 (Firebird)** | _este commit_ | **1 PR**: stopOnError |

Os 4 SGBDs estão agora alinhados quanto a:
- Tool verification no save (provider chama `verify*Tools`)
- Dialog usando `getIt<IxxxBackupService>` no `initState`
- Strategy factory passando timeouts/options/verifyPolicy completos
- `ToolPathHelp.isToolNotFoundError` para mensagens PT+EN
- `BackupFlags.stopOnError = false` quando não-aplicável
- Comentário enganoso da coluna `password` corrigido
- Senhas (e `cryptKey` em Firebird) em secure storage com migração
  transparente do SQLite legado
