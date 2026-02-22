# Plano: Cliente Consumindo Recursos do Servidor (Backup Remoto Orquestrado)

Data base: 2026-02-21  
Status: Em planejamento  
Escopo: cliente Flutter desktop + servidor Flutter desktop (socket TCP)

## Objetivo

- [ ] Permitir que o cliente configure bases de dados no servidor e execute testes de conexao pelo servidor.
- [ ] Garantir que o agendamento seja controlado pelo cliente.
- [ ] Garantir que o destino final seja controlado pelo cliente.
- [ ] Garantir que todo fluxo de backup (dump, compactacao, validacao e artefato final) ocorra no servidor.
- [ ] Garantir que compressao, checksum e demais opcoes sejam aplicadas no servidor conforme configuracao enviada pelo cliente.
- [ ] Entregar ao cliente o arquivo final pronto para continuar o fluxo de distribuicao aos destinos finais.

## Resultado Esperado (Fluxo To-Be)

- [ ] Cliente autentica no servidor com licenca valida para controle remoto.
- [ ] Cliente cria/edita/remove configuracoes de banco de dados no servidor.
- [ ] Cliente executa teste de conexao de banco remotamente, com validacao feita no servidor.
- [ ] Cliente controla agenda de execucao e envia comando de backup para o servidor no momento devido.
- [ ] Servidor executa backup (dump + compressao + verificacoes) somente quando recebe comando do cliente.
- [ ] Servidor salva artefato em pasta temporaria padrao do servidor.
- [ ] Servidor publica progresso em tempo real para cliente.
- [ ] Servidor disponibiliza arquivo final em staging remoto para download resiliente.
- [ ] Cliente baixa arquivo pronto e continua seu fluxo local de envio para destinos finais.

## Premissas de Projeto

- [ ] Fonte de verdade do agendamento sera o cliente.
- [ ] Cliente nao executa dump de banco; somente orquestra e consome artefato final.
- [ ] Controle de licenca remota deve ser fail-closed.
- [ ] API remota deve ser versionada e com contrato de erro padronizado.
- [ ] No fluxo remoto, nao havera configuracao manual de pasta temporaria no cliente.
- [ ] No fluxo remoto, o servidor usara pasta temporaria padrao do sistema operacional para staging de execucao/compactacao.
- [ ] Execucao remota deve validar disponibilidade de ferramenta de compactacao no servidor antes de iniciar backup.

## Responsabilidade de Execucao (Servidor x Cliente)

- [ ] Somente servidor executa: teste de conexao de banco, dump, compressao, checksum, scripts, limpeza e preparacao de artefato final.
- [ ] Cliente executa: controle de agenda, comando de execucao remota, UX, download do artefato pronto e envio para destino final.
- [ ] Qualquer processo dependente de ambiente/ferramenta do servidor deve estar exposto em API remota para o cliente.
- [ ] Pasta temporaria no fluxo remoto e responsabilidade exclusiva do servidor (padrao do SO, sem dependencia de configuracao no cliente).

## Contrato Minimo da API Remota (Cliente -> Servidor)

- [ ] Auth e sessao:
  - `authRequest`, `authResponse`
  - `capabilitiesRequest`, `capabilitiesResponse`
- [ ] Configuracao de banco:
  - `createDatabaseConfig`, `updateDatabaseConfig`, `deleteDatabaseConfig`
  - `listDatabaseConfigs`, `getDatabaseConfigById`
  - `testDatabaseConnection`
- [ ] Execucao remota sob comando do cliente:
  - `executeBackup`
  - `cancelBackup`
  - `getExecutionStatus`
- [ ] Execucao e progresso:
  - `backupProgress`, `backupComplete`, `backupFailed`
- [ ] Artefato final:
  - `listFiles`, `fileTransferStart`, `fileChunk`, `fileTransferProgress`, `fileTransferComplete`
- [ ] Erros:
  - `error` com `errorCode`, `errorMessage`, `requestId`

## Fase 0 - Hardening de Base Remota (P0)

Objetivo: fechar lacunas de seguranca e contrato antes de expandir API.

- [ ] F0.1 Bloquear processamento de mensagens nao-auth quando conexao ainda nao autenticada.
  Arquivos candidatos:
  - `lib/infrastructure/socket/server/client_handler.dart`
  - `lib/infrastructure/socket/server/tcp_socket_server.dart`
- [ ] F0.2 Padronizar erro remoto com `errorCode` + `errorMessage` para todos handlers.
  Arquivos candidatos:
  - `lib/infrastructure/protocol/schedule_messages.dart`
  - `lib/infrastructure/protocol/file_transfer_messages.dart`
  - `lib/infrastructure/protocol/metrics_messages.dart`
- [ ] F0.3 Adicionar endpoint de capacidades (`capabilities`) e versao de API remota.
  Arquivos candidatos:
  - `lib/infrastructure/protocol/message_types.dart`
  - `lib/infrastructure/socket/server/*_message_handler.dart`
  - `lib/infrastructure/socket/client/connection_manager.dart`
- [ ] F0.4 Criar testes de seguranca do handshake e rejeicao pre-auth.

DoD Fase 0:

- [ ] Nenhuma mensagem operacional e aceita antes de auth bem-sucedida.
- [ ] Cliente recebe motivo de erro consistente e acionavel.
- [ ] Cliente consegue descobrir capacidades/versao do servidor antes de operar.

## Fase 1 - API Remota de Recursos do Servidor (P0)

