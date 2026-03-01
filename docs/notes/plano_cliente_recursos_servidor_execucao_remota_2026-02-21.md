# Plano: Cliente Consumindo Recursos do Servidor (Backup Remoto Orquestrado)

Data base: 2026-02-21
Atualizado em: 2026-02-28
Status: Em andamento - infraestrutura base implementada; contrato REST-like e regras de concorrencia/fila pendentes
Escopo: cliente Flutter desktop + servidor Flutter desktop (socket TCP)

## Estado de Implementacao (2026-02-28)

### Infraestrutura base (implementada)

- Protocolo binario TCP: header 16 bytes, payload JSON, compressao GZIP, checksum CRC32
- Auth: `authRequest` / `authResponse` / `authChallenge` com validacao de licenca no servidor
- Agendamentos: `listSchedules`, `updateSchedule`, `executeSchedule`, `cancelSchedule` + respostas
- Progresso de backup: `backupProgress`, `backupStep`, `backupComplete`, `backupFailed`
- Transferencia de arquivo: chunked, resume (`startChunk`), path validation, lock, checksum
- Metricas: `metricsRequest` / `metricsResponse`
- Sistema: `heartbeat`, `disconnect`, `error`
- `ErrorCode` enum + `createErrorMessage` com `errorCode` + `errorMessage`
- Reconexao com backoff exponencial no cliente

### Lacunas identificadas (bloqueiam P0)

- `client_handler.dart` encaminha mensagens para handlers sem verificar `isAuthenticated` - bypass pre-auth possivel
- `createScheduleErrorMessage` omite `errorCode` no payload - erro de schedule nao segue contrato padronizado
- Sem envelope de resposta REST-like com `statusCode` padronizado
- Sem tabela oficial de status code para operacoes remotas
- Sem `capabilitiesRequest` / `capabilitiesResponse` no protocolo
- Sem CRUD remoto de configuracao de banco (`createDatabaseConfig`, etc.)
- Sem `testDatabaseConnection` remoto
- Sem `getExecutionStatus` para polling de execucao em curso
- Sem `validateServerBackupPrerequisites` (preflight de compactacao/pasta temp)
- Sem regra formal de concorrencia: apenas 1 backup por vez
- Sem regra formal de fila para disparos agendados quando ha backup em execucao
- Sem endpoint formal para health do servidor (`getServerHealth`)
- Sem endpoint formal para sessao atual (`getSession` / `whoAmI`)
- Sem endpoint para cancelar item enfileirado (`cancelQueuedBackup`)
- Sem endpoint para metadados do artefato (`getArtifactMetadata`)
- Sem endpoint de diagnostico por execucao (`getRunLogs`, `getRunErrorDetails`)
- Sem comandos de agendamento completos (`createSchedule`, `deleteSchedule`, `pauseSchedule`, `resumeSchedule`)
- Sem idempotencia por `runId`

---

## Objetivo

- [ ] Padronizar API socket com comunicacao inspirada em REST (status code + erro estruturado + requestId).
- [ ] Definir catalogo completo de recursos cliente->servidor com contrato padrao por endpoint.
- [ ] Permitir que o cliente configure bases de dados no servidor e execute testes de conexao pelo servidor.
- [ ] Garantir que o agendamento seja controlado pelo cliente.
- [ ] Garantir que o destino final seja controlado pelo cliente.
- [ ] Garantir que todo fluxo de backup (dump, compactacao, validacao e artefato final) ocorra no servidor.
- [ ] Garantir que compressao, checksum e demais opcoes sejam aplicadas no servidor conforme configuracao enviada pelo cliente.
- [ ] Garantir limite de 1 backup em execucao por servidor.
- [ ] Garantir que disparo manual durante execucao ativa seja rejeitado com erro claro para o cliente.
- [ ] Garantir que disparo agendado durante execucao ativa entre em fila para execucao posterior.
- [ ] Entregar ao cliente o arquivo final pronto para continuar o fluxo de distribuicao aos destinos finais.

## Contrato de Comunicacao Padrao (REST-like sobre Socket)

### Envelope padrao de request

```json
{
  "type": "executeBackup",
  "requestId": "uuid",
  "timestamp": "2026-02-28T12:00:00Z",
  "payload": {}
}
```

### Envelope padrao de response

```json
{
  "type": "executeBackupResponse",
  "requestId": "uuid",
  "statusCode": 202,
  "success": true,
  "data": {},
  "error": null
}
```

### Envelope padrao de erro

```json
{
  "type": "error",
  "requestId": "uuid",
  "statusCode": 409,
  "success": false,
  "data": null,
  "error": {
    "code": "BACKUP_ALREADY_RUNNING",
    "message": "Ja existe um backup em execucao no servidor.",
    "details": {}
  }
}
```

### Tabela minima de status code

- `200` - sucesso sincrono (consulta/alteracao concluida)
- `202` - aceito para processamento assincrono (execucao iniciada ou enfileirada)
- `400` - requisicao invalida
- `401` - nao autenticado
- `403` - sem permissao/licenca
- `404` - recurso nao encontrado
- `409` - conflito de estado (ex.: backup manual com outro backup em execucao)
- `410` - recurso expirado/indisponivel (ex.: artefato de backup removido por TTL)
- `422` - validacao de dominio
- `429` - limite/throughput excedido
- `500` - erro interno
- `503` - servico indisponivel/pre-requisito nao atendido

## Politica de Concorrencia e Fila (Obrigatoria)

- [ ] `maxConcurrentBackups = 1` no servidor.
- [ ] Disparo manual (`executeBackup`) com backup ativo deve retornar `409 BACKUP_ALREADY_RUNNING`.
- [ ] Disparo agendado com backup ativo deve entrar em fila (`queued`) e retornar `202`.
- [ ] Fila deve ser FIFO por padrao.
- [ ] Cada item em fila deve ter `runId`, `scheduleId`, `queuedAt`, `requestedBy`.
- [ ] Cliente deve receber eventos `backupQueued`, `backupDequeued`, `backupStarted`.
- [ ] `getExecutionStatus` deve informar `queuedPosition`, `state`, `runId`.
- [ ] Cancelamento deve suportar:
  - cancelar execucao ativa
  - remover item enfileirado

## Regras Operacionais Criticas (Obrigatorias)

- [ ] Definir maquina de estados oficial de execucao e transicoes validas:
  - `queued -> running -> completed|failed|cancelled`
  - transicao invalida deve retornar erro padronizado (`409` + `INVALID_STATE_TRANSITION`)
- [ ] Implementar idempotencia por comando com `idempotencyKey` (inicio/cancelamento/criacao):
  - deduplicacao no servidor por janela configuravel
  - mesma chave + mesmo payload retorna mesmo resultado logico
- [ ] Definir politica formal de fila:
  - `maxQueueSize`
  - TTL para item enfileirado
  - tratamento de overflow (`429` ou `503`, conforme causa)
  - regra para duplicidade de `scheduleId` ja enfileirado
- [ ] Persistir fila/estado de execucao para recuperacao apos restart do servidor.
- [ ] Adicionar resiliencia de eventos:
  - todo evento deve incluir `eventId`, `sequence`, `runId`, `occurredAt`
  - cliente deve conseguir re-sincronizar via `getExecutionStatus/getExecutionQueue` apos reconexao
