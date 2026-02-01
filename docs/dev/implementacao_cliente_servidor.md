# Implementação Cliente-Servidor - Checklist Detalhado

> **Branch**: `feature/client-server-architecture`
> **Data de Início**: 2026-01-XX
> **Status**: 🔄 Em Andamento
>
> **Documentos Relacionados**:
> - [Plano Detalhado](plano_cliente_servidor.md) - Arquitetura e decisões
> - [Anotações Iniciais](anotacoes.txt) - Requisitos originais
> - [UI/UX e Instalação](ui_instalacao_cliente_servidor.md) - Telas, instalador e código compartilhado

---

## 📋 Decisões Definidas

✅ **Porta default**: 9527
✅ **Tamanho de chunk**: 1MB (1048576 bytes)
✅ **Compressão durante transferência**: Sim (zlib)
✅ **TLS/SSL**: Depois (v2)
✅ **Limite de clientes**: Ilimitado

---

## 📊 Progresso Geral

### Fases de Implementação

| Fase | Descrição | Semanas | Progresso | Status |
|------|-----------|---------|-----------|--------|
| 1 | Fundamentos Socket | 1-2 | [ ] 0/31 | ⏳ Não Iniciado |
| 2 | Autenticação e Conexões | 3 | [ ] 0/24 | ⏳ Não Iniciado |
| 3 | Protocolo de Controle Remoto | 4 | [ ] 0/23 | ⏳ Não Iniciado |
| 4 | Transferência de Arquivos | 5-6 | [ ] 0/42 | ⏳ Não Iniciado |
| 5 | Destinos do Client | 7 | [ ] 0/18 | ⏳ Não Iniciado |
| 6 | Dashboard de Métricas | 8 | [ ] 0/15 | ⏳ Não Iniciado |
| 7 | Installer e Integração | 9 | [ ] 0/21 | ⏳ Não Iniciado |
| 8 | Testes e Documentação | 10 | [ ] 0/27 | ⏳ Não Iniciado |

**Total**: 201 tarefas

---

## 🔗 Código Compartilhado (Server e Client)

