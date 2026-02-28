# Analise da Implementacao Sybase SQL Anywhere

Atualizado em: 2026-02-28

## Resumo executivo

O suporte a Sybase esta implementado nas camadas de UI, provider, repositorio,
servico e orchestrator/scheduler.

Pontos principais do estado atual:

- backup via `dbisql` (SQL) com fallback para `dbbackup`;
- `fullSingle` e tratado como `full` no servico;
- `differential` e tratado como `log` no servico;
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

3. Integracao de execucao

- `BackupOrchestratorService` chama `ISybaseBackupService.executeBackup`;
- compressao e script pos-backup permanecem no orchestrator;
- upload para destinos, status final, notificacao final e cleanup ficam no
  `SchedulerService`.

## Estrategias de backup (comportamento real)

### 1) Full

- caminho final no servico: `<outputDirectory>/<databaseName>/`
- tentativa principal: `dbisql` com `BACKUP DATABASE DIRECTORY '<path>'`
- fallback: `dbbackup -c '<conn>' -y <path>`
- opcoes Sybase aplicadas quando configuradas:
  - `CHECKPOINT LOG ...`
  - `AUTO TUNE WRITERS ON/OFF`
  - modo server-side (`-s`) e block size (`-b`) no fluxo `dbbackup`

### 2) Full Single

- no servico Sybase, `BackupType.fullSingle` e convertido para `full`.

### 3) Differential

- no servico Sybase, `BackupType.differential` e convertido para `log`.
- observacao de UI: no `ScheduleDialog`, Sybase normaliza `differential` para
  `full` ao salvar/editar; ou seja, no fluxo padrao de UI ele nao segue para
  execucao como diferencial.

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

O servico usa `SybaseConnectionStrategyCache` por `config.id + backupType` para
reutilizar a ultima estrategia bem-sucedida e invalidar cache em falha.

## Verificacao de integridade

Quando `verifyAfterBackup=true`:

- `full`: tenta `dbvalid` no arquivo `.db` do backup;
- se `dbvalid` falhar, tenta fallback `dbverify` (ativo);
- `log`: verificacao nao disponivel; registra `verifyPolicy='log_unavailable'`.

Semantica por politica:

- `VerifyPolicy.bestEffort`: falha de verificacao gera warning e backup segue;
- `VerifyPolicy.strict`: falha de verificacao (full) encerra com erro.

Sinais em metricas (`BackupMetrics.flags.verifyPolicy`):

- `none`
- `log_unavailable`
- `dbvalid`
- `dbverify`
- `dbvalid_falhou`

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
  Log de Transacoes/
  (Diferencial/ pode existir em cenarios legados)
```

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

A implementacao Sybase esta ampla e integrada, mas havia contradicoes no
documento anterior (principalmente em `differential`, fallback `dbverify` e
modos de log do `dbbackup`).

Este arquivo agora descreve o estado real do codigo em 2026-02-28.