Objetivo: expor na API remota tudo que e necessario para o cliente operar recursos que rodam no servidor.

- [ ] F1.1 Adicionar API remota de configuracao de banco (CRUD):
  - `createDatabaseConfig`
  - `updateDatabaseConfig`
  - `deleteDatabaseConfig`
  - `listDatabaseConfigs`
  - `getDatabaseConfigById`
- [ ] F1.2 Adicionar API remota de teste de conexao de banco:
  - `testDatabaseConnection`
  - Validacao e execucao do teste no servidor
  - Retorno estruturado com motivo de sucesso/falha
- [ ] F1.3 Adicionar API remota de execucao sob comando do cliente:
  - `executeBackup`
  - `cancelBackup`
  - `getExecutionStatus`
- [ ] F1.4 Enforcar policy de licenca no servidor para configuracao de banco, teste de conexao e execucao.
- [ ] F1.5 Adaptar `ConnectionManager` e providers de cliente para consumir os novos endpoints.
- [ ] F1.6 Garantir persistencia no servidor de configuracao completa de backup remoto (compressao, checksum, script etc).
- [ ] F1.7 Testes unitarios + integracao para CRUD de banco, teste de conexao e execucao remota sob comando.
- [ ] F1.8 Adicionar API de preflight para validar prerequisitos de execucao no servidor:
  - `validateServerBackupPrerequisites`
  - checagem de ferramenta de compactacao
  - checagem de permissao/escrita na pasta temporaria padrao do servidor
  - retorno estruturado de bloqueios e avisos

DoD Fase 1:

- [ ] Cliente consegue configurar bases no servidor e testar conexao sem acesso direto ao ambiente servidor.
- [ ] Cliente consegue disparar e controlar execucao remota de backup via comando.
- [ ] Regras de licenca e validacao de dominio sao aplicadas no servidor para todos endpoints remotos.
- [ ] Alteracoes invalidas nao sao persistidas e retornam erro padronizado.
- [ ] Cliente consegue consultar preflight do servidor e recebe bloqueio claro quando compressao nao estiver disponivel.

## Fase 2 - Execucao 100% no Servidor (P0)

Objetivo: garantir pipeline completo de execucao no servidor com configuracao originada no cliente.

- [ ] F2.1 Definir contrato remoto de opcoes de backup e compressao por agendamento.
- [ ] F2.2 Garantir aplicacao no servidor de: dump, compressao, checksum, politicas de limpeza e post-script conforme permitido.
- [ ] F2.3 Publicar progresso detalhado por etapa para cliente (iniciando, dump, compressao, verificacao, finalizando).
- [ ] F2.4 Registrar historico e logs no servidor com correlacao (`runId`, `scheduleId`, `clientId`).
- [ ] F2.5 Incluir idempotencia por `runId` para evitar duplicidade por retransmissao/reconexao.
- [ ] F2.6 Padronizar uso da pasta temporaria padrao do servidor para este fluxo remoto (sem parametro de pasta temp vindo do cliente).
- [ ] F2.7 Bloquear execucao remota quando prerequisitos de compactacao falharem no servidor.
- [ ] F2.8 Garantir que execucao no servidor so inicia por comando explicito recebido do cliente.

DoD Fase 2:

- [ ] Backup remoto e executado somente no servidor.
- [ ] Artefato final no servidor corresponde exatamente a configuracao do agendamento remoto.
- [ ] Cliente observa progresso confiavel ponta-a-ponta.
- [ ] Artefato entregue ao cliente ja esta pronto para continuidade do fluxo no cliente.
- [ ] Nao existe dependencia de configuracao de pasta temporaria do cliente no fluxo remoto.
- [ ] Falha de ferramenta de compactacao no servidor retorna erro bloqueante claro e rastreavel.

## Fase 3 - Entrega de Artefato ao Cliente (P0)

Objetivo: entregar arquivo pronto ao cliente com confiabilidade e retomada.

- [ ] F3.1 Formalizar staging remoto por execucao (`runId`) com metadados de tamanho/hash/chunk.
- [ ] F3.2 Garantir download resiliente com resume (`startChunk`) e validacao de integridade no cliente.
- [ ] F3.3 Definir ciclo de vida de staging (criar, expirar, limpar com seguranca).
- [ ] F3.4 Definir politicas de concorrencia para multiplos clientes consumindo mesmo artefato.
- [ ] F3.5 Testes de falha de rede e retomada sem corrupcao de arquivo.

DoD Fase 3:

- [ ] Cliente sempre recebe arquivo pronto e validado.
- [ ] Retomada de download funciona apos queda de conexao.
- [ ] Nao ha vazamento de arquivos temporarios no servidor.

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

## Fase 5 - Observabilidade e Operacao (P1)

Objetivo: operacao previsivel em producao.

- [ ] F5.1 Padronizar codigos de erro remotos e mapeamento para UI.
- [ ] F5.2 Definir metricas: auth denied, license denied, schedule create/update rejected, run duration, download duration, resume count.
- [ ] F5.3 Log estruturado com `runId`, `scheduleId`, `requestId`, `clientId`.
- [ ] F5.4 Checklist de rollout e rollback por fase.

DoD Fase 5:

- [ ] Equipe consegue diagnosticar falhas sem depuracao manual extensa.

## Priorizacao

- [ ] P0: Fase 0, Fase 1, Fase 2, Fase 3
- [ ] P1: Fase 4, Fase 5

## Sequencia de PRs Recomendada

- [ ] PR-1: Fase 0 (hardening + contrato base)
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
