# Plano: Cliente Consumindo Recursos do Servidor (Backup Remoto Orquestrado)

Data base: 2026-02-21  
Atualizado em: 2026-02-27  
Status: Em andamento — infraestrutura base implementada; API de recursos remotos pendente  
Escopo: cliente Flutter desktop + servidor Flutter desktop (socket TCP)

## Estado de Implementação (2026-02-27)

### Infraestrutura base (implementada)

- Protocolo binário TCP: header 16 bytes, payload JSON, compressão GZIP, checksum CRC32
- Auth: `authRequest` / `authResponse` / `authChallenge` com validação de licença no servidor
- Agendamentos: `listSchedules`, `updateSchedule`, `executeSchedule`, `cancelSchedule` + respostas
- Progresso de backup: `backupProgress`, `backupStep`, `backupComplete`, `backupFailed`
- Transferência de arquivo: chunked, resume (`startChunk`), path validation, lock, checksum
- Métricas: `metricsRequest` / `metricsResponse`
- Sistema: `heartbeat`, `disconnect`, `error`
- `ErrorCode` enum + `createErrorMessage` com `errorCode` + `errorMessage`
- Reconexão com backoff exponencial no cliente

### Lacunas identificadas (bloqueiam P0)

- `client_handler.dart` encaminha mensagens para handlers sem verificar `isAuthenticated` — bypass pré-auth possível
- `createScheduleErrorMessage` omite `errorCode` no payload — erro de schedule não segue contrato padronizado
- Sem `capabilitiesRequest` / `capabilitiesResponse` no protocolo
- Sem CRUD remoto de configuração de banco (`createDatabaseConfig`, etc.)
- Sem `testDatabaseConnection` remoto
- Sem `getExecutionStatus` para polling de execução em curso
- Sem `validateServerBackupPrerequisites` (preflight de compactação/pasta temp)
- Sem idempotência por `runId`

---

## Objetivo

- [ ] Permitir que o cliente configure bases de dados no servidor e execute testes de conexao pelo servidor.
- [ ] Garantir que o agendamento seja controlado pelo cliente.
- [ ] Garantir que o destino final seja controlado pelo cliente.
- [ ] Garantir que todo fluxo de backup (dump, compactacao, validacao e artefato final) ocorra no servidor.
- [ ] Garantir que compressao, checksum e demais opcoes sejam aplicadas no servidor conforme configuracao enviada pelo cliente.
- [ ] Entregar ao cliente o arquivo final pronto para continuar o fluxo de distribuicao aos destinos finais.

## Resultado Esperado (Fluxo To-Be)

- [~] Cliente autentica no servidor com licenca valida para controle remoto. _(auth implementado; bloqueio pré-auth tem gap — ver F0.1)_
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
- [ ] API remota deve ser versionada e com contrato de erro padronizado. _(ErrorCode existe; versionamento de API ausente; contrato inconsistente em schedule errors)_
- [x] No fluxo remoto, nao havera configuracao manual de pasta temporaria no cliente.
- [ ] No fluxo remoto, o servidor usara pasta temporaria padrao do sistema operacional para staging de execucao/compactacao.
- [ ] Execucao remota deve validar disponibilidade de ferramenta de compactacao no servidor antes de iniciar backup.

## Responsabilidade de Execucao (Servidor x Cliente)

- [x] Somente servidor executa: teste de conexao de banco, dump, compressao, checksum, scripts, limpeza e preparacao de artefato final.
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
- [x] Execucao e progresso:
  - [x] `backupProgress`, `backupComplete`, `backupFailed`
- [x] Artefato final:
  - [x] `listFiles`, `fileTransferStart`, `fileChunk`, `fileTransferProgress`, `fileTransferComplete`
- [~] Erros:
  - [x] `error` com `errorCode`, `errorMessage`, `requestId` — estrutura existe em `createErrorMessage`
  - [ ] `createScheduleErrorMessage` nao inclui `errorCode` — contrato inconsistente

---

## Fase 0 - Hardening de Base Remota (P0)

Objetivo: fechar lacunas de seguranca e contrato antes de expandir API.