- [ ] Padronizar correlacao ponta-a-ponta por `runId` (progresso, logs, erros, metadados, download).
- [ ] Definir politica de retencao de artefato/staging:
  - TTL do artefato
  - janela de cleanup
  - retorno `410` para artefato expirado
- [ ] Fechar matriz de erro operacional:
  - `errorCode -> statusCode -> retryable (true/false) -> acao esperada do cliente`

## Resultado Esperado (Fluxo To-Be)

- [~] Cliente autentica no servidor com licenca valida para controle remoto. _(auth implementado; bloqueio pre-auth tem gap - ver F0.1)_
- [ ] Cliente cria/edita/remove configuracoes de banco de dados no servidor.
- [ ] Cliente executa teste de conexao de banco remotamente, com validacao feita no servidor.
- [~] Cliente controla agenda de execucao e envia comando de backup para o servidor no momento devido. _(executeSchedule implementado; executeBackup por comando direto pendente)_
- [x] Servidor executa backup (dump + compressao + verificacoes) somente quando recebe comando do cliente.
- [ ] Servidor salva artefato em pasta temporaria padrao do servidor. _(fluxo local usa pasta configuravel; fluxo remoto sem policy dedicada)_
- [x] Servidor publica progresso em tempo real para cliente.
- [x] Servidor disponibiliza arquivo final em staging remoto para download resiliente.
- [x] Cliente baixa arquivo pronto e continua seu fluxo local de envio para destinos finais.

## Premissas de Projeto

- [~] Fonte de verdade do agendamento sera o cliente. _(schedules atualmente persistidos no servidor; cliente pode atualizar via updateSchedule)_
- [x] Cliente nao executa dump de banco; somente orquestra e consome artefato final.
- [~] Controle de licenca remota deve ser fail-closed. _(licenca validada em auth e em executeSchedule; nao aplicada em CRUD de banco pois endpoints nao existem)_
- [ ] API remota deve ser versionada e com contrato de erro padronizado.
- [ ] API remota deve ter envelope com `statusCode` para todas as respostas.
- [x] No fluxo remoto, nao havera configuracao manual de pasta temporaria no cliente.
- [ ] No fluxo remoto, o servidor usara pasta temporaria padrao do sistema operacional para staging de execucao/compactacao.
- [ ] Execucao remota deve validar disponibilidade de ferramenta de compactacao no servidor antes de iniciar backup.
- [ ] O servidor aceita somente 1 backup em execucao por vez.
- [ ] Execucoes agendadas concorrentes devem ser enfileiradas.

## Responsabilidade de Execucao (Servidor x Cliente)

- [x] Somente servidor executa: teste de conexao de banco, dump, compactacao, checksum, scripts, limpeza e preparacao de artefato final.
- [x] Cliente executa: controle de agenda, comando de execucao remota, UX, download do artefato pronto e envio para destino final.
- [ ] Qualquer processo dependente de ambiente/ferramenta do servidor deve estar exposto em API remota para o cliente.
- [ ] Pasta temporaria no fluxo remoto e responsabilidade exclusiva do servidor (padrao do SO, sem dependencia de configuracao no cliente).

## Contrato Minimo da API Remota (Cliente -> Servidor)

- [~] Auth e sessao:
  - [x] `authRequest`, `authResponse`
  - [ ] `capabilitiesRequest`, `capabilitiesResponse`
- [ ] Configuracao de banco:
  - [ ] `createDatabaseConfig`, `updateDatabaseConfig`, `deleteDatabaseConfig`
  - [ ] `listDatabaseConfigs`, `getDatabaseConfigById`
  - [ ] `testDatabaseConnection`
- [~] Execucao remota sob comando do cliente:
  - [x] `executeBackup` _(implementado como `executeSchedule`)_
  - [x] `cancelBackup` _(implementado como `cancelSchedule`)_
  - [ ] `getExecutionStatus`
  - [ ] `getExecutionQueue`
- [x] Execucao e progresso:
  - [x] `backupProgress`, `backupComplete`, `backupFailed`
  - [ ] `backupQueued`, `backupDequeued`, `backupStarted`
- [x] Artefato final:
  - [x] `listFiles`, `fileTransferStart`, `fileChunk`, `fileTransferProgress`, `fileTransferComplete`
- [x] Metricas:
  - [x] `metricsRequest`, `metricsResponse`
- [~] Erros:
  - [x] `error` com `errorCode`, `errorMessage`, `requestId` - estrutura existe em `createErrorMessage`
  - [ ] `statusCode` e payload de erro padrao para todos handlers
  - [ ] `createScheduleErrorMessage` nao inclui `errorCode` - contrato inconsistente

## Matriz de Disponibilidade Atual (Confirmado no Codigo)

Data de verificacao: 2026-02-28

### Recursos ja consumiveis pelo cliente (ponta a ponta)

- [x] Autenticacao no connect (handshake):
  - mensagens: `authRequest`, `authResponse`
  - cliente: `ConnectionManager.connect(...)`
  - observacao: resposta de auth ja suporta `errorCode`
- [x] Listar agendamentos remotos:
  - mensagens: `listSchedules` -> `scheduleList`
  - cliente: `ConnectionManager.listSchedules()`
- [x] Atualizar agendamento remoto:
  - mensagens: `updateSchedule` -> `scheduleUpdated`
  - cliente: `ConnectionManager.updateSchedule(...)`
- [x] Executar backup remoto por agendamento:
  - mensagens: `executeSchedule` + eventos `backupProgress`/`backupComplete`/`backupFailed`
  - cliente: `ConnectionManager.executeSchedule(...)`
- [x] Cancelar backup remoto em execucao:
  - mensagens: `cancelSchedule` -> `scheduleCancelled`
  - cliente: `ConnectionManager.cancelSchedule(...)`
  - observacao: cancela apenas a execucao atual do `scheduleId` em andamento
- [x] Listar arquivos disponiveis no staging remoto:
  - mensagens: `listFiles` -> `fileList`
  - cliente: `ConnectionManager.listAvailableFiles()`
- [x] Baixar arquivo remoto com resume:
  - mensagens: `fileTransferStart`, `fileChunk`, `fileTransferProgress`, `fileTransferComplete`, `fileTransferError`
  - cliente: `ConnectionManager.requestFile(...)`
  - observacao: resume por `startChunk` e validacao de integridade por tamanho/hash no cliente
- [x] Consultar metricas do servidor:
  - mensagens: `metricsRequest` -> `metricsResponse`
  - cliente: `ConnectionManager.getServerMetrics()`

### Recursos parcialmente disponiveis (indireto/sem endpoint dedicado)

- [~] Verificar servidor online:
  - hoje: indireto via `connect()/status/isConnected` no cliente
  - gap: sem endpoint formal `getServerHealth`
- [~] Saber se existe backup em andamento:
  - hoje: indireto via `metricsResponse.backupInProgress`
  - gap: sem endpoint formal `getExecutionStatus`
- [~] Regra de concorrencia de backup:
  - hoje: servidor bloqueia segunda execucao concorrente (`tryStartBackup`) e retorna erro textual
  - gap: sem `statusCode`/`errorCode` dedicado (`BACKUP_ALREADY_RUNNING`) e sem politica de fila

### Recursos ainda nao disponiveis para consumo do cliente

