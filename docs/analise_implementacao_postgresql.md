# Analise da Implementacao PostgreSQL

Atualizado em: 2026-02-28

## Resumo executivo

O suporte a PostgreSQL esta implementado nas camadas de UI, provider, repositorio, servico e orchestrator.
As estrategias `full`, `fullSingle`, `differential` e `log` existem no codigo.

Porem, o documento anterior superestimava o estado atual em alguns pontos:

- verificacao de integridade nao se aplica a todos os tipos.

## O que esta implementado no codigo

1. Configuracao PostgreSQL

- entidade: `PostgresConfig`
- provider: `PostgresConfigProvider`
- repositorio: `PostgresConfigRepository`
- persistencia local: tabela `postgres_configs_table`

2. Seguranca de senha

- senha e salva via `ISecureCredentialService`
- tabela local guarda `password` vazio (`''`)
- senha real e buscada por chave segura (`postgres_password_<id>`)

3. Integracao de execucao

- `BackupOrchestratorService` chama `IPostgresBackupService`
- compressao continua no orchestrator apos gerar backup bruto
- UI de agendamento permite os tipos PostgreSQL: `full`, `fullSingle`, `differential`, `log`

## Estrategias (comportamento real)

### 1) Full

- ferramenta: `pg_basebackup`
- argumentos principais: `-D`, `-P`, `--manifest-checksums=sha256`, `--wal-method=stream`
- saida: diretorio
- verificacao opcional: `pg_verifybackup -D <backupPath>` (quando `verifyAfterBackup=true`)

### 2) Full Single

- ferramenta: `pg_dump`
- argumentos principais: `-F c`, `-f <arquivo.backup>`, `--no-owner`, `--no-privileges`
- escopo: banco configurado (`config.database`)
- saida: arquivo `.backup`
- verificacao opcional: `pg_restore -l <arquivo.backup>`

### 3) Differential (incremental)

- tentativa: `pg_basebackup --incremental=<manifest anterior>`
- requisito tecnico: encontrar FULL anterior com `backup_manifest`
- busca de FULL anterior: pasta atual + pasta irma `Full`
- fallback automatico: se nao achar FULL valido, executa `FULL`
- no fallback, o path final e ajustado para sufixo `_full_` (nao permanece `_incremental_`)

### 4) Log

- ferramenta: `pg_receivewal`
- modo: one-shot com `--endpos=<LSN atual>` e `--no-loop`
- preparacao: consulta LSN atual via `psql` (`SELECT pg_current_wal_lsn();`)
- escopo: captura de WAL para PITR
- saida: segmentos WAL + arquivo `wal_capture_info.txt`
- replication slot dedicado: opcional por ambiente
- verificacao: nao executa pos-validacao nesse tipo
- timeout do modo LOG configuravel por ambiente
- compressao opcional do WAL via `pg_receivewal --compress` com fallback automatico

#### Slot opcional (WAL)

Variaveis suportadas:

- `BACKUP_DATABASE_PG_LOG_USE_SLOT=true|false` (padrao: `false`)
- `BACKUP_DATABASE_PG_LOG_SLOT_NAME=<nome>` (opcional)
- `BACKUP_DATABASE_PG_LOG_TIMEOUT_SECONDS=<segundos>` (opcional, padrao: 3600)
- `BACKUP_DATABASE_PG_LOG_COMPRESSION=<modo>` (opcional, ex.: `gzip`, `lz4`, `none`)

Quando habilitado:

- o servico cria/valida slot com `pg_receivewal --create-slot --if-not-exists`;
- usa `--slot=<nome>` na captura WAL;
- se `BACKUP_DATABASE_PG_LOG_SLOT_NAME` nao for informado, o nome e derivado de `config.id` e sanitizado.
- no delete da configuracao, o sistema tenta remover o slot remoto em modo best effort.

#### Saude de slot (observabilidade)

Variaveis suportadas:

- `BACKUP_DATABASE_PG_SLOT_HEALTH_ENABLED=true|false` (padrao: segue `BACKUP_DATABASE_PG_LOG_USE_SLOT`)
- `BACKUP_DATABASE_PG_SLOT_MAX_LAG_MB=<valor>` (padrao: 1024)
- `BACKUP_DATABASE_PG_SLOT_INACTIVE_HOURS=<valor>` (padrao: 24)

Com isso, o `ServiceHealthChecker` avalia `pg_replication_slots`, gera `HealthIssue` e publica alertas operacionais antes de crescimento excessivo em `pg_wal`.

## Estrutura de saida real

O orchestrator separa por tipo de backup:

```
<backupFolder>/
  Full/
  Full Single/
  Diferencial/
  Log de Transacoes/
```

Dentro de cada pasta, o `PostgresBackupService` gera nome com sufixo por tipo:

- `*_full_<timestamp>/`
- `*_fullSingle_<timestamp>.backup`
- `*_incremental_<timestamp>/`
- `*_log_<timestamp>/`

## Observacao tecnica (incremental)

O orchestrator separa as saidas por tipo de pasta.
Para manter o incremental funcional nesse modelo, o servico agora busca FULL anterior em dois locais:

1. pasta atual do tipo solicitado;
2. pasta irma `Full` no mesmo nivel.

Se ainda assim nao existir FULL valido com `backup_manifest`, ocorre fallback para FULL.

## Verificacao de integridade (estado atual)

- `full`: sim, opcional (`verifyAfterBackup`)
- `fullSingle`: sim, opcional (`verifyAfterBackup`)
- `differential`: sim, opcional (`verifyAfterBackup`)
- `log`: nao

Logo, nao e correto afirmar "verificacao para todos os tipos".

## Ferramentas necessarias por fluxo

- `pg_basebackup`: `full`, `differential`
- `pg_receivewal`: `log`
- `pg_dump`: `fullSingle`
- `pg_verifybackup`: verificacao de `full`/`differential` (quando habilitada)
- `pg_restore`: verificacao de `fullSingle` (quando habilitada)
- `psql`: teste de conexao, listagem de bancos na UI e leitura do LSN atual no modo `log`

## Estado de testes

Foram encontrados testes unitarios especificos para o fluxo PostgreSQL em
`test/unit/infrastructure/external/process/postgres_backup_service_test.dart`.

Cobertura atual identificada:

1. fallback `differential -> full` quando nao ha base anterior;
2. semantica de `log` sem novos segmentos WAL (sucesso com tamanho zero + metadados);
3. erro de `psql` ausente no `testConnection`;
4. erro de `pg_receivewal` ausente no tipo `log`.

Lacunas recomendadas para priorizar:

1. descoberta de FULL anterior considerando pasta atual + pasta irma `Full`;
2. cenarios de verificacao (`pg_verifybackup` e `pg_restore`) por tipo;
3. cenarios de WAL slot habilitado (`--slot`, `--create-slot`) e cleanup no delete da configuracao;
4. fallback de compressao do `pg_receivewal --compress` para execucao sem compressao.

## Conclusao

A implementacao PostgreSQL esta ampla e integrada, mas o documento anterior nao refletia com precisao o comportamento atual.
Este arquivo agora descreve o estado real do codigo, incluindo limitacoes abertas.
