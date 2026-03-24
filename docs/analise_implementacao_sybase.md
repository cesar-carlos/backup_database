# Analise da Implementacao Sybase SQL Anywhere

Atualizado em: 2026-03-24

## Resumo executivo

O suporte a Sybase esta implementado nas camadas de UI, provider, repositorio,
servico e orchestrator/scheduler.

Pontos principais do estado atual:

- backup via `dbisql` (SQL) com fallback para `dbbackup`;
- `fullSingle` e tratado como `full` no servico;
- `differential` no servico vira `log` (effectiveType), mas na UI Sybase o tipo
  e normalizado para `full` ao persistir — ver secao Differential;
- fallback de verificacao `dbvalid -> dbverify` esta ativo;
- fluxo de envio para destinos ocorre no `SchedulerService`, nao no orchestrator.

## O que esta implementado no codigo

1. Configuracao Sybase

- entidade: `SybaseConfig`
- provider: `SybaseConfigProvider`
- repositorio: `SybaseConfigRepository`
- persistencia local: tabela `sybase_configs_table`

2. Seguranca de senha

- senha salva via `ISecureCredentialService`;
- tabela local guarda `password` vazio (`''`);
- senha real lida por chave segura `sybase_password_<id>`.

3. Validacao de ferramentas (UI)

- `SybaseConfigProvider` dispara `ToolVerificationService.verifySybaseToolsDetailed()`
  ao carregar configuracoes (`refreshToolsStatus`, nao bloqueante);
- estado exposto em `toolsStatus` (`SybaseToolsStatus`) para indicar presenca dos
  binarios no PATH (comparavel ao fluxo `sqlcmd` no SQL Server).

4. Integracao de execucao

- `BackupOrchestratorService` chama `ISybaseBackupService.executeBackup`;
- compressao e script pos-backup permanecem no orchestrator;
- upload para destinos, status final, notificacao final e cleanup ficam no
  `SchedulerService`.
- tipos **convertidos** (`convertedDifferential`, `convertedFullSingle`, `convertedLog`) nao geram SQL valido em `_buildBackupSql`; o fluxo `dbisql` falha com mensagem orientando tipo nativo.

## Estrategias de backup (comportamento real)

### 1) Full

- caminho final no servico: `<outputDirectory>/<databaseName>/`
- tentativa principal: `dbisql` com `BACKUP DATABASE DIRECTORY '<path>'`
- fallback: `dbbackup -c '<conn>' -y <path>`
- opcoes Sybase aplicadas quando configuradas (`SybaseBackupOptions`):
  - `CHECKPOINT LOG COPY|NOCOPY|AUTO|RECOVER` (via `buildCheckpointLogClause`);
  - `AUTO TUNE WRITERS ON/OFF`;
  - modo server-side (`-s`) e block size (`-b`, limites 1–4096) no fluxo `dbbackup`;
  - validacao: `CHECKPOINT LOG AUTO` exige `serverSide=true` (erro na UI se
    violado).

### 2) Full Single

- no servico Sybase, `BackupType.fullSingle` e convertido para `full`.

### 3) Differential

- no **servico** (`SybaseBackupService`), `BackupType.differential` e mapeado
  para `effectiveType = log` antes de montar caminho, SQL e `dbbackup`.
- na **UI** (`ScheduleDialog._normalizeBackupTypeForDatabase`), para Sybase,
  `differential` e normalizado para **`full`** ao carregar/editar e ao gravar o
  agendamento; o fluxo usual nao persiste `differential` para Sybase.
- se um agendamento **legado** (ou outra origem) ainda entregar `differential`
  ao orchestrator, a execucao segue o ramo **log** do servico.

### 4) Log

- SQL via `dbisql`: `BACKUP DATABASE DIRECTORY '<path>' TRANSACTION LOG ...`
  - `TRUNCATE`
  - `ONLY`
  - `RENAME`
- `dbbackup` (fallback) por modo:
  - `truncate`: `-t -x`
  - `only`: `-t`
  - `rename`: `-t -r`