- [ ] `getServerHealth` (endpoint dedicado)
- [ ] `getSession` / `whoAmI`
- [ ] `capabilitiesRequest` / `capabilitiesResponse`
- [ ] `validateServerBackupPrerequisites`
- [ ] CRUD remoto completo de configuracao de banco (`createDatabaseConfig`, `deleteDatabaseConfig`, etc.)
- [ ] `testDatabaseConnection` remoto
- [ ] `getExecutionStatus` formal com `runId`, `state`, `queuedPosition`
- [ ] `getExecutionQueue`
- [ ] `cancelQueuedBackup`
- [ ] Eventos formais de fila (`backupQueued`, `backupDequeued`, `backupStarted`)
- [ ] `getArtifactMetadata`
- [ ] `getRunLogs` / `getRunErrorDetails`
- [ ] `pauseSchedule` / `resumeSchedule` remoto
- [ ] Contrato REST-like completo com `statusCode` em todas as respostas

## Estrategia de Incorporacao de Implementacoes Existentes (Sem Reescrita)

Objetivo: incorporar o que ja existe no servidor, preservando regras de negocio atuais e adicionando somente camada de protocolo/socket + padronizacao de resposta.

Principios de implementacao:

- [ ] Nao duplicar regra de dominio em handlers de socket.
- [ ] Reusar use cases, servicos e repositorios existentes como fonte unica de regra.
- [ ] Ajustar apenas contrato de mensagem (`statusCode`, `errorCode`, `details`) e roteamento.
- [ ] Manter comportamento atual onde ja funciona e evoluir incrementalmente por PR.

Mapa de incorporacao imediata (confirmado no codigo):

- [ ] Agendamentos:
  - base existente: `IScheduleRepository` + `UpdateSchedule` + `SchedulerService.executeNow/cancelExecution`
  - API alvo: `createSchedule`, `listSchedules`, `updateSchedule`, `deleteSchedule`, `pauseSchedule`, `resumeSchedule`, `executeBackup`, `cancelBackup`
  - regra preservada: execucao continua centralizada no scheduler do servidor
  - ajuste minimo: completar tipos de mensagem/handler para comandos faltantes
- [ ] Configuracao de banco (por engine):
  - base existente: `ISybaseConfigRepository`, `ISqlServerConfigRepository`, `IPostgresConfigRepository` (CRUD completo)
  - API alvo: `createDatabaseConfig`, `updateDatabaseConfig`, `deleteDatabaseConfig`, `listDatabaseConfigs`, `getDatabaseConfigById`
  - regra preservada: validacoes e persistencia continuam no backend atual
  - ajuste minimo: adicionar handler/protocol remoto por tipo
- [ ] Teste de conexao e descoberta de base:
  - base existente: `SybaseBackupService.testConnection`, `SqlServerBackupService.testConnection`, `PostgresBackupService.testConnection`
  - base complementar: `SqlServerBackupService.listDatabases/listBackupFiles`, `PostgresBackupService.listDatabases`
  - API alvo: `testDatabaseConnection` (+ `listDatabases` opcional por capability)
  - regra preservada: teste executa no servidor, sem dependencia local do cliente
  - ajuste minimo: normalizar retorno por `statusCode/errorCode`
- [ ] Preflight de prerequisitos:
  - base existente: `ToolVerificationService` + `validate_backup_directory` + `StorageChecker` + `validate_sybase_log_backup_preflight`
  - API alvo: `validateServerBackupPrerequisites`
  - regra preservada: bloqueios tecnicos continuam decididos no servidor
  - ajuste minimo: consolidar resultado em payload unico (`blockingIssues`, `warnings`, `toolStatus`)
- [ ] Status de execucao e concorrencia:
  - base existente: `SchedulerService.executeNow/cancelExecution` + estado publicado em `metricsResponse.backupInProgress`
  - API alvo: `getExecutionStatus`, `getExecutionQueue`, `cancelQueuedBackup`
  - regra preservada: apenas 1 backup por vez no servidor
  - ajuste minimo: formalizar `runId/state/queuedPosition` e eventos de fila
- [ ] Diagnostico e rastreabilidade:
  - base existente: `IBackupHistoryRepository`, `BackupLogRepository.getByBackupHistory`, `LogService.getLogs`
  - API alvo: `getRunLogs`, `getRunErrorDetails`
  - regra preservada: fonte de log/historico continua no servidor
  - ajuste minimo: correlacao por `runId` no contrato remoto
- [ ] Artefato e staging:
  - base existente: `TransferStagingService.copyToStaging/cleanupStaging/cleanupOldBackups`
  - API alvo: `getArtifactMetadata` + `cleanupStaging` remoto
  - regra preservada: geracao/limpeza de artefato segue no servidor
  - ajuste minimo: expor cleanup via socket (nao executar cleanup local no cliente)

Ajuste obrigatorio ja identificado:

- [ ] Corrigir `remote_file_transfer_provider.dart` que chama `_transferStagingService.cleanupStaging(scheduleId)` localmente; trocar por comando remoto no servidor (`cleanupStagingRequest/Response`) para manter modelo server-first.

---

## Fase 0 - Hardening de Base Remota (P0)

Objetivo: fechar lacunas de seguranca e contrato antes de expandir API.

- [ ] F0.1 Bloquear processamento de mensagens nao-auth quando conexao ainda nao autenticada.
      Situacao: `client_handler.dart` encaminha toda mensagem para `_messageController` sem verificar `isAuthenticated`. Handlers (`ScheduleMessageHandler`, etc.) nao fazem essa verificacao.
      Arquivos:
  - `lib/infrastructure/socket/server/client_handler.dart` - adicionar guard em `_tryParseMessages`
  - `lib/infrastructure/socket/server/tcp_socket_server.dart` - verificar se handler checa auth antes de rotear
- [ ] F0.2 Padronizar erro remoto com `errorCode` + `errorMessage` para todos handlers.
      Situacao: `createErrorMessage` ja suporta `errorCode`; `createScheduleErrorMessage` nao inclui `errorCode`.
      Arquivos:
  - `lib/infrastructure/protocol/schedule_messages.dart` - adicionar `errorCode` em `createScheduleErrorMessage`
  - `lib/infrastructure/socket/server/schedule_message_handler.dart` - passar `ErrorCode` apropriado
  - `lib/infrastructure/socket/server/metrics_message_handler.dart` - verificar e padronizar
- [ ] F0.3 Adicionar endpoint de capacidades (`capabilities`) e versao de API remota.
      Arquivos candidatos:
  - `lib/infrastructure/protocol/message_types.dart` - adicionar `capabilitiesRequest`, `capabilitiesResponse`
  - `lib/infrastructure/socket/server/*_message_handler.dart` - novo `CapabilitiesMessageHandler`
  - `lib/infrastructure/socket/client/connection_manager.dart` - expor `getServerCapabilities()`
- [ ] F0.4 Criar testes de seguranca do handshake e rejeicao pre-auth.
- [ ] F0.5 Definir envelope padrao de response REST-like no socket com `statusCode`, `success`, `data`, `error`.
- [ ] F0.6 Definir tabela de mapeamento `ErrorCode -> statusCode`.

DoD Fase 0:

- [ ] Nenhuma mensagem operacional e aceita antes de auth bem-sucedida.
- [ ] Cliente recebe motivo de erro consistente e acionavel (`statusCode` + `errorCode` + `errorMessage`) em todos os handlers.
- [ ] Cliente consegue descobrir capacidades/versao do servidor antes de operar.

---

## Fase 1 - API Remota de Recursos do Servidor (P0)

Objetivo: expor na API remota tudo que e necessario para o cliente operar recursos que rodam no servidor.

