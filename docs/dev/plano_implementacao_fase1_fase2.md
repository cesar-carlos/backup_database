# Plano de Implementação – FASE 1 e FASE 2

Documento de referência para completar FASE 1 (Fundamentos Socket) e FASE 2 (Autenticação e Conexões). Ordem sugerida de implementação.

---

## Já implementado (não refazer)

- **Protocolo**: message_types, message, binary_protocol, compression, auth_messages, crc32, message_test, binary_protocol_test
- **Server**: TcpSocketServer, ClientHandler, ServerAuthentication, ClientManager, tcp_socket_server_test, server_authentication_test
- **Client**: TcpSocketClient, ConnectionManager (connect, disconnect, send, getSavedConnections, connectToSavedConnection), tcp_socket_client_test, connection_manager_test
- **Heartbeat**: heartbeat.dart, heartbeat_test
- **Segurança**: PasswordHasher (hash, verify, constantTimeEquals)
- **Banco**: ServerCredentialsTable + ServerCredentialDao, ServerConnectionsTable + ServerConnectionDao, ConnectionLogsTable + ConnectionLogDao
- **Domain**: ConnectedClient (lib/domain/entities/connection/connected_client.dart)
- **Integração**: socket_integration_test (connect, sendToClient, broadcastToAll, auth ok, auth fail)

---

# FASE 1 – O que falta implementar

## 1.1 Compression test

| # | Ação | Caminho |
|---|------|--------|
| 1 | Criar testes unitários de compressão | `test/unit/infrastructure/protocol/compression_test.dart` |
|   | • compress/decompress round-trip | |
|   | • shouldCompress(true para size > 1KB) | |
|   | • (opcional) performance ou taxa de compressão | |

**Referência**: `lib/infrastructure/protocol/compression.dart` (PayloadCompression, ZLibCodec).

---

## 1.2 File Chunker (protocolo para FASE 4, mas listado na FASE 1)

| # | Ação | Caminho |
|---|------|--------|
| 1 | Criar classe `FileChunk` | `lib/infrastructure/protocol/file_chunker.dart` |
|   | • chunkIndex, totalChunks, data (Uint8List), checksum (int/String CRC32) | |
|   | • toJson() / fromJson() ou equivalente para serialização no payload | |
| 2 | Criar classe `FileChunker` | mesmo arquivo ou separado |
|   | • `chunkFile(String filePath, int chunkSize)`: Stream/List\<FileChunk\> – ler em chunks de chunkSize (128KB), CRC32 por chunk | |
|   | • `assembleChunks(List<FileChunk> chunks, String outputPath)`: validar checksum, escrever em ordem | |
| 3 | Testes | `test/unit/infrastructure/protocol/file_chunker_test.dart` |
|   | • arquivo pequeno (<128KB), grande (>1MB), assembly, checksum inválido, chunk faltando | |

**Constante**: usar `SocketConfig` ou constante 128KB para chunkSize default.

---

## 1.3 Testes Socket Server (complementares)

| # | Ação | Caminho |
|---|------|--------|
| 1 | Teste múltiplas conexões | `test/unit/infrastructure/socket/tcp_socket_server_test.dart` |
|   | • start server, connect 2 clientes, getConnectedClients().length == 2, disconnect um, verificar 1 restante | |
| 2 | Teste envio de mensagem | mesmo arquivo |
|   | • connect cliente, sendToClient com Message, cliente recebe no messageStream | |

---

## 1.4 ClientHandler test (opcional)

| # | Ação | Caminho |
|---|------|--------|
| 1 | Criar testes isolados do ClientHandler | `test/unit/infrastructure/socket/client_handler_test.dart` |
|   | • mock Socket (ou usar package fake_async / raw socket em teste de integração) | |
|   | • autenticação (authRequest → authResponse success/fail) | |
|   | • recebimento e envio de mensagem, desconexão | |

**Nota**: parte do comportamento já coberta por `socket_integration_test`; este arquivo adiciona cobertura unitária isolada.

---

## 1.5 Auto-reconnect tests

| # | Ação | Caminho |
|---|------|--------|
| 1 | Teste reconnect após desconexão | `test/unit/infrastructure/socket/tcp_socket_client_test.dart` ou novo arquivo |
|   | • start server, client connect com enableAutoReconnect: true, server.stop(), aguardar reconnect (porta reaberta), verificar connected | |
| 2 | Teste max attempts | • após N falhas (SocketConfig.maxReconnectAttempts), status não deve ser connecting; reconnect não deve ser agendado | |
| 3 | Teste backoff | • verificar que o intervalo entre tentativas cresce (2^attempts) até o máximo | |

---

## 1.6 Testes de integração adicionais

| # | Ação | Caminho |
|---|------|--------|
| 1 | Auth + Heartbeat | `test/integration/socket_integration_test.dart` |
|   | • server com auth, client conecta com credencial, aguardar 1–2 heartbeats, verificar que cliente continua connected | |
| 2 | Múltiplos clientes | • 2 clientes conectados, sendToClient para um, broadcastToAll, ambos recebem o broadcast | |
| 3 | Server para → Client reconnect | • client connect com enableAutoReconnect, server.stop(), server.start(port) de novo, aguardar client reconectar | |
| 4 | (Opcional) Large message | • payload >1MB, enviar e receber, validar checksum/compressão | |