- saida em pasta por execucao (`<database>_log_<timestamp>/`), com resolucao
  do arquivo real (`.trn`/`.log`) por `_tryFindLogFile`.

## Estrategias de conexao

### dbisql (tentativa principal)

1. `ENG=<serverName>;DBN=<databaseName>;UID=<user>;PWD=<pass>`
2. `ENG=<serverName>;UID=<user>;PWD=<pass>`
3. `ENG=<databaseName>;DBN=<databaseName>;UID=<user>;PWD=<pass>`

### dbbackup (fallback)

1. `ENG=<serverName>;DBN=<databaseName>;UID=<user>;PWD=<pass>`
2. `ENG=<databaseName>;DBN=<databaseName>;UID=<user>;PWD=<pass>`
3. `ENG=<serverName>;UID=<user>;PWD=<pass>`
4. `HOST=localhost:<port>;DBN=<databaseName>;UID=<user>;PWD=<pass>;LINKS=TCPIP`

### Cache de estrategia

O servico usa `SybaseConnectionStrategyCache` com chave `configId|backupType`,
onde `backupType` passado e o **`effectiveType.name`** apos normalizar
(`fullSingle` -> `full`, `differential` -> `log`), nao o enum bruto do
agendamento.

- **TTL padrao do cache**: 10 minutos (`SybaseConnectionStrategyCache`);
- em falha de `dbisql`/`dbbackup`, a entrada correspondente e **invalidada** para
  forcar nova descoberta na proxima execucao.

## Variaveis de ambiente e PATH

Diferente do PostgreSQL (WAL/slots com `BACKUP_DATABASE_PG_*`), **nao ha**
variaveis de ambiente dedicadas ao fluxo de backup Sybase no
`SybaseBackupService`.

Comportamento pratico:

- `dbisql`, `dbbackup`, `dbvalid` e `dbverify` precisam estar resolviveis via
  **PATH** do processo (ou diretorio do executavel detectado pelo
  `ProcessService`, que pode prefixar PATH do subprocesso);
- mensagens de erro do `ProcessService` orientam pasta tipica **Bin64** do SQL
  Anywhere e referencia a `docs/path_setup.md`.

Opcoes de backup avancadas (checkpoint, server-side, block size, modo de log)
vêm de **`SybaseBackupOptions`** no agendamento / serializacao, nao de env.

## Timeouts

Valores usados pelo `SybaseBackupService` (parametros do agendamento quando
existem):

| Etapa                          | Parametro       | Padrao no codigo |
| ------------------------------ | --------------- | ---------------- |
| `dbisql` / `dbbackup` (backup) | `backupTimeout` | **2 horas**      |
| `dbvalid` / `dbverify`         | `verifyTimeout` | **30 minutos**   |
| `testConnection` (`dbisql`)    | fixo            | **10 segundos**  |

## Verificacao de integridade

Quando `verifyAfterBackup=true`:

- `full`: tenta `dbvalid` no arquivo `.db` do backup;
- se `dbvalid` falhar, tenta fallback `dbverify` (ativo);
- `log`: verificacao nao disponivel; registra `verifyPolicy='log_unavailable'`.

Semantica por politica:

- `VerifyPolicy.bestEffort`: falha de verificacao gera warning e backup segue;
- `VerifyPolicy.strict`: falha de verificacao (full) encerra com erro.

### Metricas e observabilidade (`BackupMetrics`)

Apos backup (e verificacao quando aplicavel), o servico monta `BackupMetrics`:

- **Duracoes**: `backupDuration`, `verifyDuration`, `totalDuration` (soma);
- **Tamanho / desempenho**: `backupSizeBytes`, `backupSpeedMbPerSec`;
- **`backupType`**: nome do **`effectiveType`** (`full` ou `log`), nao o tipo
  bruto do agendamento (ex.: `differential` executado como log aparece como
  `log`).

`BackupFlags` (Sybase) no codigo atual:

- `compression`: `false` (compressao continua no orchestrator, pos-backup);
- `stripingCount`: `1`;
- `withChecksum`: `false`;
- `stopOnError`: `true`;
- **`verifyPolicy`** (string em `flags.verifyPolicy`, espelho operacional):

| Valor             | Significado                                                            |
| ----------------- | ---------------------------------------------------------------------- |
| `none`            | `verifyAfterBackup=false`                                              |
| `log_unavailable` | tipo efetivo `log` (verificacao nao aplicavel)                         |
| `dbvalid`         | verificacao ok com `dbvalid`                                           |
| `dbverify`        | `dbvalid` falhou e `dbverify` ok (fallback)                            |
| `dbvalid_falhou`  | ambas falharam ou sem `.db`; em `bestEffort` o backup pode ter sucesso |

**`sybaseOptions` (JSON em metricas)**: copia de `SybaseBackupOptions.toJson()`
com campos adicionais preenchidos na execucao:

- `verificationMethod`: mesmo sentido que `flags.verifyPolicy` (historico /
  depuracao);
- `backupMethod`: `dbisql` ou `dbbackup` (qual ramo venceu);
- `connectionStrategy`: rotulo da string de conexao usada (ex.: nome da
  estrategia em `connectionStrategies` ou indice).

Esses dados entram em `BackupMetrics.toJson()` sob a chave `sybaseOptions` quando
nao vazios.

## Preflight de log e regras de replicacao

No orchestrator, para Sybase `log`:

- executa `ValidateSybaseLogBackupPreflight`;
- exige full anterior bem-sucedido para o mesmo agendamento;
- pode emitir warning de cadeia (ex.: full antigo, ultimo backup com erro).

Regra adicional:

- se `config.isReplicationEnvironment=true`, modo `truncate` para log e
  bloqueado (exige `rename` ou `only`).

## Ferramentas necessarias

- `dbisql`
- `dbbackup`
- `dbvalid` (recomendado para verificacao)
- `dbverify` (fallback de verificacao quando `dbvalid` falha)

## Estrutura de saida real

No agendamento, o orchestrator separa por tipo de pasta (nome de exibicao do
tipo efetivo):

```text
<backupFolder>/
  Full/
  Log de Transações/
```

(O nome das pastas vem de `getBackupTypeDisplayName`. Uma pasta `Diferencial/`
so aparece se o tipo efetivo do agendamento for diferencial; no fluxo Sybase
atual via UI o tipo gravado tende a ser `full` ou `log`, nao `differential`.)

Dentro da pasta do tipo para Sybase:

- full: `<databaseName>/...`
- log: `<databaseName>_log_<timestamp>/...`

## Estado de testes

Existem testes unitarios especificos para o fluxo Sybase em:

- `test/unit/infrastructure/external/process/sybase_backup_service_test.dart`

Cobertura identificada inclui:

1. `verifyDuration` refletindo tempo real;
2. `log_unavailable` para verificacao de log;
3. conversao `differential -> log` no servico;
4. modos de log (`truncate`, `only`, `rename`) e flags do `dbbackup`;
5. fallback `dbisql -> dbbackup`;
6. `VerifyPolicy.strict` falhando quando verificacao falha;
7. matriz `dbvalid`/`dbverify` (sucesso e falha);
8. resolucao de arquivo de log `.trn`/`.log`.

Lacunas recomendadas:

1. testes de integracao com SQL Anywhere real (binarios reais);
2. testes de ponta a ponta orchestrator + scheduler para preflight de log;
3. testes focados na normalizacao de tipo no `ScheduleDialog` para cenarios
   legados com diferencial Sybase.

## Conclusao

A implementacao Sybase esta integrada nas camadas citadas. Este arquivo descreve
comportamento do servico, UI, PATH/timeouts, metricas e o descompasso entre
normalizacao na UI (`differential` -> `full`) e mapeamento no servico
(`differential` -> `log`) para dados legados.