> **Detalhes completos em**: [UI/UX e Instalação](ui_instalacao_cliente_servidor.md#código-compartilhado)

### Princípio: DRY (Don't Repeat Yourself)

Muito código será usado tanto pelo Server quanto pelo Client. Vamos seguir o princípio DRY e criar código compartilhado desde o início.

### 1. Protocolo Binário (100% Compartilhado)

**Pasta**: `lib/infrastructure/protocol/`

- `message_types.dart` - Enum MessageType (18 tipos)
- `message.dart` - Class Message (header + payload + checksum)
- `binary_protocol.dart` - Serialização/deserialização
- `compression.dart` - Compressão zlib
- `file_chunker.dart` - Chunking de arquivos (1MB)
- `checksum.dart` - CRC32 calculation

**✅ Server envia e recebe usando os mesmos protocolos**
**✅ Client envia e recebe usando os mesmos protocolos**

### 2. Destinos de Backup (EXISTENTE - Reutilizar 100%)

**Pasta**: `lib/infrastructure/external/destinations/`

Serviços existentes que **NÃO precisam ser recriados**:

- `local_destination_service.dart` ✅
- `ftp_destination_service.dart` ✅
- `google_drive_destination_service.dart` ✅
- `dropbox_destination_service.dart` ✅
- `nextcloud_destination_service.dart` ✅

**Uso**:
- **Server**: Envia backups executados localmente
- **Client**: Envia backups recebidos do servidor

### 3. Entities Compartilhadas

```dart
// lib/domain/entities/protocol/
✅ Message                    // Usado por ambos
✅ FileChunk                  // Usado por ambos
✅ FileTransferProgress       // Usado por ambos

// lib/domain/entities/connection/
✅ RemoteScheduleControl      // Representa agendamento controlado
✅ ServerConnection           // Salvo pelo Client
✅ ConnectedClient            // Rastreado pelo Server
```

### 4. Serviços Compartilhados

```dart
// lib/core/security/
✅ PasswordHasher             // Hash e validação de senhas

// lib/core/utils/
✅ LoggerService              // Logging estruturado (EXISTENTE)

// lib/core/constants/
✅ SocketConfig               // Porta 9527, chunk 1MB, timeouts
```

### 5. UI Components Compartilhados

```dart
// lib/presentation/widgets/common/
📝 StatusIndicator           // Indicador online/offline (NOVO)
📝 ProgressCard              // Card de progresso genérico (NOVO)
📝 DestinationPicker         // Seletor de destino (REUTILIZAR)
📝 FileTransferIndicator     // Indicador de transferência (NOVO)
```

### 6. Diagrama de Dependências

```
┌─────────────────────────────────────────────────────────────────┐
│                    CÓDIGO COMPARTILHADO                        │
│  (Server e Client usam os mesmos arquivos)                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  Domain Layer                                                     │
│  ├── entities/protocol/        ✅ Message, FileChunk          │
│  ├── value_objects/           ✅ ServerId, PortNumber         │
│  └── services/                ✅ IProtocolService             │
│                                                                   │
│  Infrastructure Layer                                            │
│  ├── protocol/                 ✅ BinaryProtocol, Compression  │
│  ├── external/destinations/   ✅ FTP, GoogleDrive, etc (REUSE)│
│  └── core/security/           ✅ PasswordHasher               │
│                                                                   │
│  Core                                                             │
│  ├── utils/logger_service.dart  ✅ (REUSE)                     │
│  └── constants/socket_config.dart ✅ (NOVO)                    │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
           ↕ compartilha                    ↕ compartilha
┌──────────────────────┐        ┌──────────────────────────────┐
│  SERVER-SPECIFIC     │        │  CLIENT-SPECIFIC             │
│                      │        │                              │
│ • TcpSocketServer    │        │ • TcpSocketClient            │
│ • ClientHandler      │        │ • ConnectionManager          │
│ • ServerAuth         │        │ • FileTransferHandler        │
│ • ServerSettings UI  │        │ • ServerLogin UI             │
└──────────────────────┘        └──────────────────────────────┘
```

### 7. Checklist Código Compartilhado

**Antes de iniciar FASE 1**:
- [ ] Criar pasta `lib/domain/entities/protocol/`
- [ ] Criar `lib/core/constants/socket_config.dart` com configurações
- [ ] Documentar serviços que podem ser reutilizados
- [ ] Mover entidades compartilhadas para pasta correta
- [ ] Atualizar imports em código existente

**Durante FASE 1**:
- [ ] Implementar protocol binário como código compartilhado
- [ ] Testar protocolo com testes unitários isolados
- [ ] Não criar código duplicado Server/Client

**Validação**:
- [ ] Server usa protocolo de `lib/infrastructure/protocol/`
- [ ] Client usa protocolo de `lib/infrastructure/protocol/` (mesmo!)
- [ ] Zero duplicação de código de protocolo

---

## 🎯 FASE 1: Fundamentos Socket (Semanas 1-2)

### Objetivo
Infraestrutura base para comunicação Socket TCP/IP entre Server e Client

### Critérios de Aceitação
- [ ] Server pode aceitar conexões TCP na porta 9527
- [ ] Client pode conectar ao Server via Socket
- [ ] Autenticação básica funciona (Server ID + Password)
- [ ] Heartbeat/ping-pong funciona
- [ ] Mensagens podem ser enviadas e recebidas
- [ ] Testes unitários passando
- [ ] Zero memory leaks

---

### 1.1 Protocolo Binário

#### 1.1.1 Estrutura da Mensagem
- [ ] Criar arquivo `lib/infrastructure/protocol/message_types.dart`
  - [ ] Enum `MessageType` com 15 tipos:
    - [ ] authRequest
    - [ ] authResponse
    - [ ] authChallenge
    - [ ] listSchedules
    - [ ] scheduleList
    - [ ] updateSchedule
    - [ ] executeSchedule
    - [ ] scheduleUpdated
    - [ ] fileTransferStart
    - [ ] fileChunk
    - [ ] fileTransferProgress
    - [ ] fileTransferComplete
    - [ ] fileTransferError
    - [ ] fileAck
    - [ ] metricsRequest
    - [ ] metricsResponse
    - [ ] heartbeat
    - [ ] disconnect
    - [ ] error
- [ ] Criar arquivo `lib/infrastructure/protocol/message.dart`
  - [ ] Class `MessageHeader`:
    - [ ] Magic number (4 bytes): `0xFA000000`
    - [ ] Version (1 byte): `0x01`
    - [ ] Length (4 bytes): payload length
    - [ ] Type (1 byte): MessageType
    - [ ] RequestID (4 bytes): unique ID
    - [ ] Flags (3 bytes): reserved
    - [ ] Reserved (7 bytes): future use
  - [ ] Class `Message`:
    - [ ] header: MessageHeader
    - [ ] payload: Map<String, dynamic>
    - [ ] checksum: uint32 (CRC32)
  - [ ] Constructor from JSON
  - [ ] Method `toJson()`
  - [ ] Method `validate()`: valida checksum
- [ ] Criar testes unitários `test/infrastructure/protocol/message_test.dart`
  - [ ] Teste serialização/deserialização
  - [ ] Teste validação de checksum
  - [ ] Teste boundary conditions

#### 1.1.2 Serialização Binária
- [ ] Criar arquivo `lib/infrastructure/protocol/binary_protocol.dart`
  - [ ] Class `BinaryProtocol`
  - [ ] Method `serializeMessage(Message message)`: Uint8List
    - [ ] Serializar header (16 bytes fixos)
    - [ ] Serializar payload (JSON → bytes)
    - [ ] Calcular CRC32 do payload
    - [ ] Montar mensagem completa
  - [ ] Method `deserializeMessage(Uint8List data)`: Message
    - [ ] Validar magic number
    - [ ] Validar version
    - [ ] Ler header
    - [ ] Ler payload
    - [ ] Validar checksum
    - [ ] Retornar Message object
  - [ ] Method `calculateChecksum(Uint8List data)`: String (CRC32)
    - [ ] Implementar CRC32 algorithm
  - [ ] Method `validateChecksum(Uint8List data, String checksum)`: bool
- [ ] Criar testes unitários `test/infrastructure/protocol/binary_protocol_test.dart`
  - [ ] Teste serialização de todos os message types
  - [ ] Teste deserialização com dados inválidos
  - [ ] Teste checksum calculation
  - [ ] Performance test (serializar 1000 mensagens)

#### 1.1.3 Compressão de Payload
- [ ] Criar arquivo `lib/infrastructure/protocol/compression.dart`
  - [ ] Class `PayloadCompression`
  - [ ] Method `compress(Uint8List data)`: Uint8List
    - [ ] Usar `dart:convert` + `zlib`
    - [ ] Nível de compressão: 6 (default)
  - [ ] Method `decompress(Uint8List data)`: Uint8List
  - [ ] Method `shouldCompress(int size)`: bool
    - [ ] Comprimir se > 1KB
- [ ] Atualizar `BinaryProtocol` para usar compressão
  - [ ] Flag `compressed` no header
  - [ ] Comprimir payload antes de enviar
  - [ ] Descomprimir ao receber
- [ ] Criar testes unitários `test/infrastructure/protocol/compression_test.dart`
  - [ ] Teste compressão/descompressão
  - [ ] Teste taxa de compressão
  - [ ] Performance test

#### 1.1.4 File Chunking
- [ ] Criar arquivo `lib/infrastructure/protocol/file_chunker.dart`
  - [ ] Class `FileChunk`
    - [ ] chunkIndex: int
    - [ ] totalChunks: int
    - [ ] data: Uint8List (1MB)
    - [ ] checksum: String (CRC32 do chunk)
    - [ ] Method `toJson()`
    - [ ] Constructor `fromJson()`
  - [ ] Class `FileChunker`
    - [ ] Method `chunkFile(String filePath, int chunkSize)`: List<FileChunk>
      - [ ] Abrir arquivo
      - [ ] Ler em chunks de 1MB
      - [ ] Calcular checksum de cada chunk
      - [ ] Retornar lista de FileChunk
    - [ ] Method `assembleChunks(List<FileChunk> chunks, String outputPath)`: Future<void>
      - [ ] Validar checksum de cada chunk
      - [ ] Escrever chunks em ordem
      - [ ] Validar checksum final do arquivo
      - [ ] Fechar arquivo
- [ ] Criar testes unitários `test/infrastructure/protocol/file_chunker_test.dart`
  - [ ] Teste chunking de arquivo pequeno (<1MB)
  - [ ] Teste chunking de arquivo grande (>10MB)
  - [ ] Teste assembly de chunks
  - [ ] Teste validação de checksum
  - [ ] Teste chunk faltando (erro)

---

### 1.2 Socket Server

#### 1.2.1 Implementação Base do Server
- [ ] Criar pasta `lib/infrastructure/socket/server/`
- [ ] Criar interface `lib/domain/services/i_socket_server_service.dart`
  - [ ] Abstract class `ISocketServerService`
    - [ ] `Future<void> start({int port = 9527})`
    - [ ] `Future<void> stop()`
    - [ ] `Future<void> restart()`
    - [ ] `bool get isRunning`
    - [ ] `int get port`
    - [ ] `Stream<Message> get messageStream`
    - [ ] `Future<List<ConnectedClient>> getConnectedClients()`
    - [ ] `Future<void> disconnectClient(String clientId)`
    - [ ] `Future<void> broadcastToAll(Message message)`
    - [ ] `Future<void> sendToClient(String clientId, Message message)`
    - [ ] `Future<bool> authenticateClient(String serverId, String password)`
- [ ] Criar implementação `lib/infrastructure/socket/server/tcp_socket_server.dart`
  - [ ] Class `TcpSocketServer` implements `ISocketServerService`
    - [ ] ServerSocket? _serverSocket
    - [ ] int _port = 9527
    - [ ] bool _isRunning = false
    - [ ] final Map<String, Socket> _clients = {}
    - [ ] final StreamController<Message> _messageController
  - [ ] Method `start({int port = 9527})`
    - [ ] Validar se não está rodando
    - [ ] Criar ServerSocket.bind(host, port)
    - [ ] Escutar conexões: `server.listen()`
    - [ ] Para cada conexão, criar `ClientHandler`
    - [ ] Set `_isRunning = true`
    - [ ] Log: "Socket Server started on port $port"
  - [ ] Method `stop()`
    - [ ] Desconectar todos os clientes
    - [ ] Fechar ServerSocket
    - [ ] Set `_isRunning = false`
    - [ ] Log: "Socket Server stopped"
  - [ ] Method `restart()`
    - [ ] Chamar `stop()`
    - [ ] Aguardar 1 segundo
    - [ ] Chamar `start(port)`
  - [ ] Method `sendToClient(String clientId, Message message)`
    - [ ] Buscar Socket do cliente
    - [ ] Serializar mensagem
    - [ ] Enviar via socket.add()
    - [ ] Tratar erros
- [ ] Criar testes `test/infrastructure/socket/server/tcp_socket_server_test.dart`
  - [ ] Teste start/stop
  - [ ] Teste múltiplas conexões
  - [ ] Teste envio de mensagem

#### 1.2.2 Client Handler
- [ ] Criar `lib/infrastructure/socket/server/client_handler.dart`
  - [ ] Class `ClientHandler`
    - [ ] final Socket _socket
    - [ ] final String _clientId
    - [ ] final StreamController<Message> _messageController
    - [ ] bool _isAuthenticated = false
    - [ ] ConnectedClient? _clientInfo
  - [ ] Constructor `ClientHandler(Socket socket)`
    - [ ] Gerar UUID único para clientId
    - [ ] Configurar streams
  - [ ] Method `handleConnection()`
    - [ ] Escutar socket: `socket.listen()`
    - [ ] Buffer para receber dados completos
    - [ ] Deserializar mensagem
    - [ ] Emitir no stream
    - [ ] Tratar erros de conexão
  - [ ] Method `send(Message message)`
    - [ ] Serializar mensagem
    - [ ] socket.add(data)
    - [ ] Tratar erros
  - [ ] Method `disconnect()`
    - [ ] Fechar socket
    - [ ] Fechar stream controller
    - [ ] Limpar recursos
  - [ ] Getter `isAuthenticated`: bool
  - [ ] Setter `authenticated(bool value)`
  - [ ] Getter `clientInfo`: ConnectedClient?
  - [ ] Setter `clientInfo(ConnectedClient info)`
- [ ] Criar testes `test/infrastructure/socket/server/client_handler_test.dart`
  - [ ] Teste autenticação
  - [ ] Teste recebimento de mensagem
  - [ ] Teste envio de mensagem
  - [ ] Teste desconexão

#### 1.2.3 Autenticação de Clientes
- [ ] Criar `lib/infrastructure/socket/server/server_authentication.dart`
  - [ ] Class `ServerAuthentication`
    - [ ] final IServerCredentialRepository _repository
  - [ ] Method `authenticateClient(String serverId, String password)`: Future<bool>
    - [ ] Buscar credenciais no repositório
    - [ ] Comparar hash SHA-256 da senha
    - [ ] Retornar true se válido
    - [ ] Log tentativas (sucesso/falha)
  - [ ] Method `validateAuthRequest(Message message)`: Future<bool>
    - [ ] Extrair serverId e passwordHash do payload
    - [ ] Chamar `authenticateClient()`
    - [ ] Retornar resultado
- [ ] Criar credencial default para testes
  - [ ] Server ID: `test-server-123`
  - [ ] Password: `test-password`
  - [ ] Hash: SHA-256

#### 1.2.4 Gerenciamento de Clientes
- [ ] Criar `lib/infrastructure/socket/server/client_manager.dart`
  - [ ] Class `ClientManager`
    - [ ] final Map<String, ClientHandler> _handlers = {}
  - [ ] Method `registerClient(ClientHandler handler)`
    - [ ] Adicionar ao map
    - [ ] Log: "Client connected: ${handler.clientId}"
  - [ ] Method `unregisterClient(String clientId)`
    - [ ] Remover do map
    - [ ] Chamar `handler.disconnect()`
    - [ ] Log: "Client disconnected: $clientId"
  - [ ] Method `getHandler(String clientId)`: ClientHandler?
    - [ ] Buscar no map
  - [ ] Method `getAllHandlers()`: List<ClientHandler>
    - [ ] Retornar valores do map
  - [ ] Method `broadcast(Message message)`
    - [ ] Enviar para todos os handlers
    - [ ] Tratar erros individuais
  - [ ] Method `getConnectedClients()`: List<ConnectedClient>
    - [ ] Mapear handlers para ConnectedClient
  - [ ] Method `disconnectClient(String clientId)`
    - [ ] Buscar handler
    - [ ] Chamar `handler.disconnect()`
    - [ ] Remover do map

---

### 1.3 Socket Client

#### 1.3.1 Implementação Base do Client
- [ ] Criar pasta `lib/infrastructure/socket/client/`
- [ ] Criar interface `lib/domain/services/i_socket_client_service.dart`
  - [ ] Abstract class `ISocketClientService`
    - [ ] `Future<Result<void>> connect({required String host, required int port, required String serverId, required String password})`
    - [ ] `Future<void> disconnect()`
    - [ ] `bool get isConnected`
    - [ ] `ConnectionStatus get status`
    - [ ] `Stream<Message> get messageStream`
    - [ ] `Future<Result<List<RemoteScheduleControl>>> listSchedules()`
    - [ ] `Future<Result<void>> updateSchedule({...})`
    - [ ] `Future<Result<void>> executeSchedule(String scheduleId)`
    - [ ] `Future<Result<DashboardMetrics>> getServerMetrics()`
    - [ ] `Stream<FileTransferProgress> receiveFile({...})`
- [ ] Criar implementação `lib/infrastructure/socket/client/tcp_socket_client.dart`
  - [ ] Class `TcpSocketClient` implements `ISocketClientService`
    - [ ] Socket? _socket
    - [ ] ConnectionStatus _status = ConnectionStatus.disconnected
    - [ ] final StreamController<Message> _messageController
    - [ ] String? _currentServerId
  - [ ] Method `connect({required host, required port, required serverId, required password})`
    - [ ] Validar estado (desconectado)
    - [ ] Set `_status = ConnectionStatus.connecting`
    - [ ] Socket.connect(host, port)
    - [ ] Enviar authRequest
    - [ ] Aguardar authResponse (timeout 30s)
    - [ ] Validar autenticação
    - [ ] Set `_status = ConnectionStatus.connected`
    - [ ] Iniciar listener de mensagens
    - [ ] Log: "Connected to server $serverId"
  - [ ] Method `disconnect()`
    - [ ] Enviar disconnect message
    - [ ] Fechar socket
    - [ ] Set `_status = ConnectionStatus.disconnected`
    - [ ] Log: "Disconnected from server"
  - [ ] Method `send(Message message)`
    - [ ] Validar conexão
    - [ ] Serializar mensagem
    - [ ] socket.add(data)
    - [ ] Tratar erros
- [ ] Criar testes `test/infrastructure/socket/client/tcp_socket_client_test.dart`
  - [ ] Teste connect/disconnect
  - [ ] Teste autenticação com credenciais inválidas
  - [ ] Teste envio de mensagem
  - [ ] Teste timeout de conexão

#### 1.3.2 Connection Manager
- [ ] Criar `lib/infrastructure/socket/client/connection_manager.dart`
  - [ ] Class `ConnectionManager`
    - [ ] final List<ServerConnection> _savedConnections = []
    - [ ] ServerConnection? _activeConnection
    - [ ] TcpSocketClient? _client
  - [ ] Method `connectToSavedConnection(String connectionId)`: Future<Result<void>>
    - [ ] Buscar conexão salva
    - [ ] Criar TcpSocketClient
    - [ ] Conectar
    - [ ] Set `_activeConnection`
  - [ ] Method `connectToNew({...})`: Future<Result<void>>
    - [ ] Criar nova ServerConnection
    - [ ] Salvar no repositório
    - [ ] Conectar
  - [ ] Method `disconnectActive()`: Future<void>
    - [ ] Desconectar _client
    - [ ] Set `_activeConnection = null`
  - [ ] Method `getSavedConnections()`: List<ServerConnection>
    - [ ] Retornar do repositório
  - [ ] Method `getActiveConnection()`: ServerConnection?
    - [ ] Retornar `_activeConnection`
- [ ] Criar testes `test/infrastructure/socket/client/connection_manager_test.dart`
  - [ ] Teste salvar e conectar
  - [ ] Teste múltiplas conexões salvas
  - [ ] Teste disconnect

#### 1.3.3 Auto-Reconnect
- [ ] Adicionar em `TcpSocketClient`
  - [ ] Timer? _reconnectTimer
  - [ ] int _reconnectAttempts = 0
  - [ ] final int _maxReconnectAttempts = 5
  - [ ] Method `_scheduleReconnect()`
    - [ ] Calcular backoff exponencial: 2^attempts segundos
    - [ ] Agendar reconexão
    - [ ] Log: "Scheduling reconnect in ${delay}s"
  - [ ] Method `_attemptReconnect()`
    - [ ] Validar max attempts
    - [ ] Incrementar `_reconnectAttempts`
    - [ ] Tentar conectar com credenciais salvas
    - [ ] Se sucesso, resetar attempts
    - [ ] Se falha, agendar próxima tentativa
- [ ] Criar testes
  - [ ] Teste reconnect após desconexão
  - [ ] Teste max attempts
  - [ ] Teste backoff exponencial

---

### 1.4 Heartbeat e Monitoramento

#### 1.4.1 Heartbeat (Bidirectional)
- [ ] Criar `lib/infrastructure/socket/heartbeat.dart`
  - [ ] Class `HeartbeatManager`
    - [ ] Timer? _heartbeatTimer
    - [ ] Duration _heartbeatInterval = 30 seconds
    - [ ] Duration _heartbeatTimeout = 60 seconds
    - [ ] DateTime? _lastHeartbeatReceived
  - [ ] Method `startHeartbeat(Socket socket)`
    - [ ] Iniciar timer periódico
    - [ ] Enviar heartbeat message a cada 30s
    - [ ] Log heartbeat sent
  - [ ] Method `stopHeartbeat()`
    - [ ] Cancelar timer
  - [ ] Method `onHeartbeatReceived()`
    - [ ] Atualizar `_lastHeartbeatReceived`
    - [ ] Log heartbeat received
  - [ ] Method `checkTimeout()`: bool
    - [ ] Validar se `_lastHeartbeatReceived` > timeout
    - [ ] Retornar true se timeout
- [ ] Integrar no Server (ClientHandler)
  - [ ] Iniciar heartbeat quando cliente autenticado
  - [ ] Responder heartbeat recebido
  - [ ] Desconectar se timeout
- [ ] Integrar no Client (TcpSocketClient)
  - [ ] Iniciar heartbeat quando conectado
  - [ ] Responder heartbeat recebido
  - [ ] Desconectar se timeout (reconnect)
- [ ] Criar testes
  - [ ] Teste heartbeat exchange
  - [ ] Teste timeout detection
  - [ ] Teste reconnect após timeout

---

### 1.5 Logging Estruturado

- [ ] Adicionar logs em todos os pontos críticos
  - [ ] Server start/stop
  - [ ] Client connect/disconnect
  - [ ] Auth success/failure
  - [ ] Message sent/received (debug level)
  - [ ] Errors com stack trace
  - [ ] Heartbeat events
- [ ] Usar `LoggerService` existente
- [ ] Configurar diferentes níveis por ambiente

---

### 1.6 Testes de Integração Iniciais

- [ ] Criar `test/integration/socket_integration_test.dart`
  - [ ] Teste: Server start → Client connect → Auth → Heartbeat → Disconnect
  - [ ] Teste: Múltiplos clientes conectados
  - [ ] Teste: Server para → Client reconnect → Success
  - [ ] Teste: Message roundtrip (Client → Server → Client)
  - [ ] Teste: Large message (>1MB payload)

---

## ✅ FASE 1 - Critérios de Aceitação (Revisão)

- [ ] Server pode aceitar conexões TCP na porta 9527
- [ ] Client pode conectar ao Server via Socket
- [ ] Autenticação básica funciona (Server ID + Password)
- [ ] Heartbeat/ping-pong funciona
- [ ] Mensagens podem ser enviadas e recebidas
- [ ] Testes unitários passando
- [ ] Zero memory leaks

---

## Observações FASE 1

<!-- Espaço para notas durante implementação -->

---

## 🔑 FASE 2: Autenticação e Gerenciamento de Conexões (Semana 3)

### Objetivo
Sistema robusto de autenticação e gerenciamento de conexões

### Critérios de Aceitação
- [ ] Server tem credenciais configuráveis via UI
- [ ] Client salva e gerencia múltiplas conexões
- [ ] Server monitora clientes conectados em tempo real
- [ ] Histórico de conexões no Server
- [ ] Validação de credenciais com SHA-256

---

### 2.1 Autenticação no Servidor

#### 2.1.1 Entity e Repository - Server Credential
- [ ] Criar entity `lib/domain/entities/server_credential.dart`
  - [ ] Class `ServerCredential`
    - [ ] id: String (UUID)
    - [ ] serverId: String (único, configurável)
    - [ ] passwordHash: String (SHA-256)
    - [ ] createdAt: DateTime
    - [ ] isActive: bool
    - [ ] lastUsedAt: DateTime?
- [ ] Criar DAO `lib/infrastructure/datasources/daos/server_credential_dao.dart`
  - [ ] Table `server_credentials`
  - [ ] Methods: getAll, getById, save, update, delete
- [ ] Criar repository interface `lib/domain/repositories/i_server_credential_repository.dart`
- [ ] Criar repository implementation `lib/infrastructure/repositories/server_credential_repository.dart`
- [ ] Registrar no DI `lib/core/di/service_locator.dart`
- [ ] Criar testes unitários

#### 2.1.2 Tela de Configuração de Credenciais (Server)
- [ ] Criar `lib/presentation/pages/server_settings_page.dart`
  - [ ] FluentUI Page comtabs:
    - [ ] Tab 1: Credenciais de Acesso
    - [ ] Tab 2: Clientes Conectados
  - [ ] Listar credenciais existentes
  - [ ] Botão "Nova Credencial"
- [ ] Criar dialog `lib/presentation/widgets/server/server_credential_dialog.dart`
  - [ ] TextField: Server ID (obrigatório, único)
  - [ ] TextField: Password (obrigatório, com confirmação)
  - [ ] Switch: Ativo/Inativo
  - [ ] Botão "Gerar Password Aleatório"
  - [ ] Validações:
    - [ ] Server ID único
    - [ ] Password mínimo 8 caracteres
    - [ ] Passwords conferem
- [ ] Criar Provider `lib/application/providers/server_credential_provider.dart`
  - [ ] loadCredentials()
  - [ ] createCredential(ServerCredential)
  - [ ] updateCredential(ServerCredential)
  - [ ] deleteCredential(String id)
  - [ ] validatePassword(String password) → String hash
- [ ] Integrar com `ServerAuthentication`
- [ ] Criar testes de widget

#### 2.1.3 Validação e Hash de Senha
- [ ] Criar `lib/core/security/password_hasher.dart`
  - [ ] Class `PasswordHasher`
  - [ ] Method `hashPassword(String password)`: String
    - [ ] Usar `crypto` package
    - [ ] SHA-256 + salt (serverId)
  - [ ] Method `verifyPassword(String password, String hash, String serverId)`: bool
- [ ] Atualizar `ServerAuthentication` para usar `PasswordHasher`
- [ ] Adicionar testes de segurança

#### 2.1.4 Gerar Credencial Default na Instalação
- [ ] Criar `lib/application/services/initial_setup_service.dart`
  - [ ] Method `createDefaultCredentialIfNotExists()`
    - [ ] Gerar Server ID aleatório
    - [ ] Gerar Password aleatória
    - [ ] Salvar no banco
    - [ ] Mostrar para usuário na primeira execução
- [ ] Chamar no `main.dart` (modo server)

---

### 2.2 Gerenciamento de Conexões (Client)

#### 2.2.1 Entity e Repository - Server Connection
- [ ] Criar entity `lib/domain/entities/server_connection.dart`
  - [ ] Class `ServerConnection`
    - [ ] id: String (UUID local)
    - [ ] name: String (nome personalizável, ex: "Servidor Produção")
    - [ ] serverId: String (ID do servidor para autenticação)
    - [ ] host: String (IP ou hostname)
    - [ ] port: int (default 9527)
    - [ ] password: String (senha do servidor, armazenada de forma segura)
    - [ ] lastConnectedAt: DateTime?
    - [ ] createdAt: DateTime
    - [ ] isOnline: bool
- [ ] Criar DAO `lib/infrastructure/datasources/daos/server_connection_dao.dart`
  - [ ] Table `server_connections`
  - [ ] Methods: getAll, getById, save, update, delete
- [ ] Criar repository interface `lib/domain/repositories/i_server_connection_repository.dart`
- [ ] Criar repository implementation `lib/infrastructure/repositories/server_connection_repository.dart`
- [ ] Registrar no DI
- [ ] Criar testes unitários

#### 2.2.2 Tela de Login do Client
- [ ] Criar `lib/presentation/pages/server_login_page.dart`
  - [ ] Layout FluentUI:
    - [ ] Lista de servidores salvos (cards)
    - [ ] Botão "Adicionar Servidor"
    - [ ] Botão "Conectar" em cada card
  - [ ] Indicador de status (online/offline)
- [ ] Criar dialog `lib/presentation/widgets/server/connection_dialog.dart`
  - [ ] TextField: Nome da Conexão (ex: "Servidor Produção")
  - [ ] TextField: Host/IP
  - [ ] TextField: Porta (default 9527)
  - [ ] TextField: Server ID
  - [ ] TextField: Password
  - [ ] Checkbox: Salvar conexão
  - [ ] Botão "Testar Conexão"
  - [ ] Validações
- [ ] Criar Provider `lib/application/providers/server_connection_provider.dart`
  - [ ] loadConnections()
  - [ ] saveConnection(ServerConnection)
  - [ ] updateConnection(ServerConnection)
  - [ ] deleteConnection(String id)
  - [ ] connectTo(String connectionId)
  - [ ] disconnect()
  - [ ] testConnection(ServerConnection)
- [ ] Integrar com `ConnectionManager`
- [ ] Criar testes de widget

#### 2.2.3 Lista de Servidores Salvos
- [ ] Widget `lib/presentation/widgets/server/server_list_item.dart`
  - [ ] Card com:
    - [ ] Nome da conexão
    - [ ] Host:Porta
    - [ ] Server ID
    - [ ] Status (online/offline)
    - [ ] Última conexão
    - [ ] Botões: Editar, Excluir, Conectar
  - [ ] Hover effects
  - [ ] Context menu (botão direito)
- [ ] Ações disponíveis:
  - [ ] Editar configurações
  - [ ] Excluir conexão
  - [ ] Conectar/Desconectar
  - [ ] Duplicar conexão
- [ ] Drag and drop para reordenar

---

### 2.3 Monitoramento de Clientes (Server)

#### 2.3.1 Entity - Connected Client
- [ ] Criar entity `lib/domain/entities/connected_client.dart`
  - [ ] Class `ConnectedClient`
    - [ ] id: String (UUID)
    - [ ] clientId: String (identificador único do client)
    - [ ] clientName: String (nome informado pelo client)
    - [ ] host: String (IP do client)
    - [ ] port: int
    - [ ] connectedAt: DateTime
    - [ ] lastHeartbeat: DateTime
    - [ ] isAuthenticated: bool
    - [ ] monitoredScheduleIds: List<String>

#### 2.3.2 Repository - Connected Client (In-Memory)
- [ ] Criar repository `lib/infrastructure/repositories/connected_client_repository.dart`
  - [ ] In-memory storage (Map<String, ConnectedClient>)
  - [ ] Methods:
    - [ ] addClient(ConnectedClient)
    - [ ] removeClient(String clientId)
    - [ ] getClient(String clientId)
    - [ ] getAllClients()
    - [ ] updateClient(ConnectedClient)
    - [ ] getClientsByServerId(String serverId)
- [ ] Registrar no DI como singleton
- [ ] Criar testes unitários

#### 2.3.3 Tela de Clientes Conectados (Server)
- [ ] Criar widget `lib/presentation/widgets/server/connected_clients_list.dart`
  - [ ] DataTable FluentUI com colunas:
    - [ ] Client Name
    - [ ] IP Address
    - [ ] Connected At
    - [ ] Last Heartbeat
    - [ ] Status
    - [ ] Actions
  - [ ] Atualização em tempo real (Stream/Provider)
  - [ ] Indicador de "Agora" (último heartbeat < 30s)
- [ ] Ações disponíveis:
  - [ ] View Details (dialog com info completa)
  - [ ] Disconnect Client
  - [ ] View Monitored Schedules
- [ ] Criar Provider `lib/application/providers/connected_client_provider.dart`
  - [ ] Stream de clientes conectados
  - [ ] Auto-refresh a cada 5 segundos
  - [ ] Method `disconnectClient(String clientId)`
- [ ] Criar testes de widget

#### 2.3.4 Log de Tentativas de Conexão
- [ ] Criar entity `lib/domain/entities/connection_log.dart`
  - [ ] Class `ConnectionLog`
    - [ ] id: String
    - [ ] clientHost: String
    - [ ] serverId: String? (tentou autenticar com qual ID)
    - [ ] success: bool
    - [ ] errorMessage: String?
    - [ ] timestamp: DateTime
- [ ] Criar repository para logs
- [ ] Salvar toda tentativa de autenticação
- [ ] Tela para visualizar logs (Server Settings)
  - [ ] Filtrar por período
  - [ ] Filtrar por sucesso/falha
  - [ ] Exportar para CSV

---

## ✅ FASE 2 - Critérios de Aceitação (Revisão)

- [ ] Server tem credenciais configuráveis via UI
- [ ] Client salva e gerencia múltiplas conexões
- [ ] Server monitora clientes conectados em tempo real
- [ ] Histórico de conexões no Server
- [ ] Validação de credenciais com SHA-256

---

## Observações FASE 2

<!-- Espaço para notas -->

---

## *Continua nas próximas fases...*

> **NOTA**: Este documento será atualizado conforme as fases são implementadas.
> Cada fase será expandida com o mesmo nível de detalhe da Fase 1 e 2.

---

## Links Rápidos

- [Plano Detalhado](plano_cliente_servidor.md)
- [Anotações Iniciais](anotacoes.txt)
- [Branch no GitHub](https://github.com/cesar-carlos/backup_database/tree/feature/client-server-architecture)

---

**Última Atualização**: 2026-01-XX
**Responsável**: @cesar-carlos
**Status**: 🔄 Em Implementação