- [ ] F1.1 Adicionar API remota de configuracao de banco (CRUD), reaproveitando repositorios atuais:
  - [ ] `createDatabaseConfig`
  - [ ] `updateDatabaseConfig`
  - [ ] `deleteDatabaseConfig`
  - [ ] `listDatabaseConfigs`
  - [ ] `getDatabaseConfigById`
  - [ ] reutilizar `ISybaseConfigRepository`, `ISqlServerConfigRepository`, `IPostgresConfigRepository`
        Arquivos novos:
  - `lib/infrastructure/protocol/database_config_messages.dart`
  - `lib/infrastructure/socket/server/database_config_message_handler.dart`
- [ ] F1.2 Adicionar API remota de teste de conexao de banco, reaproveitando servicos atuais:
  - [ ] `testDatabaseConnection`
  - [ ] opcional por capability: `listDatabases` e `listBackupFiles`
  - [ ] Validacao e execucao do teste no servidor
  - [ ] Retorno estruturado com motivo de sucesso/falha e `statusCode`/`errorCode`
  - [ ] reutilizar `SybaseBackupService.testConnection`, `SqlServerBackupService.testConnection`, `PostgresBackupService.testConnection`
- [ ] F1.3 Adicionar API remota de execucao sob comando do cliente:
  - [x] `executeBackup` _(via `executeSchedule`)_
  - [x] `cancelBackup` _(via `cancelSchedule`)_
  - [ ] `getExecutionStatus` - polling de status de execucao em curso
  - [ ] `getExecutionQueue` - consulta de fila ativa
  - [ ] reutilizar `SchedulerService.executeNow/cancelExecution` e estado atual exposto em `metricsResponse`
- [ ] F1.4 Enforcar policy de licenca no servidor para configuracao de banco, teste de conexao e execucao.
- [ ] F1.5 Adaptar `ConnectionManager` e providers de cliente para consumir os novos endpoints sem quebrar fronteiras da arquitetura.
- [ ] F1.6 Garantir persistencia no servidor de configuracao completa de backup remoto (compressao, checksum, script etc).
- [ ] F1.7 Testes unitarios + integracao para CRUD de banco, teste de conexao e execucao remota sob comando.
- [ ] F1.8 Adicionar API de preflight para validar prerequisitos de execucao no servidor, reaproveitando use cases/servicos ja existentes:
  - [ ] `validateServerBackupPrerequisites`
  - [ ] checagem de ferramenta de compactacao
  - [ ] checagem de permissao/escrita na pasta temporaria padrao do servidor
  - [ ] retorno estruturado de bloqueios e avisos
  - [ ] reutilizar `ToolVerificationService`, `validate_backup_directory`, `StorageChecker`, `validate_sybase_log_backup_preflight`
- [ ] F1.9 Completar comandos remotos de agendamento faltantes sem alterar regra de negocio do scheduler:
  - [ ] `createSchedule`
  - [ ] `deleteSchedule`
  - [ ] `pauseSchedule`
  - [ ] `resumeSchedule`
- [ ] F1.10 Adicionar API de saude minima do servidor:
  - [ ] `getServerHealth`
  - [ ] incluir status de socket, autenticacao e disponibilidade do banco configurado

DoD Fase 1:

- [ ] Cliente consegue configurar bases no servidor e testar conexao sem acesso direto ao ambiente servidor.
- [ ] Cliente consegue disparar e controlar execucao remota de backup via comando.
- [ ] Endpoints novos reutilizam servicos/repositorios existentes (sem duplicacao de regra de dominio em handlers).
- [ ] Regras de licenca e validacao de dominio sao aplicadas no servidor para todos endpoints remotos.
- [ ] Alteracoes invalidas nao sao persistidas e retornam erro padronizado com `statusCode`.
- [ ] Cliente consegue consultar preflight do servidor e recebe bloqueio claro quando compactacao nao estiver disponivel.

---

## Fase 2 - Execucao 100% no Servidor (P0)

Objetivo: garantir pipeline completo de execucao no servidor com configuracao originada no cliente e politica de concorrencia/fila.

- [ ] F2.1 Definir contrato remoto de opcoes de backup e compactacao por agendamento.
- [x] F2.2 Garantir aplicacao no servidor de: dump, compactacao, checksum, politicas de limpeza e post-script conforme permitido.
- [x] F2.3 Publicar progresso detalhado por etapa para cliente (iniciando, dump, compactacao, verificacao, finalizando). _(`backupStep` implementado)_
- [~] F2.4 Registrar historico e logs no servidor com correlacao (`runId`, `scheduleId`, `clientId`). _(`scheduleId` rastreado; `runId` e `clientId` nao formalizados no contrato de mensagens)_
- [ ] F2.5 Incluir idempotencia por `runId` para evitar duplicidade por retransmissao/reconexao.
- [ ] F2.6 Padronizar uso da pasta temporaria padrao do servidor para este fluxo remoto (sem parametro de pasta temp vindo do cliente).
- [ ] F2.7 Bloquear execucao remota quando prerequisitos de compactacao falharem no servidor.
- [x] F2.8 Garantir que execucao no servidor so inicia por comando explicito recebido do cliente.
- [ ] F2.9 Implementar mutex global de execucao de backup no servidor (`maxConcurrentBackups = 1`).
- [ ] F2.10 Implementar fila FIFO para execucoes agendadas quando houver backup ativo.
- [ ] F2.11 Retornar `409 BACKUP_ALREADY_RUNNING` para disparo manual durante execucao ativa.
- [ ] F2.12 Publicar eventos de fila (`backupQueued`, `backupDequeued`, `backupStarted`) com `runId`.
- [ ] F2.13 Definir e validar maquina de estados da execucao (`queued`, `running`, `completed`, `failed`, `cancelled`) no servidor.
- [ ] F2.14 Exigir `idempotencyKey` para comandos mutaveis (`startBackup`, `cancelBackup`, `createSchedule`) com deduplicacao por janela.
- [ ] F2.15 Definir limites operacionais da fila:
  - [ ] `maxQueueSize`
  - [ ] TTL de item enfileirado
  - [ ] regra para duplicidade de `scheduleId`
  - [ ] retorno padrao em overflow (`429`/`503`)
- [ ] F2.16 Persistir estado de execucao e fila para recuperacao apos reinicio do servidor.
- [ ] F2.17 Adicionar `eventId` e `sequence` em todos eventos de execucao/fila para reprocessamento seguro no cliente.
- [ ] F2.18 Garantir correlacao obrigatoria por `runId` em logs, eventos, diagnostico e metadados de artefato.

DoD Fase 2:

- [x] Backup remoto e executado somente no servidor.
- [ ] Artefato final no servidor corresponde exatamente a configuracao do agendamento remoto.
- [x] Cliente observa progresso confiavel ponta-a-ponta.
- [ ] Artefato entregue ao cliente ja esta pronto para continuidade do fluxo no cliente.
- [ ] Nao existe dependencia de configuracao de pasta temporaria do cliente no fluxo remoto.
- [ ] Falha de ferramenta de compactacao no servidor retorna erro bloqueante claro e rastreavel.
- [ ] Nunca existem 2 backups simultaneos no servidor.
- [ ] Disparos agendados concorrentes entram em fila e executam na ordem esperada.
- [ ] Disparo manual concorrente retorna erro padronizado e acionavel.
- [ ] Transicoes de estado invalidas sao bloqueadas e retornadas com erro padronizado.
- [ ] Reenvio/reconexao de comandos nao gera duplicidade de execucao (idempotencia efetiva).
- [ ] Servidor reinicia sem perder controle da fila/execucao em andamento.
- [ ] Cliente reconecta e consegue se ressincronizar por `sequence` e consultas de status/fila.