---

## 1.7 Revisão FASE 1

| # | Ação |
|---|------|
| 1 | Revisar cancelamento de subscriptions, timers e streams (zero memory leaks) em TcpSocketClient, ClientHandler, TcpSocketServer. |
| 2 | (Opcional) Logging debug: message sent/received; níveis por ambiente. |

---

# FASE 2 – O que falta implementar

**Observação**: DAOs e tabelas (server_credentials, server_connections, connection_logs) já existem. PasswordHasher já existe. ConnectionManager já tem getSavedConnections e connectToSavedConnection. O foco da FASE 2 é **domain entities**, **repositories** (onde fizer sentido), **UI** e **services**.

---

## 2.1 Server – Credenciais (domain + UI)

### 2.1.1 Domain e repositório ✅ (concluído)

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Entity `ServerCredential` (domain, sem Drift) | `lib/domain/entities/server_credential.dart` |
|   | • id, serverId, passwordHash, name, createdAt, isActive, lastUsedAt?, description? | |
| 2 | [x] Interface do repositório | `lib/domain/repositories/i_server_credential_repository.dart` |
|   | • getAll(), getById(), getByServerId(), save(), update(), delete(), getActive(), updateLastUsed(), watchAll() | |
| 3 | [x] Implementação usando ServerCredentialDao | `lib/infrastructure/repositories/server_credential_repository.dart` |
|   | • mapear ServerCredentialsTableData ↔ ServerCredential | |
| 4 | [x] Registrar no DI | `lib/core/di/service_locator.dart` |
| 5 | [x] Testes unitários | `test/unit/domain/entities/server_credential_test.dart`, `test/unit/infrastructure/repositories/server_credential_repository_test.dart` |

**Nota**: ServerAuthentication hoje usa ServerCredentialDao diretamente; pode seguir assim ou passar a usar IServerCredentialRepository (injetando no TcpSocketServer/ClientHandler).

### 2.1.2 UI – Configuração de credenciais (Server) ✅ (concluído)

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Página Server Settings (FluentUI) | `lib/presentation/pages/server_settings_page.dart` |
|   | • Abas: Credenciais de Acesso | Clientes Conectados (placeholder) |
|   | • Lista de credenciais (getAll), botão "Nova Credencial" | |
| 2 | [x] Dialog Nova/Editar Credencial | `lib/presentation/widgets/server/server_credential_dialog.dart` |
|   | • Server ID, Nome, Password, Confirmar Password, Descrição, Ativo, Gerar senha aleatória | |
|   | • Validações: ID único (create), senha ≥ 8 caracteres, passwords iguais | |
| 3 | [x] Provider | `lib/application/providers/server_credential_provider.dart` |
|   | • loadCredentials(), createCredential(), updateCredential(), deleteCredential() | |
|   | • PasswordHasher.hash(plainPassword, serverId) ao salvar | |
| 4 | [x] Rota e entrada no app | go_router `/server-settings`, item "Servidor" na navegação, ServerCredentialProvider no DI |

---

## 2.2 Client – Conexões salvas (domain + UI) ✅ (concluído)

### 2.2.1 Domain e repositório ✅

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Entity `ServerConnection` (domain) | `lib/domain/entities/server_connection.dart` |
|   | • id, name, serverId, host, port, password, isOnline, lastConnectedAt?, createdAt, updatedAt | |
| 2 | [x] Interface | `lib/domain/repositories/i_server_connection_repository.dart` |
|   | • getAll(), getById(), save(), update(), delete(), watchAll() | |
| 3 | [x] Implementação usando ServerConnectionDao | `lib/infrastructure/repositories/server_connection_repository.dart` |
|   | • Mapear ServerConnectionsTableData ↔ ServerConnection | |
| 4 | [x] Registrar no DI | `lib/core/di/service_locator.dart` |
|   | ConnectionManager registrado com serverConnectionDao (opcional IServerConnectionRepository não aplicado) | |

### 2.2.2 UI – Login / lista de servidores (Client) ✅

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Página de login / lista de conexões | `lib/presentation/pages/server_login_page.dart` |
|   | • Lista de servidores salvos via ServerConnectionProvider | |
|   | • Botão "Adicionar Servidor", por card: Testar, Conectar/Desconectar, Editar, Excluir | |
|   | • Indicador de status (Conectado/Offline/Conectando) por conexão | |
| 2 | [x] Dialog Adicionar/Editar conexão | `lib/presentation/widgets/client/connection_dialog.dart` |
|   | • Nome, Host, Porta, Server ID, Password, Salvar | |
| 3 | [x] Widget card de item da lista | `lib/presentation/widgets/client/server_list_item.dart` |
|   | • Nome, host:porta, serverId, última conexão, status, ações (Testar, Conectar, Editar, Excluir) | |
| 4 | [x] Provider | `lib/application/providers/server_connection_provider.dart` |
|   | • loadConnections(), saveConnection(), updateConnection(), deleteConnection() | |
|   | • connectTo(connectionId), disconnect(), testConnection(connection) | |
| 5 | [x] Rota e entrada no app | go_router `/server-login`, item "Conectar" na navegação |

