# Contexto Atual - Continuidade do Desenvolvimento

> **Última Atualização**: 01/02/2026
> **Branch**: `feature/client-server-architecture` > **Status**: FASE 0 (85% – plano + teste auto ✅; testes manuais pendentes), FASE 1 (26/31), **FASE 2.1–2.4 ✅**, **FASE 3 ✅**, **FASE 4 ✅**, **FASE 5.1–5.3 ✅** (pasta padrão, destinos remotos, vinculação agendamento↔destino), **FASE 6 ✅** (Dashboard métricas), **FASE 7 ✅** (AppMode, instalador atalhos)

## 🚀 Para Outra IA: Como Continuar Este Projeto

### 1. Leia Primeiro (Ordem Importante)

1. **Este arquivo** (README_CONTEXT_ATUAL.md) - 5 min

   - Contexto imediato do estado atual
   - O que já foi feito
   - Próximos passos

2. **plano_cliente_servidor.md** - 15 min

   - Arquitetura completa do sistema
   - Decisões técnicas (TCP Socket, protocolo binário)
   - Diagramas e especificações

3. **analise_tecnica_ui_banco_pacotes.md** - 10 min

   - Análise de componentes existentes (reutilizar!)
   - Database schema (já implementado v14)
   - Pacotes necessários (qr_flutter já adicionado)

4. **implementacao_cliente_servidor.md** - 20 min
   - Checklist detalhado de TODAS as tarefas
   - FASE 0: 11/13 completados (banco de dados pronto)
   - FASE 1: Em andamento (26/31 tarefas)
   - FASE 2: 2.1–2.4 completados (credenciais, conexões salvas, clientes conectados, credencial default, log de conexões)
   - FASE 3: Concluída (listSchedules, updateSchedule, executeSchedule, UI Agendamentos Remotos)
   - FASE 4: Concluída (protocolo, handler, requestFile, listFiles, UI Transferir Backups, progresso, FileTransferDao, histórico). FASE 5.1 parcial (pasta padrão).
5. **plano_implementacao_fase1_fase2.md** – plano para completar FASE 1 e FASE 2 (arquivos a criar, ordem sugerida, checklist)

### 2. Estado Atual do Projeto

#### ✅ JÁ IMPLEMENTADO (FASE 0 - 85%)

**Banco de Dados v14** (Commit: `2dbc725`):

- 4 tabelas criadas: `ServerCredentialsTable`, `ConnectionLogsTable`, `ServerConnectionsTable`, `FileTransfersTable`
- 4 DAOs criados com métodos CRUD completos
- Schema version atualizado: 13 → 14
- Migration script v14 implementado e testado automaticamente
- Índices de performance criados
- Código gerado com `build_runner` sem erros

**FASE 1 - Protocolo e Socket (26/31)**:

- `lib/core/constants/socket_config.dart` criado (porta 9527, chunk 128KB, timeouts)
- `lib/infrastructure/protocol/message_types.dart` criado (enum MessageType, 19 tipos)
- `lib/infrastructure/protocol/message.dart` criado (MessageHeader + Message, toJson/fromJson)
- `lib/core/utils/crc32.dart` criado (CRC32 puro Dart)
- `lib/infrastructure/protocol/binary_protocol.dart` criado (serializeMessage/deserializeMessage)
- `lib/infrastructure/protocol/compression.dart` criado (PayloadCompression zlib, flag no header)
- `lib/infrastructure/protocol/file_chunker.dart` criado (FileChunk + FileChunker, 128KB, CRC32)
- `lib/infrastructure/protocol/auth_messages.dart` criado (createAuthRequest, createAuthResponse)
- `lib/core/security/password_hasher.dart` criado (hash, verify, constantTimeEquals)
- `lib/domain/entities/connection/connected_client.dart` criado
- `lib/infrastructure/socket/server/socket_server_service.dart` (interface)
- `lib/infrastructure/socket/server/tcp_socket_server.dart` (ServerSocket, handlers, ClientManager opcional)
- `lib/infrastructure/socket/server/client_handler.dart` (buffer, parse, send, auth)
- `lib/infrastructure/socket/server/server_authentication.dart` (validateAuthRequest com ServerCredentialDao)
- `lib/infrastructure/socket/server/client_manager.dart` (register, unregister, getConnectedClients, disconnectClient)
- `lib/infrastructure/socket/client/socket_client_service.dart` (interface + ConnectionStatus, connect com serverId/password opcionais)
- `lib/infrastructure/socket/client/tcp_socket_client.dart` (connect com auth: authRequest → authResponse → connected/authenticationFailed)
- `lib/infrastructure/socket/client/connection_manager.dart` (connect com serverId/password opcionais; getSavedConnections, connectToSavedConnection com ServerConnectionDao opcional)
- `lib/infrastructure/socket/heartbeat.dart` (createHeartbeatMessage, HeartbeatManager, isHeartbeatMessage)
- Heartbeat integrado em ClientHandler e TcpSocketClient (interval 30s, timeout 60s)
- Auto-reconnect no TcpSocketClient (enableAutoReconnect, backoff 2^attempts, max 5)
- Testes unitários: `message_test`, `binary_protocol_test`, `compression_test`, `file_chunker_test`, `heartbeat_test`, `server_authentication_test`, `tcp_socket_server_test` (45+ testes)
- Testes de integração: `test/integration/socket_integration_test.dart` (Server → Client → sendToClient → broadcastToAll; auth: credencial correta → connected, senha errada → authenticationFailed/disconnected; usa `AppDatabase.inMemory()` para evitar path_provider em testes)
- Testes: `tcp_socket_client_test.dart` (status, disconnect, send, connect/disconnect, messageStream)
- Testes: `connection_manager_test.dart` (connect/disconnect, send, getSavedConnections, connectToSavedConnection)

**FASE 2 - Autenticação e Conexões (2.1–2.4 concluídas)**:

- **2.1 Server Credentials**: Entity `ServerCredential`, `IServerCredentialRepository` + `ServerCredentialRepository`, DI, `ServerCredentialProvider`, `ServerCredentialDialog`, `ServerCredentialListItem`, `ServerSettingsPage` (tab Credenciais de Acesso), testes unitários.
- **2.2 Client Conexões salvas**: Entity `ServerConnection`, `IServerConnectionRepository` + `ServerConnectionRepository`, DI, `ConnectionManager` com `ServerConnectionDao`, `ServerConnectionProvider`, `ConnectionDialog`, `ServerListItem`, `ServerLoginPage`, rota `/server-login`, testes unitários.
- **2.3 Clientes conectados**: `ClientManager`, `TcpSocketServer` (com `ConnectionLogDao` opcional), `SocketServerService` no DI, `ConnectedClientProvider`, `ConnectedClientsList` (tab Clientes Conectados em Server Settings), Iniciar/Parar servidor, polling 5s, Desconectar cliente.
  - **2.4 Credencial default e log de conexões**:
  - Entity `ConnectionLog`, `IConnectionLogRepository` + `ConnectionLogRepository`, DI.
  - `InitialSetupService.createDefaultCredentialIfNotExists()` (Server ID + senha aleatórios), chamado em `AppInitializer._initializeDefaultCredential()` após `_setupDependencies()`.
  - `ConnectionLogDao.insertConnectionAttempt()`; `ClientHandler` registra tentativas de auth (sucesso/falha) no `ConnectionLogDao`.
  - `ConnectionLogProvider`, `ConnectionLogsList` (filtro Todos/Sucesso/Falha, refresh), aba **Log de Conexões** em Server Settings.

**FASE 3 - Protocolo de Controle Remoto (Agendamentos)**:

- **Protocolo compartilhado**: `schedule_serialization.dart` (scheduleToMap/scheduleFromMap), `schedule_messages.dart` (listSchedules, scheduleList, updateSchedule, scheduleUpdated, executeSchedule, error com requestId).
- **Servidor**: `ScheduleMessageHandler` (processa listSchedules, updateSchedule, executeSchedule via IScheduleRepository, UpdateSchedule, ExecuteScheduledBackup); integrado em `TcpSocketServer` com `sendToClient`.
- **Cliente**: `ConnectionManager` com `listSchedules()`, `updateSchedule(Schedule)`, `executeSchedule(String scheduleId)` (requestId + Completer para parear requisição/resposta, timeout).
- **UI**: `RemoteSchedulesProvider`, `RemoteSchedulesPage` (lista agendamentos do servidor, atualizar, ativar/desativar, executar agora); rota `/remote-schedules`, item "Agendamentos Remotos" no `MainLayout`.

**FASE 4 - Transferência de Arquivos (concluída)**:

- **Protocolo**: `file_transfer_messages.dart` (fileTransferStart request/metadata, fileChunk, fileTransferProgress, fileTransferComplete, fileTransferError, fileAck; listFiles/fileList com `RemoteFileEntry`; create/parse).
- **Servidor**: `FileTransferMessageHandler` (allowedBasePath; listFiles → lista recursiva → fileList; requestFile com path relativo a allowedBasePath; envia metadata → chunks → progress → complete); integrado em `TcpSocketServer` e DI.
- **Cliente**: `ConnectionManager.requestFile(filePath, outputPath, { scheduleId, onProgress })` e `listAvailableFiles()` → `Result<List<RemoteFileEntry>>`; timeout e disconnect tratados.
- **UI**: `RemoteFileTransferProvider`, página "Transferir Backups" (lista remota, seleção, pasta destino, transferir, barra de progresso em tempo real); rota `/transfer-backups`, item no MainLayout.
- **FileTransferDao**: cada transferência (sucesso/falha) é registrada em `file_transfers_table`; histórico exibido na seção "Histórico de transferências" (últimas 50).
- **Testes**: `file_transfer_integration_test.dart` (transferência sucesso/erro, listAvailableFiles).

**FASE 5.1–5.3 – Destinos do Client**:

- **5.1** Preferência `received_backups_default_path`; checkbox "Salvar como pasta padrão" na página Transferir Backups.
- **5.2** `ISendFileToDestinationService` / `SendFileToDestinationService`; UI "Enviar também para" (checkboxes destinos remotos) na TransferBackupsPage.
- **5.3** Vinculação agendamento ↔ destino (SharedPreferences); dropdown Agendamento na TransferBackupsPage; ContentDialog em RemoteSchedulesPage para configurar destinos por agendamento.

**FASE 6 – Dashboard de Métricas**:

- Protocolo `metricsRequest` / `metricsResponse`; servidor: `MetricsMessageHandler`; cliente: `ConnectionManager.getServerMetrics()`, `DashboardProvider`; UI: seções "Local" e "Servidor" na DashboardPage.

**FASE 7 – Installer e Integração**:

- `AppMode` (server, client, unified), `getAppMode(args/env/config)`, `getWindowTitleForMode`, título da janela; instalador: atalhos "Backup Database (Servidor)" e "(Cliente)" no menu Iniciar.

**Pacotes**:

- `qr_flutter: ^4.1.0` adicionado (geração de QR codes)

**Qualidade**:

- `flutter analyze`: No issues found
- Clean Architecture mantida
- Todos os arquivos commitados no GitHub

#### ⏳ PENDENTE (FASE 0 - 15%)

- [x] Plano de testes: [fase0_migration_v14_test_plan.md](fase0_migration_v14_test_plan.md)
- [x] Teste de integração automatizado: `test/integration/database_migration_v14_test.dart`
- [ ] Testar migration manualmente com backup do banco
- [ ] Testar migration com dados existentes

### 3. Próximo Passo Imediato