---

## Fase 3 - Entrega de Artefato ao Cliente (P0)

Objetivo: entregar arquivo pronto ao cliente com confiabilidade e retomada.

- [~] F3.1 Formalizar staging remoto por execucao (`runId`) com metadados de tamanho/hash/chunk. _(staging de arquivo implementado; sem correlacao por `runId`)_
- [x] F3.2 Garantir download resiliente com resume (`startChunk`) e validacao de integridade no cliente.
- [ ] F3.3 Definir ciclo de vida de staging (criar, expirar, limpar com seguranca).
- [ ] F3.4 Retornar `410` quando artefato solicitado estiver expirado/removido por politica de retencao.
- [ ] F3.5 Definir politicas de concorrencia para multiplos clientes consumindo mesmo artefato.
- [ ] F3.6 Testes de falha de rede e retomada sem corrupcao de arquivo.

DoD Fase 3:

- [x] Cliente sempre recebe arquivo pronto e validado.
- [x] Retomada de download funciona apos queda de conexao.
- [ ] Nao ha vazamento de arquivos temporarios no servidor.

---

## Fase 4 - Continuidade do Fluxo no Cliente (P1)

Objetivo: apos receber arquivo pronto, cliente segue fluxo local de envio para destino final.

- [ ] F4.1 Integrar download remoto com pipeline local de envio a destinos finais.
- [ ] F4.2 Preservar bloqueios/licenca por tipo de destino no cliente.
- [ ] F4.3 Melhorar UX de fila e status de transferencias (baixando, enviado, falha, retry).
- [ ] F4.4 Implementar retry/backoff no envio ao destino final.
- [ ] F4.5 Telemetria minima de sucesso/falha por etapa cliente->destino.

DoD Fase 4:

- [ ] Cliente conclui fluxo completo apos receber artefato do servidor.
- [ ] Falhas em destinos finais nao afetam integridade do artefato recebido.

---

## Fase 5 - Observabilidade e Operacao (P1)

Objetivo: operacao previsivel em producao.

- [ ] F5.1 Padronizar codigos de erro remotos e mapeamento para UI.
- [ ] F5.2 Definir metricas: auth denied, license denied, schedule create/update rejected, run duration, download duration, resume count.
- [ ] F5.3 Log estruturado com `runId`, `scheduleId`, `requestId`, `clientId`.
- [ ] F5.4 Checklist de rollout e rollback por fase.

DoD Fase 5:

- [ ] Equipe consegue diagnosticar falhas sem depuracao manual extensa.

---

## Priorizacao

- [ ] P0: Fase 0, Fase 1, Fase 2, Fase 3
- [ ] P1: Fase 4, Fase 5

## Roadmap Objetivo Final (P0/P1 com Criterios de Aceite)

### P0 - Essencial para atingir o objetivo final com seguranca

- [ ] P0.1 Congelar contrato remoto `v1` (envelope, tipos, erros, eventos).
      Criterio de aceite:
  - [ ] Documento de contrato `v1` fechado no repositorio.
  - [ ] Toda resposta segue `statusCode`, `success`, `data`, `error`.
- [ ] P0.2 Garantir conformidade de protocolo entre cliente e servidor.
      Criterio de aceite:
  - [ ] Testes de protocolo (golden/contract) cobrindo serializacao e parsing.
  - [ ] Sem divergencia de payload/tipos entre `protocol` e `connection_manager`.
- [ ] P0.3 Pipeline unico de comando no servidor (auth -> licenca -> validacao -> idempotencia -> execucao).
      Criterio de aceite:
  - [ ] Nenhum handler executa acao mutavel fora desse pipeline.
  - [ ] Falhas retornam erro padronizado com `errorCode` acionavel.
- [ ] P0.4 Implementar modelo de execucao robusto (`maxConcurrentBackups = 1`, fila, maquina de estados).
      Criterio de aceite:
  - [ ] Nunca existem 2 backups simultaneos.
  - [ ] Fila respeita ordem e regras de overflow/TTL.
  - [ ] Transicao invalida retorna `409 INVALID_STATE_TRANSITION`.
- [ ] P0.5 Implementar idempotencia forte para comandos mutaveis.
      Criterio de aceite:
  - [ ] `idempotencyKey` obrigatorio em `startBackup`, `cancelBackup`, `createSchedule`.
  - [ ] Reenvio nao cria execucao duplicada.
- [ ] P0.6 Persistir fila/estado para recuperacao apos restart.
      Criterio de aceite:
  - [ ] Reinicio do servidor preserva execucao/fila.
  - [ ] `runId` e status permanecem consistentes apos reboot.
- [ ] P0.7 Garantir artefato server-first com ciclo de vida formal.
      Criterio de aceite:
  - [ ] `getArtifactMetadata` retorna metadados completos (hash/tamanho/chunk/TTL).
  - [ ] Artefato expirado retorna `410 ARTIFACT_EXPIRED`.
  - [ ] `cleanupStaging` e remoto (sem chamada local no cliente).
- [ ] P0.8 Cobertura de resiliencia e concorrencia em integracao.
      Criterio de aceite:
  - [ ] Testes com 2 clientes concorrentes.
  - [ ] Testes de reconexao + replay de eventos com `sequence`.
  - [ ] Teste de recovery apos restart passando no CI.

### P1 - Estabilidade operacional e rollout controlado

- [ ] P1.1 Observabilidade ponta-a-ponta por `runId`.
      Criterio de aceite:
  - [ ] Logs estruturados com `runId`, `scheduleId`, `requestId`, `clientId`.
  - [ ] Metricas minimas publicadas (duracao, fila, falhas por `errorCode`).
- [ ] P1.2 Matriz de erro operacional para decisao automatica do cliente.
      Criterio de aceite:
  - [ ] Mapa `errorCode -> statusCode -> retryable -> acao cliente` publicado.
  - [ ] Cliente aplica retry/backoff apenas onde permitido.
- [ ] P1.3 Rollout por feature flag + playbook de rollback.
      Criterio de aceite:
  - [ ] Endpoints novos ativaveis gradualmente.
  - [ ] Procedimento de rollback testado em ambiente de homologacao.

Amarracao sugerida com PRs:

- [ ] PR-1: P0.1, P0.2 (base), P0.3 (fundacao do pipeline), P1.2 (matriz inicial de erro)
- [ ] PR-2: P0.3 (completo), P0.5, parte de P0.8
- [ ] PR-3: P0.4, P0.6, P0.7, P0.8 (completo)
- [ ] PR-4/PR-5: P1.1, P1.3 e refinamentos operacionais

## Sequencia de PRs Recomendada

- [ ] PR-1: Fase 0 (hardening + contrato base + status code) - proximo passo
- [ ] PR-2: Fase 1 (CRUD remoto de base + teste de conexao + API de execucao por comando)
- [ ] PR-3: Fase 2 (execucao completa no servidor + mutex + fila)
- [ ] PR-4: Fase 3 (entrega resiliente do artefato)
- [ ] PR-5: Fase 4 e Fase 5 (continuidade local + observabilidade)

## Quebra de Implementacao por PR (PR-1, PR-2, PR-3)