- [ ] F0.1 Bloquear processamento de mensagens nao-auth quando conexao ainda nao autenticada.
  Situacao: `client_handler.dart` encaminha toda mensagem para `_messageController` sem verificar `isAuthenticated`. Handlers (`ScheduleMessageHandler`, etc.) nao fazem essa verificacao.
  Arquivos:
  - `lib/infrastructure/socket/server/client_handler.dart` — adicionar guard em `_tryParseMessages`
  - `lib/infrastructure/socket/server/tcp_socket_server.dart` — verificar se handler checa auth antes de rotear
- [ ] F0.2 Padronizar erro remoto com `errorCode` + `errorMessage` para todos handlers.
  Situacao: `createErrorMessage` ja suporta `errorCode`; `createScheduleErrorMessage` nao inclui `errorCode`.
  Arquivos:
  - `lib/infrastructure/protocol/schedule_messages.dart` — adicionar `errorCode` em `createScheduleErrorMessage`
  - `lib/infrastructure/socket/server/schedule_message_handler.dart` — passar `ErrorCode` apropriado
  - `lib/infrastructure/socket/server/metrics_message_handler.dart` — verificar e padronizar
- [ ] F0.3 Adicionar endpoint de capacidades (`capabilities`) e versao de API remota.
  Arquivos candidatos:
  - `lib/infrastructure/protocol/message_types.dart` — adicionar `capabilitiesRequest`, `capabilitiesResponse`
  - `lib/infrastructure/socket/server/*_message_handler.dart` — novo `CapabilitiesMessageHandler`
  - `lib/infrastructure/socket/client/connection_manager.dart` — expor `getServerCapabilities()`
- [ ] F0.4 Criar testes de seguranca do handshake e rejeicao pre-auth.

DoD Fase 0:

- [ ] Nenhuma mensagem operacional e aceita antes de auth bem-sucedida.
- [ ] Cliente recebe motivo de erro consistente e acionavel (errorCode + errorMessage) em todos os handlers.
- [ ] Cliente consegue descobrir capacidades/versao do servidor antes de operar.

---

## Fase 1 - API Remota de Recursos do Servidor (P0)

Objetivo: expor na API remota tudo que e necessario para o cliente operar recursos que rodam no servidor.

- [ ] F1.1 Adicionar API remota de configuracao de banco (CRUD):
  - [ ] `createDatabaseConfig`
  - [ ] `updateDatabaseConfig`
  - [ ] `deleteDatabaseConfig`
  - [ ] `listDatabaseConfigs`
  - [ ] `getDatabaseConfigById`
  Arquivos novos:
  - `lib/infrastructure/protocol/database_config_messages.dart`
  - `lib/infrastructure/socket/server/database_config_message_handler.dart`
- [ ] F1.2 Adicionar API remota de teste de conexao de banco:
  - [ ] `testDatabaseConnection`
  - [ ] Validacao e execucao do teste no servidor
  - [ ] Retorno estruturado com motivo de sucesso/falha e `errorCode`
- [ ] F1.3 Adicionar API remota de execucao sob comando do cliente:
  - [x] `executeBackup` _(via `executeSchedule`)_
  - [x] `cancelBackup` _(via `cancelSchedule`)_
  - [ ] `getExecutionStatus` — polling de status de execucao em curso
- [ ] F1.4 Enforcar policy de licenca no servidor para configuracao de banco, teste de conexao e execucao.
  Situacao: licenca validada em auth e em `executeSchedule`; endpoints de DB config nao existem ainda.
- [ ] F1.5 Adaptar `ConnectionManager` e providers de cliente para consumir os novos endpoints.
- [ ] F1.6 Garantir persistencia no servidor de configuracao completa de backup remoto (compressao, checksum, script etc).
- [ ] F1.7 Testes unitarios + integracao para CRUD de banco, teste de conexao e execucao remota sob comando.
- [ ] F1.8 Adicionar API de preflight para validar prerequisitos de execucao no servidor:
  - [ ] `validateServerBackupPrerequisites`
  - [ ] checagem de ferramenta de compactacao
  - [ ] checagem de permissao/escrita na pasta temporaria padrao do servidor
  - [ ] retorno estruturado de bloqueios e avisos