#### **FASE 2.1–2.4 concluídas**

- **2.1** Server Credentials (entity, repository, UI, Provider, Dialog, Server Settings tab).
- **2.2** Client: ServerConnection (entity, repository, UI), ServerLoginPage, ConnectionDialog, ServerListItem, ConnectionManager com saved connections.
- **2.3** Clientes conectados: ConnectedClientProvider, ConnectedClientsList, Iniciar/Parar servidor, Desconectar cliente.
- **2.4** Credencial default (`InitialSetupService` no bootstrap), log de conexões (ConnectionLog entity/repository, ClientHandler grava tentativas, aba Log de Conexões na Server Settings).

#### **Próximos passos recomendados (escolher ordem)**

1. **FASE 0 (15% restante)**  
   - [ ] Testar migration manualmente com backup do banco  
   - [ ] Testar migration com dados existentes  

2. **FASE 1 (opcional)**  
   - [x] `client_handler_test.dart` (testes unitários do ClientHandler)  
   - [x] Revisar cancelamento de timers/streams (zero memory leaks)  

3. **FASE 3 – Protocolo de Controle Remoto** ✅ **Concluída**  
   - [x] Mensagens e fluxos: listSchedules / scheduleList, updateSchedule / scheduleUpdated, executeSchedule  
   - [x] Implementar no servidor (ScheduleMessageHandler) e no cliente (ConnectionManager)  
   - [x] UI no cliente: `RemoteSchedulesPage`, rota `/remote-schedules`, item no MainLayout  

4. **FASE 4 – Transferência de Arquivos** ✅ **Concluída**  
   - [x] Protocolo e mensagens: fileTransferStart (request/metadata), fileChunk, fileTransferProgress, fileTransferComplete, fileTransferError, fileAck; listFiles/fileList  
   - [x] Servidor: FileTransferMessageHandler (allowedBasePath, listFiles, requestFile com path relativo), integrado em TcpSocketServer e DI  
   - [x] Cliente: ConnectionManager.requestFile(filePath, outputPath, onProgress), listAvailableFiles()  
   - [x] UI: página "Transferir Backups" (lista remota, seleção, destino, transferir, barra de progresso); rota `/transfer-backups`  
   - [x] Testes de integração (transferência + listAvailableFiles)  
   - [x] **Opcional:** progresso em tempo real na UI (onProgress, barra de progresso)  
   - [x] **Opcional:** FileTransferDao para registrar transferências concluídas  
   - [x] **Opcional:** histórico de transferências na UI (seção na página Transferir Backups)

5. **FASE 5 – Destinos do Client** ✅ **Concluída**  
   - [x] Configurar pasta local padrão para backups recebidos (preferência + checkbox "Salvar como pasta padrão")  
   - [x] Reutilizar destinos existentes (FTP, Google Drive, etc.) para envio após receber do servidor ("Enviar também para")  
   - [x] Vincular agendamento remoto a destino do client; upload automático após transferência  

6. **FASE 6 – Dashboard de Métricas** ✅ **Concluída**  
   - [x] metricsRequest / metricsResponse no servidor (MetricsMessageHandler)  
   - [x] Dashboard no client com métricas locais + servidor (seções Local e Servidor)  

7. **FASE 7 – Installer e Integração** ✅ **Concluída**  
   - [x] AppMode (server, client, unified), detecção (args, env, config/mode.ini), título da janela  
   - [x] Instalador: atalhos "Backup Database (Servidor)" e "(Cliente)" no menu Iniciar  

### 4. FASE 1: Fundamentos Socket (26/31 tarefas)

#### Objetivo da FASE 1

Infraestrutura base para comunicação Socket TCP/IP entre Server e Client

#### Critérios de Aceitação

- [ ] Server pode aceitar conexões TCP na porta 9527
- [ ] Client pode conectar ao Server via Socket
- [ ] Autenticação básica funciona (Server ID + Password)
- [ ] Heartbeat/ping-pong funciona
- [ ] Mensagens podem ser enviadas e recebidas
- [ ] Testes unitários passando
- [ ] Zero memory leaks