### PR-1 - Contrato base REST-like + hardening pre-auth (fundacao)

Escopo:

- [ ] Padronizar envelope de response/erro com `statusCode`, `success`, `data`, `error`.
- [ ] Implementar tabela `ErrorCode -> statusCode`.
- [ ] Fechar matriz `ErrorCode -> statusCode -> retryable -> acao esperada do cliente`.
- [ ] Bloquear processamento pre-auth para mensagens operacionais.
- [ ] Entregar `getServerCapabilities`, `getServerHealth`, `getSession`.
- [ ] Garantir parsing/serializacao do envelope no cliente.

Arquivos foco:

- [ ] Protocol:
  - [ ] `lib/infrastructure/protocol/message_types.dart`
  - [ ] `lib/infrastructure/protocol/message.dart`
  - [ ] `lib/infrastructure/protocol/error_codes.dart`
  - [ ] `lib/infrastructure/protocol/error_messages.dart`
  - [ ] `lib/infrastructure/protocol/auth_messages.dart`
- [ ] Server:
  - [ ] `lib/infrastructure/socket/server/client_handler.dart`
  - [ ] `lib/infrastructure/socket/server/tcp_socket_server.dart`
  - [ ] `lib/infrastructure/socket/server/server_authentication.dart`
  - [ ] novo `lib/infrastructure/socket/server/system_message_handler.dart`
  - [ ] novo `lib/infrastructure/socket/server/session_message_handler.dart`
- [ ] Client:
  - [ ] `lib/infrastructure/socket/client/connection_manager.dart`
  - [ ] `lib/infrastructure/socket/client/socket_client_service.dart`
  - [ ] `lib/infrastructure/socket/client/tcp_socket_client.dart`

Testes obrigatorios:

- [ ] `test/unit/infrastructure/protocol/message_test.dart` (envelope completo)
- [ ] novo `test/unit/infrastructure/protocol/error_messages_test.dart`
- [ ] `test/unit/infrastructure/socket/server/client_handler_test.dart` (rejeicao pre-auth)
- [ ] `test/integration/socket_integration_test.dart` (auth -> capabilities -> health)

Gate de saida:

- [ ] Nenhuma mensagem operacional passa sem auth.
- [ ] Todas as respostas retornam `statusCode`.
- [ ] Cliente recebe erro padronizado em falhas de contrato/auth.

Roteiro executavel (ordem sugerida):

1. Baseline local antes das alteracoes
   - [ ] Rodar analise e testes atuais para garantir ponto de partida estavel.
   - [ ] Comandos:
     - `flutter analyze`
     - `flutter test test/unit/infrastructure/protocol/message_test.dart`
     - `flutter test test/unit/infrastructure/socket/server/client_handler_test.dart`
2. Protocolo base (contrato REST-like)
   - [ ] Atualizar `message_types.dart` com mensagens de `capabilities`, `health` e `session`.
   - [ ] Atualizar `message.dart` para suportar envelope padrao (`statusCode`, `success`, `data`, `error`).
   - [ ] Atualizar `error_codes.dart` e `error_messages.dart` com mapa `ErrorCode -> statusCode`.
   - [ ] Atualizar `auth_messages.dart` para `getSession`/`whoAmI`.
   - [ ] Checkpoint:
     - `flutter test test/unit/infrastructure/protocol/message_test.dart`
3. Hardening de autenticacao no servidor
   - [ ] Em `client_handler.dart`, bloquear mensagens operacionais antes de auth.
   - [ ] Definir allowlist pre-auth: `authRequest`, `heartbeat`, `capabilitiesRequest` (se habilitado).
   - [ ] Em `tcp_socket_server.dart`, garantir roteamento para handlers novos e erro `400` para tipo invalido.
   - [ ] Enriquecer sessao em `server_authentication.dart`.
   - [ ] Checkpoint:
     - `flutter test test/unit/infrastructure/socket/server/client_handler_test.dart`
4. Handlers de sistema/sessao
   - [ ] Criar `system_message_handler.dart` com:
     - `getServerCapabilities`
     - `getServerHealth`
   - [ ] Criar `session_message_handler.dart` com:
     - `getSession`/`whoAmI`
   - [ ] Garantir que todos retornem envelope padrao e `statusCode`.
5. Ajustes no cliente socket
   - [ ] Em `connection_manager.dart`, expor:
     - `getServerCapabilities()`
     - `getServerHealth()`
     - `getSession()`
   - [ ] Em `socket_client_service.dart`, padronizar parser de erro por `statusCode` + `error.code`.
   - [ ] Em `tcp_socket_client.dart`, validar correlacao por `requestId`.
6. Testes do PR-1
   - [ ] Atualizar `test/unit/infrastructure/protocol/message_test.dart`.
   - [ ] Criar `test/unit/infrastructure/protocol/error_messages_test.dart`.
   - [ ] Atualizar `test/unit/infrastructure/socket/server/client_handler_test.dart`.
   - [ ] Atualizar `test/integration/socket_integration_test.dart` para fluxo:
     - auth -> capabilities -> health.
7. Validacao final do PR-1
   - [ ] Rodar validacao completa:
     - `flutter analyze`
     - `flutter test test/unit/infrastructure/protocol`
     - `flutter test test/unit/infrastructure/socket/server`
     - `flutter test test/integration/socket_integration_test.dart`
   - [ ] Confirmar gates de saida do PR-1.

Sequencia de commits sugerida:

1. `protocol: add response envelope and status code mapping`
2. `server: enforce pre-auth guard and route system/session handlers`
3. `client: add capabilities/health/session APIs in connection manager`
4. `test: cover envelope, pre-auth rejection and socket integration flow`

### PR-2 - Recursos operacionais de cliente->servidor (CRUD + preflight + status)

Escopo:

- [ ] Incorporar implementacoes existentes do servidor sem reescrever regra de negocio.
- [ ] CRUD remoto de configuracao de banco.
- [ ] Teste remoto de conexao de banco (`testDatabaseConnection`).
- [ ] Preflight de servidor (`validateServerBackupPrerequisites`).
- [ ] Definir contrato de idempotencia para comandos mutaveis:
  - [ ] campo `idempotencyKey` nos requests de comando
  - [ ] padrao de resposta para repeticao (mesmo resultado logico)
- [ ] API de execucao/status base:
  - [ ] `startBackup`
  - [ ] `cancelBackup`
  - [ ] `getExecutionStatus`
  - [ ] `getExecutionQueue` (consulta)
- [ ] Completar comandos de agendamento faltantes:
  - [ ] `createSchedule`, `deleteSchedule`, `pauseSchedule`, `resumeSchedule`
- [ ] Reaproveitamento obrigatorio de base atual:
  - [ ] repositorios de config: `i_sybase_config_repository.dart`, `i_sql_server_config_repository.dart`, `i_postgres_config_repository.dart`
  - [ ] servicos de teste: `sybase_backup_service.dart`, `sql_server_backup_service.dart`, `postgres_backup_service.dart`
  - [ ] preflight: `tool_verification_service.dart`, `validate_backup_directory.dart`, `storage_checker.dart`, `validate_sybase_log_backup_preflight.dart`
  - [ ] agendamento: `i_schedule_repository.dart`, `update_schedule.dart`, `scheduler_service.dart`

Arquivos foco:

- [ ] Protocol:
  - [ ] novo `lib/infrastructure/protocol/database_config_messages.dart`
  - [ ] novo `lib/infrastructure/protocol/execution_messages.dart`
  - [ ] novo `lib/infrastructure/protocol/system_messages.dart`
  - [ ] ajuste em `lib/infrastructure/protocol/schedule_messages.dart`
- [ ] Server:
  - [ ] novo `lib/infrastructure/socket/server/database_config_message_handler.dart`
  - [ ] novo `lib/infrastructure/socket/server/execution_message_handler.dart`
  - [ ] novo `lib/infrastructure/socket/server/system_message_handler.dart` (`getServerHealth`)
  - [ ] `lib/infrastructure/socket/server/schedule_message_handler.dart`
  - [ ] `lib/infrastructure/socket/server/metrics_message_handler.dart`
- [ ] Client:
  - [ ] `lib/infrastructure/socket/client/connection_manager.dart`
  - [ ] `lib/application/providers/remote_schedules_provider.dart`
  - [ ] `lib/application/providers/server_connection_provider.dart`
  - [ ] `lib/application/providers/license_provider.dart`

Testes obrigatorios:

- [ ] novo `test/unit/infrastructure/protocol/execution_messages_test.dart`
- [ ] novo `test/unit/infrastructure/protocol/system_messages_test.dart`
- [ ] `test/unit/infrastructure/socket/server/schedule_message_handler_test.dart` (`statusCode`)
- [ ] novo `test/unit/infrastructure/socket/server/system_message_handler_test.dart`
- [ ] novo `test/unit/infrastructure/socket/server/execution_message_handler_test.dart` (status base)

Gate de saida:

- [ ] Cliente consegue configurar base, testar conexao e consultar preflight remoto.
- [ ] Cliente consegue iniciar/cancelar/consultar execucao com contrato padronizado.
- [ ] Comandos remotos novos usam implementacoes existentes do servidor sem regressao funcional.
- [ ] Contrato de `idempotencyKey` fechado e coberto por teste de protocolo.
- [ ] Sem regressao no fluxo atual de schedule/list/download.

### PR-3 - Concorrencia, fila, diagnostico e artefato pronto (server-first)

Escopo:

- [ ] Incorporar diagnostico e staging a partir dos servicos ja existentes.
- [ ] Implementar `maxConcurrentBackups = 1`.
- [ ] Implementar fila FIFO para disparos agendados concorrentes.
- [ ] Implementar politica operacional de fila (`maxQueueSize`, TTL, overflow, duplicidade de `scheduleId`).
- [ ] Retornar `409 BACKUP_ALREADY_RUNNING` em disparo manual concorrente.
- [ ] Implementar `cancelQueuedBackup`.
- [ ] Publicar eventos de fila:
  - [ ] `backupQueued`
  - [ ] `backupDequeued`
  - [ ] `backupStarted`
- [ ] Incluir `eventId` e `sequence` nos eventos para consumo resiliente.
- [ ] Persistir estado/fila para recuperacao apos restart do servidor.
- [ ] Entregar diagnostico e suporte operacional:
  - [ ] `getRunLogs`
  - [ ] `getRunErrorDetails`
  - [ ] `getArtifactMetadata`
  - [ ] `cleanupStaging` remoto
- [ ] Integrar consumo no cliente:
  - [ ] status/posicao de fila em tempo real
  - [ ] validacao de hash apos download
  - [ ] remover chamada local de cleanup no cliente e migrar para endpoint remoto

Arquivos foco:

- [ ] Protocol:
  - [ ] `lib/infrastructure/protocol/execution_messages.dart`
  - [ ] `lib/infrastructure/protocol/file_transfer_messages.dart`
  - [ ] novo `lib/infrastructure/protocol/diagnostics_messages.dart`
- [ ] Server:
  - [ ] `lib/infrastructure/socket/server/execution_message_handler.dart`
  - [ ] `lib/infrastructure/socket/server/file_transfer_message_handler.dart`
  - [ ] novo `lib/infrastructure/socket/server/diagnostics_message_handler.dart`
  - [ ] `lib/infrastructure/transfer_staging_service.dart` (reuso no endpoint remoto de metadata/cleanup)
  - [ ] `lib/infrastructure/repositories/backup_log_repository.dart`
  - [ ] `lib/application/services/log_service.dart`
- [ ] Client:
  - [ ] `lib/infrastructure/socket/client/connection_manager.dart`
  - [ ] `lib/application/providers/backup_progress_provider.dart`
  - [ ] `lib/application/providers/remote_file_transfer_provider.dart`
  - [ ] `lib/application/providers/remote_schedules_provider.dart`

Testes obrigatorios:

- [ ] `test/unit/infrastructure/socket/server/execution_message_handler_test.dart` (concorrencia/fila/cancelamento)
- [ ] novo `test/unit/infrastructure/socket/server/diagnostics_message_handler_test.dart`
- [ ] `test/integration/socket_integration_test.dart` (status/fila/eventos)
- [ ] `test/integration/file_transfer_integration_test.dart` (`getArtifactMetadata` + hash)
- [ ] novo `test/integration/backup_queue_integration_test.dart` (2 clientes concorrentes)
- [ ] novo `test/integration/server_restart_recovery_test.dart` (restaura fila/estado apos restart)
- [ ] cobertura de idempotencia e deduplicacao de comando por `idempotencyKey`
- [ ] cobertura de eventos com ordenacao por `sequence`

Gate de saida:

- [ ] Nunca ha 2 backups simultaneos no servidor.
- [ ] Agendados concorrentes entram em fila e executam em ordem.
- [ ] Cliente enxerga fila/status/eventos de forma consistente.
- [ ] Cliente recebe artefato pronto com metadados confiaveis.
- [ ] Limpeza de staging e sempre orquestrada remotamente pelo servidor.
- [ ] Reinicio do servidor nao perde fila nem estado de execucao.
- [ ] Duplicidade de comando nao dispara backup duplicado.

## Checklist Tecnico de Implementacao por Arquivo (Server, Protocol, Client + Testes)

### Protocol (`lib/infrastructure/protocol`)

- [ ] `message_types.dart`
  - [ ] Adicionar tipos de mensagem:
    - `getServerHealthRequest/Response`
    - `getSessionRequest/Response`
    - `getServerCapabilitiesRequest/Response`
    - `validateServerBackupPrerequisitesRequest/Response`
    - `getExecutionStatusRequest/Response`
    - `getExecutionQueueRequest/Response`
    - `cancelQueuedBackupRequest/Response`
    - `getArtifactMetadataRequest/Response`
    - `getRunLogsRequest/Response`
    - `getRunErrorDetailsRequest/Response`
    - `pauseScheduleRequest/Response`
    - `resumeScheduleRequest/Response`
    - `backupQueued`, `backupDequeued`, `backupStarted`
- [ ] `message.dart`
  - [ ] Garantir serializacao/deserializacao do envelope padrao:
    - `requestId`, `statusCode`, `success`, `data`, `error`
  - [ ] Garantir validacao de campos obrigatorios para request/response
  - [ ] Incluir suporte a `idempotencyKey` para requests mutaveis
  - [ ] Incluir suporte a `eventId` e `sequence` para eventos