---

## 2.3 Server – Clientes conectados (monitoramento) ✅ (concluído)

### 2.3.1 ConnectedClient e repositório

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Entity `ConnectedClient` | Já existe em `lib/domain/entities/connection/connected_client.dart` |
| 2 | — | Interface/repositório in-memory não implementados; provider usa SocketServerService diretamente |
| 3 | [x] TcpSocketServer + ClientManager no DI | `lib/core/di/service_locator.dart` – singleton para polling |

### 2.3.2 UI – Lista de clientes conectados (Server) ✅

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Widget lista (ListView FluentUI) | `lib/presentation/widgets/server/connected_clients_list.dart` |
|   | • Nome, host:porta, Connected At, Last Heartbeat, chip Autenticado, botão Desconectar | |
|   | • Estado "Servidor não está em execução" com botão "Iniciar servidor"; polling 5s | |
| 2 | [x] Provider | `lib/application/providers/connected_client_provider.dart` |
|   | • refresh(), disconnectClient(id), startServer(port), stopServer() | |
| 3 | [x] Aba "Clientes Conectados" na Server Settings | `server_settings_page.dart` (aba 2) usa `ConnectedClientsList` |

---

## 2.4 Credencial default e log de conexões ✅

### 2.4.1 Credencial default (instalação / primeira execução)

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Service | `lib/application/services/initial_setup_service.dart` |
|   | • createDefaultCredentialIfNotExists(): se nenhuma credencial, criar uma (Server ID aleatório, senha aleatória), salvar via repository | |
|   | • Retorna DefaultCredentialResult (serverId, plainPassword) para exibir na UI (opcional) | |
| 2 | [x] Chamar no bootstrap do app | `AppInitializer._initializeDefaultCredential()` após `_setupDependencies()`. |

### 2.4.2 Log de tentativas de conexão

| # | Ação | Caminho |
|---|------|--------|
| 1 | [x] Entity `ConnectionLog` (domain) | `lib/domain/entities/connection_log.dart` |
|   | • id, clientHost, serverId?, success, errorMessage?, timestamp, clientId? | |
| 2 | [x] ConnectionLogDao.insertConnectionAttempt() | `lib/infrastructure/datasources/daos/connection_log_dao.dart` |
| 3 | [x] Registrar tentativa no ClientHandler | Ao validar auth: inserir log (clientHost, serverId, success, errorMessage, clientId). TcpSocketServer recebe ConnectionLogDao opcional. |
| 4 | [x] Tela de logs | Aba **Log de Conexões** em Server Settings: `ConnectionLogsList`, filtro Todos/Sucesso/Falha, `ConnectionLogProvider` + `IConnectionLogRepository`/`ConnectionLogRepository`. |

---

# Ordem sugerida de execução

**FASE 1 (fechar fundação)**  
1. compression_test  
2. file_chunker + file_chunker_test  
3. Testes tcp_socket_server (múltiplas conexões, envio)  
4. Testes auto-reconnect (tcp_socket_client ou integração)  
5. Integração: Auth+Heartbeat, múltiplos clientes, reconnect  
6. (Opcional) client_handler_test, revisão memory leaks  

**FASE 2 (valor para usuário)**  
1. Domain: ServerCredential, ServerConnection, ConnectionLog (entities)  
2. Repositories: ServerCredentialRepository, ServerConnectionRepository, ConnectedClientRepository (in-memory)  
3. UI Client: server_login_page, connection_dialog, server_list_item, ServerConnectionProvider → integrar ConnectionManager  
4. UI Server: server_settings_page (credenciais), server_credential_dialog, ServerCredentialProvider  
5. Server: connected_clients_list, ConnectedClientProvider; aba Clientes Conectados  
6. initial_setup_service (credencial default)  
7. Log de auth: registrar em ConnectionLogDao no ServerAuthentication; tela de logs (opcional)  

---

# Checklist rápido

- [x] FASE 1: compression_test
- [x] FASE 1: file_chunker + testes
- [x] FASE 1: testes server (múltiplas conexões, envio)
- [x] FASE 1: testes auto-reconnect
- [x] FASE 1: testes integração (auth+heartbeat, múltiplos clientes, reconnect)
- [x] FASE 2: entities ServerCredential, ServerConnection, ConnectionLog
- [x] FASE 2: repositories (credential, connection, connection log; connected client via ClientManager)
- [x] FASE 2: UI Client (login page, connection_dialog, server_list_item, provider)
- [x] FASE 2: UI Server (settings page, credential dialog, provider)
- [x] FASE 2: UI Server (connected clients list, provider)
- [x] FASE 2: initial_setup_service (credencial default, bootstrap)
- [x] FASE 2: log de auth (ConnectionLogDao + ClientHandler + aba Log de Conexões)