#### Primeiras 5 Tarefas da FASE 1

1. ~~**Criar `lib/core/constants/socket_config.dart`**~~ ✅

   - Definir constantes: porta 9527, chunk 128KB, timeouts

2. ~~**Criar `lib/infrastructure/protocol/message_types.dart`**~~ ✅

   - Enum MessageType com 19 tipos (authRequest, heartbeat, fileChunk, etc.)

3. ~~**Criar `lib/infrastructure/protocol/message.dart`**~~ ✅

   - Class MessageHeader + Message (header + payload + checksum)
   - toJson() / fromJson(), validateChecksum()

4. ~~**Criar `lib/core/utils/crc32.dart`**~~ ✅

   - Crc32.calculate(List<int>) – implementação pura Dart

5. ~~**Criar `lib/infrastructure/protocol/binary_protocol.dart`**~~ ✅
   - serializeMessage / deserializeMessage, calculateChecksum, validateChecksum

### 5. Estrutura de Pastas (Já Existente)

```
lib/
├── core/
│   ├── constants/
│   │   └── socket_config.dart (✅ CRIADO)
│   ├── security/
│   │   └── password_hasher.dart (✅ CRIADO)
│   └── utils/
│       ├── logger_service.dart (✅ EXISTE - reutilizar)
│       └── crc32.dart (✅ CRIADO)
│
├── domain/
│   ├── entities/
│   │   ├── protocol/
│   │   │   ├── 📝 message.dart (CRIAR NA FASE 1)
│   │   │   ├── 📝 file_chunk.dart (CRIAR NA FASE 1)
│   │   │   └── 📝 file_transfer_progress.dart (CRIAR NA FASE 1)
│   │   └── connection/
│   │       ├── server_connection.dart (✅ CRIADO)
│   │       ├── connection_log.dart (✅ CRIADO)
│   │       └── connected_client.dart (✅ CRIADO)
│   └── value_objects/
│       └── 📝 server_id.dart (CRIAR NA FASE 2)
│
├── infrastructure/
│   ├── protocol/
│   │   ├── binary_protocol.dart (✅ CRIADO)
│   │   ├── message.dart (✅ CRIADO)
│   │   ├── message_types.dart (✅ CRIADO)
│   │   ├── compression.dart (✅ CRIADO)
│   │   ├── file_chunker.dart (✅ CRIADO)
│   │   ├── file_transfer_messages.dart (✅ CRIADO – FASE 4)
│   │   ├── schedule_serialization.dart (✅ CRIADO – FASE 3)
│   │   └── schedule_messages.dart (✅ CRIADO – FASE 3)
│   ├── socket/
│   │   ├── server/
│   │   │   ├── socket_server_service.dart (✅ CRIADO)
│   │   │   ├── tcp_socket_server.dart (✅ CRIADO)
│   │   │   ├── client_handler.dart (✅ CRIADO)
│   │   │   ├── file_transfer_message_handler.dart (✅ CRIADO – FASE 4)
│   │   │   └── schedule_message_handler.dart (✅ CRIADO – FASE 3)
│   │   ├── client/
│   │   │   ├── socket_client_service.dart (✅ CRIADO)
│   │   │   ├── tcp_socket_client.dart (✅ CRIADO)
│   │   │   └── connection_manager.dart (✅ CRIADO)
│   │   └── heartbeat.dart (✅ CRIADO)
│   └── datasources/
│       ├── local/
│       │   ├── database.dart (✅ v14 JÁ ATUALIZADO)
│       │   └── tables/
│       │       ├── server_credentials_table.dart (✅ CRIADO)
│       │       ├── connection_logs_table.dart (✅ CRIADO)
│       │       ├── server_connections_table.dart (✅ CRIADO)
│       │       └── file_transfers_table.dart (✅ CRIADO)
│       └── daos/
│           ├── server_credential_dao.dart (✅ CRIADO)
│           ├── connection_log_dao.dart (✅ CRIADO)
│           ├── server_connection_dao.dart (✅ CRIADO)
│           └── file_transfer_dao.dart (✅ CRIADO)
│
├── presentation/
│   ├── pages/
│   │   ├── server_settings_page.dart (✅ CRIADO – 3 tabs: Credenciais, Clientes Conectados, Log de Conexões)
│   │   ├── server_login_page.dart (✅ CRIADO – lista de servidores salvos, Conectar/Adicionar)
│   │   └── remote_schedules_page.dart (✅ CRIADO – FASE 3, Agendamentos Remotos)
│   └── widgets/
│       ├── common/
│       │   ├── app_button.dart (✅ EXISTE - reutilizar)
│       │   ├── app_card.dart (✅ EXISTE - reutilizar)
│       │   └── config_list_item.dart (✅ EXISTE - reutilizar)
│       └── 📝 client/ (CRIAR NOVOS WIDGETS)
│           └── 📝 qr_code_widget.dart (CRIAR NA FASE 2)
```