- [ ] `error_codes.dart`
  - [ ] Adicionar codigos de erro obrigatorios:
    - `BACKUP_ALREADY_RUNNING`
    - `QUEUED_BACKUP_NOT_FOUND`
    - `BACKUP_NOT_RUNNING`
    - `PRECONDITION_FAILED`
    - `FEATURE_NOT_AVAILABLE`
    - `DB_CONNECTION_TEST_FAILED`
    - `UNSUPPORTED_DATABASE_TYPE`
    - `INVALID_STATE_TRANSITION`
    - `ARTIFACT_EXPIRED`
    - `QUEUE_OVERFLOW`
- [ ] `database_config_messages.dart` (novo)
  - [ ] Requests/responses de CRUD de configuracao de banco com envelope padrao
  - [ ] Suportar discriminador por tipo de banco (`sybase|sqlserver|postgres`)
- [ ] `execution_messages.dart` (novo)
  - [ ] Requests/responses para `startBackup`, `cancelBackup`, `getExecutionStatus`, `getExecutionQueue`, `cancelQueuedBackup`
  - [ ] Eventos `backupQueued`, `backupDequeued`, `backupStarted`
  - [ ] `getExecutionStatus` deve retornar estado formal + `queuedPosition` + `runId`
  - [ ] Eventos devem carregar `eventId`, `sequence`, `runId`, `occurredAt`
- [ ] `system_messages.dart` (novo)
  - [ ] Requests/responses para `getServerHealth`, `validateServerBackupPrerequisites`, `capabilities`
- [ ] `diagnostics_messages.dart` (novo)
  - [ ] Requests/responses para `getRunLogs`, `getRunErrorDetails`, `getArtifactMetadata`, `cleanupStaging`

### Server (`lib/infrastructure/socket/server`)

- [ ] `database_config_message_handler.dart` (novo)
  - [ ] Reusar repositorios existentes de config (`sybase/sqlserver/postgres`)
  - [ ] Nao implementar regra de negocio no handler; apenas parse/validacao de contrato + delegacao
- [ ] `execution_message_handler.dart` (novo)
  - [ ] Reusar `SchedulerService.executeNow/cancelExecution`
  - [ ] Expor `getExecutionStatus/getExecutionQueue` com `runId/state/queuedPosition`
  - [ ] Aplicar regra: manual concorrente retorna `409 BACKUP_ALREADY_RUNNING`
  - [ ] Enforcar maquina de estados e bloquear transicoes invalidas
  - [ ] Implementar deduplicacao por `idempotencyKey`
  - [ ] Enforcar politica de fila (`maxQueueSize`, TTL, duplicidade de `scheduleId`)
- [ ] `schedule_message_handler.dart`
  - [ ] Completar `create/delete/pause/resume`
  - [ ] Migrar erros para `createErrorMessage` com `statusCode/errorCode`
- [ ] `system_message_handler.dart` (novo)
  - [ ] `getServerHealth`
  - [ ] `validateServerBackupPrerequisites` usando `ToolVerificationService`, `StorageChecker`, `validate_backup_directory`, `validate_sybase_log_backup_preflight`
- [ ] `diagnostics_message_handler.dart` (novo)
  - [ ] Reusar `IBackupHistoryRepository`, `BackupLogRepository.getByBackupHistory`, `LogService.getLogs`
  - [ ] Expor `getRunLogs/getRunErrorDetails/getArtifactMetadata/cleanupStaging`
- [ ] `file_transfer_message_handler.dart`
  - [ ] Retornar `410` + `ARTIFACT_EXPIRED` para artefato fora da retencao
- [ ] `tcp_socket_server.dart`
  - [ ] Registrar roteamento dos novos handlers mantendo guard de autenticacao
  - [ ] Garantir recuperacao de estado/fila apos restart (bootstrap de runtime)

### Client (`lib/infrastructure/socket/client` + providers)

- [ ] `connection_manager.dart`
  - [ ] Adicionar APIs: `getServerHealth`, `validateServerBackupPrerequisites`, CRUD de DB config, `testDatabaseConnection`, `getExecutionStatus`, `getExecutionQueue`, `cancelQueuedBackup`, `getRunLogs`, `getRunErrorDetails`, `getArtifactMetadata`, `cleanupStaging`
  - [ ] Garantir parse de envelope padrao (`statusCode/success/data/error`)
  - [ ] Gerar e enviar `idempotencyKey` para comandos mutaveis
  - [ ] Reprocessar eventos por `sequence` e descartar duplicados por `eventId`
- [ ] `remote_schedules_provider.dart`
  - [ ] Consumir comandos novos de agendamento (`create/delete/pause/resume`)
- [ ] `server_connection_provider.dart`
  - [ ] Integrar health/preflight no fluxo de conexao
- [ ] `remote_file_transfer_provider.dart`
  - [ ] Remover chamada local `_transferStagingService.cleanupStaging(scheduleId)`
  - [ ] Chamar endpoint remoto `cleanupStaging` apos transferencia concluida

### Testes (`test/unit` + `test/integration`)

- [ ] Protocol:
  - [ ] `execution_messages_test.dart` (novo)
  - [ ] `system_messages_test.dart` (novo)
  - [ ] `diagnostics_messages_test.dart` (novo)
  - [ ] validar `idempotencyKey`, `eventId`, `sequence` no contrato
- [ ] Server unit:
  - [ ] `schedule_message_handler_test.dart` (erros padronizados + comandos faltantes)
  - [ ] `execution_message_handler_test.dart` (mutex, fila, 409 manual concorrente)
  - [ ] `system_message_handler_test.dart` (health + preflight)
  - [ ] `diagnostics_message_handler_test.dart` (logs/metadata/cleanup)
  - [ ] validar bloqueio de transicao invalida e deduplicacao por `idempotencyKey`
- [ ] Client unit:
  - [ ] `connection_manager_test.dart` (novos endpoints + envelope)
  - [ ] `remote_file_transfer_provider_test.dart` (cleanup remoto)
  - [ ] validar ordenacao/deduplicacao de eventos por `sequence/eventId`
- [ ] Integracao:
  - [ ] `socket_integration_test.dart` (fluxo completo de CRUD config + execucao + status)
  - [ ] `backup_queue_integration_test.dart` (2 clientes concorrentes)
  - [ ] `file_transfer_integration_test.dart` (`getArtifactMetadata` + hash + cleanup remoto)
  - [ ] `server_restart_recovery_test.dart` (recuperacao de fila/estado)
  - [ ] fluxo de artefato expirado com retorno `410`

## Checklist de Qualidade por PR

- [ ] Compila e analisa sem erros novos.
- [ ] Testes unitarios/integracao cobrindo fluxos alterados.
- [ ] Sem bypass de auth/licenca no caminho remoto.
- [ ] Contrato de erro estavel e documentado no codigo do protocolo.
- [ ] Todas as respostas remotas retornam `statusCode` e envelope padrao.
- [ ] Matriz `errorCode -> statusCode -> retryable -> acao cliente` publicada e coberta por teste.
- [ ] Regras de concorrencia/fila testadas (1 execucao ativa + enfileiramento de agendados).
- [ ] Maquina de estados de execucao validada em testes (incluindo transicao invalida).
- [ ] Idempotencia validada para comandos mutaveis (sem duplicidade de execucao).
- [ ] Eventos possuem `eventId/sequence` e cliente re-sincroniza corretamente apos reconexao.
- [ ] Reinicio de servidor preserva estado de fila/execucao.
- [ ] Politica de retencao de artefato validada (inclui retorno `410` para expirado).
- [ ] Endpoints de processos server-only cobertos na API remota para consumo do cliente.
- [ ] Sem regressao funcional no fluxo atual cliente->servidor.
