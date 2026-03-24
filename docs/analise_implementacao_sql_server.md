# Analise da Implementacao SQL Server

Atualizado em: 2026-03-24

## Resumo executivo

O suporte a SQL Server esta implementado nas camadas de UI, provider, repositorio, servico e orchestrator.

A documentacao antiga estava desatualizada em pontos importantes, principalmente:

- uso de `INIT` (e nao `NOINIT`);
- deteccao de erros mais precisa (e nao por palavras genericas);
- fluxo real de envio para destinos (feito no `SchedulerService`, nao no `BackupOrchestratorService`).

## O que esta implementado no codigo

1. Configuracao SQL Server

- entidade: `SqlServerConfig`
- provider: `SqlServerConfigProvider`
- repositorio: `SqlServerConfigRepository`
- persistencia local: tabela `sql_server_configs_table`

2. Seguranca de senha

- senha e salva via `ISecureCredentialService`;
- tabela local guarda `password` vazio (`''`);
- senha real e lida por chave segura `sql_server_password_<id>`.

3. Validacao de ferramenta

- `SqlServerConfigProvider` valida `sqlcmd` em `createConfig` e `updateConfig` via `ToolVerificationService.verifySqlCmd`.

4. Integracao de execucao

- `BackupOrchestratorService` chama `ISqlServerBackupService.executeBackup`;
- compressao e script pos-backup continuam no orchestrator;
- envio para destinos e notificacao final ocorrem no `SchedulerService`.
- tipos de backup **convertidos** do Sybase (`convertedDifferential`, `convertedFullSingle`, `convertedLog`) **nao** se aplicam ao SQL Server: o servico retorna falha explicita se forem usados.

## Estrategias de backup (comportamento real)

### 1) Full

- comando: `BACKUP DATABASE`
- extensao: `.bak`
- clausulas: `NOFORMAT, INIT, SKIP, NOREWIND, NOUNLOAD, STATS = <N>` (padrao `N = 10`, configuravel em `SqlServerBackupOptions.statsPercent`)
- opcional: `CHECKSUM` e `STOP_ON_ERROR` quando `enableChecksum=true`
- opcional: clausulas adicionais via `SqlServerBackupOptions.buildWithClause()` (ex.: `COMPRESSION`, `MAXTRANSFERSIZE`, `BUFFERCOUNT`, `BLOCKSIZE`)

### 2) Differential

- comando: `BACKUP DATABASE ... WITH DIFFERENTIAL`
- extensao: `.bak`
- mesmas opcoes de integridade/logistica do full (inclui `STATS`, `CHECKSUM`/`STOP_ON_ERROR`, opcoes avancadas)

### 3) Log

- comando: `BACKUP LOG`
- extensao: `.trn`
- `truncateLog=true`: sem `COPY_ONLY`
- `truncateLog=false`: adiciona `COPY_ONLY`
- opcional: `CHECKSUM` e `STOP_ON_ERROR` quando `enableChecksum=true`; demais opcoes via `SqlServerBackupOptions` como no full

### 4) Full Single

- no servico SQL Server, existe branch para `BackupType.fullSingle`;
- no fluxo real de agendamento, para bancos nao-PostgreSQL, o orchestrator converte `fullSingle` para `full`;
- na UI de agendamento SQL Server, `fullSingle` nao e ofertado.

## Comando base do sqlcmd

O servico usa:

- `-S <server>,<port>`
- `-d <database>`
- `-b` (retorno nao-zero em erro SQL)
- `-r 1` (mensagens de erro em STDERR)
- autenticacao:
  - `-U` quando ha autenticacao SQL (`useWindowsAuth == false` e `username`
    nao vazio) + senha via `SQLCMDPASSWORD` (nao usa `-P` na linha de comando)
  - `-E` quando `useWindowsAuth == true` ou `username` vazio

## Verificacao de integridade

Quando `verifyAfterBackup=true`, executa:

```sql
RESTORE VERIFYONLY FROM DISK = N'<path>' [WITH CHECKSUM]
```

Comportamento:

- timeout de 30 minutos;
- se falhar com `verifyPolicy=bestEffort`, gera warning no log sem marcar falha;
- se falhar com `verifyPolicy=strict`, o backup e marcado como falha.

## Teste de conexao e listagem de bancos

1. Teste de conexao

- query: `SELECT @@VERSION`
- timeout do sqlcmd: `-t 5`
- timeout do processo: 10 segundos

2. Listagem de bancos

- query:
  `SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') ORDER BY name`
- argumentos adicionais: `-h -1`, `-W`, `-t 10`
- timeout padrao do processo: 15 segundos

## Tratamento de erros (estado atual)

O servico nao depende de busca por palavras genericas (`error`, `failed`, etc.).

Ele considera erro por:

- padrao SQL Server (`Msg <numero>` + `Level <numero>`);
- mensagens de cliente `sqlcmd: error`;
- ou `exitCode` de falha (`isSuccess=false`).

Depois da execucao, tambem valida:

- existencia do arquivo;
- tamanho maior que zero.

## Estrutura de saida real

No agendamento:

```text
<backupFolder>/
  Full/
  Diferencial/
  Log de Transações/
```

(O nome das pastas vem de `getBackupTypeDisplayName` / `BackupTypeExtension.displayName`.)

O `SqlServerBackupService` cria arquivo com padrao:

- `<database>_<typeSlug>_<timestamp>.bak` (full/differential)
- `<database>_<typeSlug>_<timestamp>.trn` (log)

Observacao: para SQL Server, `typeSlug` efetivo fica entre `full`, `differential` e `log` no fluxo de agendamento (devido ao ajuste de `fullSingle -> full` no orchestrator).

## Integracao com UI e licenciamento

No `ScheduleDialog`, para SQL Server:

- tipos disponiveis: `full`, `differential`, `log`;
- `truncateLog` aparece apenas para tipo `log`;
- `enableChecksum` e controlado por feature de licenca (`checksum`);
- `verifyAfterBackup` e opcional.

## Diferencas relevantes em relacao ao documento antigo

1. O codigo usa `INIT`, nao `NOINIT`.
2. O detector de erro e baseado em padroes SQL Server + `sqlcmd`, nao em palavras genericas.
3. O envio para destinos nao e responsabilidade do `BackupOrchestratorService`; ocorre no `SchedulerService`.
4. Senha SQL Server e persistida em armazenamento seguro, nao na tabela local.

## Limitacoes atuais

- Nao foram identificadas limitacoes funcionais criticas neste fluxo em relacao ao que esta implementado hoje.

## Estado de testes

Foram encontrados testes unitarios especificos para `SqlServerBackupService` em
`test/unit/infrastructure/external/process/sql_server_backup_service_test.dart`.

Cobertura atual identificada:

- autenticacao SQL (`SQLCMDPASSWORD`, sem `-P`) e Windows (`-E`);
- `verifyAfterBackup` com `verifyPolicy=strict` (falha quando `VERIFYONLY` falha);
- pre-check de recovery model no backup de log (bloqueio em `SIMPLE`);
- montagem de SQL com opcoes avancadas (`COMPRESSION`, `MAXTRANSFERSIZE`, `BUFFERCOUNT`, `BLOCKSIZE`, `STATS`) e escape de identificador.

Lacunas recomendadas para priorizar:

- casos explicitos de `truncateLog` com/sem `COPY_ONLY`;
- cenarios dedicados para parse de erros `Msg/Level` e `sqlcmd: error`;
- casos de `verifyPolicy=bestEffort` para garantir que a falha de verificacao nao interrompe o fluxo.

## Conclusao

O suporte a SQL Server esta funcional e integrado nas camadas citadas. Este arquivo descreve o comportamento atual do codigo, fluxo scheduler/orchestrator e lacunas de teste ainda abertas.