### 6. Comandos Importantes

```bash
# Verificar código
flutter analyze

# Gerar código Drift após mudar banco de dados
dart run build_runner build --delete-conflicting-outputs

# Rodar testes
flutter test

# Ver mudanças no banco
git diff lib/infrastructure/datasources/local/database.dart

# Fazer commit padrão
git add .
git commit -m "feat(scope): description"
git push origin feature/client-server-architecture
```

### 7. Regras do Projeto (MUITO IMPORTANTE)

**Clean Architecture**:

- Domain Layer NÃO pode importar Infrastructure/Application/Presentation
- Application Layer NÃO pode importar Infrastructure/Presentation
- Infrastructure Layer NÃO pode importar Application/Presentation
- Presentation Layer NÃO pode importar Infrastructure

**Protocolo Binário (CRÍTICO)**:

- Código de protocolo DEVE ser 100% compartilhado entre Server e Client
- NÃO criar arquivos separados para Server/Client do protocolo
- Pasta `lib/infrastructure/protocol/` é compartilhada!

**Reutilização**:

- UI Components existentes em `lib/presentation/widgets/common/` devem ser reutilizados
- Services existentes (LoggerService, EncryptionService) devem ser reutilizados
- Destinos de backup (FTP, Google Drive, etc.) JÁ EXISTEM e funcionam

**Qualidade**:

- Sempre rodar `flutter analyze` antes de commitar
- Seguir padrões de código existentes (naming, estrutura)
- Usar `const` constructors wherever possible
- Adicionar testes unitários para lógica de negócio

### 8. Decisões Já Tomadas (NÃO MUDAR)

✅ **Porta**: 9527 (configurável, mas default é 9527)
✅ **Chunk size**: 128KB (131072 bytes)
✅ **Compressão**: Sim (zlib)
✅ **TLS/SSL**: Não para v1 (planejado para v2)
✅ **Limite clientes**: Ilimitado
✅ **Protocolo**: TCP Socket (dart:io nativo)
✅ **Autenticação**: Server ID + Password (SHA-256 hash)
✅ **Banco**: Drift/SQLite v14 (já implementado)

### 9. Arquivos de Referência

| Arquivo                               | Para Que Serve                                |
| ------------------------------------- | --------------------------------------------- |
| `plano_cliente_servidor.md`           | Arquitetura completa, decisões técnicas       |
| `implementacao_cliente_servidor.md`   | Checklist DETALHADO de todas as tarefas       |
| `analise_tecnica_ui_banco_pacotes.md` | Análise técnica, componentes existentes       |
| `ui_instalacao_cliente_servidor.md`   | Wireframes de UI, instalador Inno Setup       |
| `.claude/rules/`                      | Regras de código (Clean Architecture, estilo) |