DoD Fase 1:

- [ ] Cliente consegue configurar bases no servidor e testar conexao sem acesso direto ao ambiente servidor.
- [ ] Cliente consegue disparar e controlar execucao remota de backup via comando.
- [ ] Regras de licenca e validacao de dominio sao aplicadas no servidor para todos endpoints remotos.
- [ ] Alteracoes invalidas nao sao persistidas e retornam erro padronizado.
- [ ] Cliente consegue consultar preflight do servidor e recebe bloqueio claro quando compressao nao estiver disponivel.

---

## Fase 2 - Execucao 100% no Servidor (P0)

Objetivo: garantir pipeline completo de execucao no servidor com configuracao originada no cliente.

- [ ] F2.1 Definir contrato remoto de opcoes de backup e compressao por agendamento.
- [x] F2.2 Garantir aplicacao no servidor de: dump, compressao, checksum, politicas de limpeza e post-script conforme permitido.
- [x] F2.3 Publicar progresso detalhado por etapa para cliente (iniciando, dump, compressao, verificacao, finalizando). _(`backupStep` implementado)_
- [~] F2.4 Registrar historico e logs no servidor com correlacao (`runId`, `scheduleId`, `clientId`). _(`scheduleId` rastreado; `runId` e `clientId` nao formalizados no contrato de mensagens)_
- [ ] F2.5 Incluir idempotencia por `runId` para evitar duplicidade por retransmissao/reconexao.
- [ ] F2.6 Padronizar uso da pasta temporaria padrao do servidor para este fluxo remoto (sem parametro de pasta temp vindo do cliente).
- [ ] F2.7 Bloquear execucao remota quando prerequisitos de compactacao falharem no servidor.
- [x] F2.8 Garantir que execucao no servidor so inicia por comando explicito recebido do cliente.

DoD Fase 2:

- [x] Backup remoto e executado somente no servidor.
- [ ] Artefato final no servidor corresponde exatamente a configuracao do agendamento remoto.
- [x] Cliente observa progresso confiavel ponta-a-ponta.
- [ ] Artefato entregue ao cliente ja esta pronto para continuidade do fluxo no cliente.
- [ ] Nao existe dependencia de configuracao de pasta temporaria do cliente no fluxo remoto.
- [ ] Falha de ferramenta de compactacao no servidor retorna erro bloqueante claro e rastreavel.

---

## Fase 3 - Entrega de Artefato ao Cliente (P0)

Objetivo: entregar arquivo pronto ao cliente com confiabilidade e retomada.

- [~] F3.1 Formalizar staging remoto por execucao (`runId`) com metadados de tamanho/hash/chunk. _(staging de arquivo implementado; sem correlacao por `runId`)_
- [x] F3.2 Garantir download resiliente com resume (`startChunk`) e validacao de integridade no cliente.
- [ ] F3.3 Definir ciclo de vida de staging (criar, expirar, limpar com seguranca).
- [ ] F3.4 Definir politicas de concorrencia para multiplos clientes consumindo mesmo artefato.
- [ ] F3.5 Testes de falha de rede e retomada sem corrupcao de arquivo.

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

## Sequencia de PRs Recomendada

- [ ] PR-1: Fase 0 (hardening + contrato base) — **proximo passo**
- [ ] PR-2: Fase 1 (CRUD remoto de base + teste de conexao + API de execucao por comando)
- [ ] PR-3: Fase 2 (execucao completa no servidor)
- [ ] PR-4: Fase 3 (entrega resiliente do artefato)
- [ ] PR-5: Fase 4 e Fase 5 (continuidade local + observabilidade)

## Checklist de Qualidade por PR

- [ ] Compila e analisa sem erros novos.
- [ ] Testes unitarios/integracao cobrindo fluxos alterados.
- [ ] Sem bypass de auth/licenca no caminho remoto.
- [ ] Contrato de erro estavel e documentado no codigo do protocolo.
- [ ] Endpoints de processos server-only cobertos na API remota para consumo do cliente.
- [ ] Sem regressao funcional no fluxo atual cliente->servidor.
