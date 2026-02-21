# Analise da Implementacao SQL Server

Atualizado em: 2026-02-21

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

## Estrategias de backup (comportamento real)

### 1) Full
- comando: `BACKUP DATABASE`
- extensao: `.bak`
- clausulas: `NOFORMAT, INIT, SKIP, NOREWIND, NOUNLOAD, STATS = 10`
- opcional: `CHECKSUM` quando `enableChecksum=true`

### 2) Differential
- comando: `BACKUP DATABASE ... WITH DIFFERENTIAL`
- extensao: `.bak`
- mesmas opcoes de integridade/logistica do full

### 3) Log
- comando: `BACKUP LOG`
- extensao: `.trn`
- `truncateLog=true`: sem `COPY_ONLY`
- `truncateLog=false`: adiciona `COPY_ONLY`
- opcional: `CHECKSUM`

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
  - `-U/-P` quando `username` informado
  - `-E` quando `username` vazio

## Verificacao de integridade

Quando `verifyAfterBackup=true`, executa:

```sql
RESTORE VERIFYONLY FROM DISK = N'<path>' [WITH CHECKSUM]
```

Comportamento:

- timeout de 30 minutos;
- se falhar, gera warning no log, sem marcar o backup como falha.

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
  Log de Transacoes/
```

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

- Apesar do backend suportar autenticacao Windows com `-E` quando `username` vazio, a UI de configuracao atualmente exige usuario e senha no fluxo de teste de conexao.

## Estado de testes

Nao foram encontrados testes unitarios/integracao especificos para:

- `SqlServerBackupService`;
- casos de `verifyAfterBackup`;
- casos de `truncateLog` com/sem `COPY_ONLY`;
- parse de erros `Msg/Level` e `sqlcmd: error`.

Existe teste apenas da entidade `SqlServerConfig`.

## Conclusao

O suporte a SQL Server esta funcional e integrado, mas a documentacao antiga nao refletia o comportamento atual.
Este arquivo agora descreve o estado real da implementacao, incluindo limitacoes e lacunas de teste.