### 10. Comandos Rápidos Para Começar

```bash
# 1. Verificar branch atual
git branch

# 2. Ver se está tudo commitado
git status

# 3. Ler os documentos de planejamento
# - plano_cliente_servidor.md (arquitetura)
# - implementacao_cliente_servidor.md (checklist FASE 1)

# 4. Criar primeiro arquivo
# lib/core/constants/socket_config.dart

# 5. Rodar analyze
flutter analyze

# 6. Commit
git add lib/core/constants/socket_config.dart
git commit -m "feat(core): add SocketConfig constants"
git push origin feature/client-server-architecture
```

### 11. Perguntas Frequentes

**Q: Posso mudar o chunk size de 128KB?**
A: Não! Essa decisão já foi tomada e validada. Mantenha 131072 bytes.

**Q: Preciso criar dois protocolos (Server e Client)?**
A: NÃO! Protocolo binário DEVE ser 100% compartilhado. Pasta `lib/infrastructure/protocol/` é usada por ambos.

**Q: Posso usar gRPC em vez de TCP Socket?**
A: Não! Decisão técnica já foi tomada. Use TCP Socket com dart:io nativo.

**Q: Onde coloco código de Socket Server?**
A: `lib/infrastructure/socket/server/tcp_socket_server.dart`

**Q: Onde coloco código de Socket Client?**
A: `lib/infrastructure/socket/client/tcp_socket_client.dart`

**Q: Preciso recriar os destinos de backup?**
A: NÃO! Eles JÁ EXISTEM em `lib/infrastructure/external/destinations/` e funcionam perfeitamente. Apenas reutilize.

**Q: Como testar a migration v14?**
A:

1. Backup do banco atual
2. Rodar o app (migration acontece automaticamente)
3. Verificar se as 4 novas tabelas foram criadas
4. Inserir dados de teste
5. Verificar se DAOs funcionam

### 12. Checkpoint - O Que Deveria Estar Próximo

Após ler este documento, você deveria ser capaz de:

- [x] Saber EXATAMENTE o que já foi implementado (banco v14, FASE 1 protocolo/socket, FASE 2.1–2.4)
- [x] Saber EXATAMENTE o que fazer a seguir (FASE 0 migration tests, FASE 1 opcional, ou FASE 3 Controle Remoto)
- [x] Conhecer todas as decisões técnicas já tomadas
- [x] Saber quais arquivos reutilizar vs quais criar
- [x] Entender a arquitetura e regras do projeto
- [x] (FASE 3 concluída) listSchedules/scheduleList, updateSchedule, executeSchedule e UI remote_schedules_page implementados
- [x] (FASE 4 em andamento) Protocolo file transfer, FileTransferMessageHandler, ConnectionManager.requestFile implementados
- [ ] (Próximo) FASE 4: UI para solicitar arquivo ao servidor, listagem de backups, testes de integração de transferência

### 13. Suporte e Referências

**Documentos do Projeto**:

- Todos em `docs/dev/`
- Leitura obrigatória antes de codificar

**Regras de Código**:

- `.claude/rules/` - Clean Architecture, estilo Dart, UI patterns
- LEIA antes de escrever código!

**Commits Recentes** (entender o que foi feito):

- `2dbc725` - Banco de dados v14 implementado
- `9138ebd` - Documentação atualizada

---

## 📝 Notas para a Próxima IA

1. **NÃO pule a leitura dos documentos** - O planejamento é EXTENSIVO por um motivo
2. **Comece PEQUENO** - Primeiro crie `socket_config.dart` (5 minutos)
3. **Reutilize TUDO** - UI components, services, destinos - JÁ EXISTEM
4. **Siga Clean Architecture** - Violations causarão problemas
5. **Teste constantemente** - `flutter analyze` é seu amigo
6. **Commit frequentemente** - Commits pequenos são melhores que um monolítico

**Boa sorte! 🚀**
