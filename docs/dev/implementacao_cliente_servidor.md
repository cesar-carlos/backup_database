# Implementação Cliente-Servidor - Checklist Detalhado

> **⚠️ IMPORTANTE**: Leia primeiro [README_CONTEXT_ATUAL.md](README_CONTEXT_ATUAL.md) para entender onde estamos no projeto
>
> **Branch**: `feature/client-server-architecture` > **Data de Início**: 2026-01-XX
> **Status**: 🔄 Em Andamento (FASE 0: 85% – plano + teste auto ✅; manuais pendentes | FASE 2.1–2.4 ✅ | FASE 3 ✅ | FASE 4 ✅ | FASE 5.1–5.3 ✅ | FASE 6 ✅ | FASE 7 ✅)
>
> **Documentos Relacionados**:
>
> - [📖 Contexto Atual](README_CONTEXT_ATUAL.md) - **LEIA PRIMEIRO** - Onde estamos, o que fazer
> - [Plano Detalhado](plano_cliente_servidor.md) - Arquitetura e decisões
> - [Anotações Iniciais](anotacoes.txt) - Requisitos originais
> - [UI/UX e Instalação](ui_instalacao_cliente_servidor.md) - Telas, instalador e código compartilhado
> - [Análise Técnica](analise_tecnica_ui_banco_pacotes.md) - Componentes, banco, pacotes

---

## 📋 Decisões Definidas

✅ **Porta default**: 9527
✅ **Tamanho de chunk**: 128KB (131072 bytes)
✅ **Compressão durante transferência**: Sim (zlib)
✅ **TLS/SSL**: Depois (v2)
✅ **Limite de clientes**: Ilimitado

---

## 📊 Progresso Geral

### Fases de Implementação

| Fase | Descrição                    | Semanas | Progresso | Status          |
| ---- | ---------------------------- | ------- | --------- | --------------- |
| 0    | Pré-requisitos              | -       | [x] 11/13 | 🟡 Em Andamento  |
| 1    | Fundamentos Socket           | 1-2     | [x] 26/31 | 🟡 Em Andamento  |
| 2    | Autenticação e Conexões      | 3       | [x] 2.1–2.4 | ✅ Concluído |
| 3    | Protocolo de Controle Remoto | 4       | [x] Agendamentos | ✅ Concluído |
| 4    | Transferência de Arquivos    | 5-6     | [x] Completo | ✅ Concluído |
| 5    | Destinos do Client           | 7       | [x] 5.1–5.3 | ✅ Concluído |
| 6    | Dashboard de Métricas        | 8       | [x] Completo | ✅ Concluído |
| 7    | Installer e Integração       | 9       | [x] Completo | ✅ Concluído |
| 8    | Testes e Documentação        | 10      | [ ] 0/27  | ⏳ Não Iniciado |

**Total**: 201 tarefas + 13 pré-requisitos

### ✅ FASE 0 - Pré-requisitos (11/13 completados - **85%**)

**Completado em**: 01/02/2026
**Commit**: `2dbc725`

#### ✅ Banco de Dados (11/13 - 85%)
- [x] Adicionar pacote `qr_flutter: ^4.1.0`
- [x] Criar `ServerCredentialsTable` (Drift table class)
- [x] Criar `ConnectionLogsTable` (Drift table class)
- [x] Criar `ServerConnectionsTable` (Drift table class)
- [x] Criar `FileTransfersTable` (Drift table class)
- [x] Criar `ServerCredentialDao`
- [x] Criar `ConnectionLogDao`
- [x] Criar `ServerConnectionDao`
- [x] Criar `FileTransferDao`
- [x] Atualizar `AppDatabase` (adicionar tabelas e DAOs)
- [x] Atualizar schemaVersion: 13 → 14
- [x] Criar migration script (v14)
- [x] Plano de testes manuais: [fase0_migration_v14_test_plan.md](fase0_migration_v14_test_plan.md)
- [x] Teste de integração automatizado: `test/integration/database_migration_v14_test.dart` (schema v14, tabelas, leitura/escrita)
- [ ] Testar migration manualmente (com backup do banco)
- [ ] Testar migration com dados existentes

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
- `file_chunker.dart` - Chunking de arquivos (128KB)
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
✅ SocketConfig               // Porta 9527, chunk 128KB, timeouts
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
- [x] Criar `lib/core/constants/socket_config.dart` com configurações
- [ ] Documentar serviços que podem ser reutilizados
- [ ] Mover entidades compartilhadas para pasta correta
- [ ] Atualizar imports em código existente

**Durante FASE 1**:

- [x] Implementar protocol binário como código compartilhado (message_types, message, binary_protocol, crc32)
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
- [x] Zero memory leaks (revisado: timers/streams em ClientHandler, TcpSocketClient, ConnectionManager, HeartbeatManager, TcpSocketServer)

---

### 1.1 Protocolo Binário

#### 1.1.1 Estrutura da Mensagem

- [x] Criar arquivo `lib/infrastructure/protocol/message_types.dart`
  - [x] Enum `MessageType` com 19 tipos:
    - [x] authRequest
    - [x] authResponse
    - [x] authChallenge
    - [x] listSchedules
    - [x] scheduleList
    - [x] updateSchedule
    - [x] executeSchedule
    - [x] scheduleUpdated
    - [x] fileTransferStart
    - [x] fileChunk
    - [x] fileTransferProgress
    - [x] fileTransferComplete
    - [x] fileTransferError
    - [x] fileAck
    - [x] metricsRequest
    - [x] metricsResponse
    - [x] heartbeat
    - [x] disconnect
    - [x] error
- [x] Criar arquivo `lib/infrastructure/protocol/message.dart`
  - [x] Class `MessageHeader`:
    - [x] Magic number (4 bytes): `0xFA000000`
    - [x] Version (1 byte): `0x01`
    - [x] Length (4 bytes): payload length
    - [x] Type (1 byte): MessageType
    - [x] RequestID (4 bytes): unique ID
    - [x] Flags (3 bytes): reserved
    - [x] Reserved (7 bytes): future use
  - [x] Class `Message`:
    - [x] header: MessageHeader
    - [x] payload: Map<String, dynamic>
    - [x] checksum: uint32 (CRC32)
  - [x] Constructor from JSON
  - [x] Method `toJson()`
  - [x] Method `validateChecksum()`: valida checksum
- [x] Criar testes unitários `test/unit/infrastructure/protocol/message_test.dart`
  - [x] Teste serialização/deserialização
  - [x] Teste validação de checksum
  - [x] Teste boundary conditions

#### 1.1.2 Serialização Binária

- [x] Criar arquivo `lib/infrastructure/protocol/binary_protocol.dart`
  - [x] Class `BinaryProtocol`
  - [x] Method `serializeMessage(Message message)`: Uint8List
    - [x] Serializar header (16 bytes fixos)
    - [x] Serializar payload (JSON → bytes)
    - [x] Calcular CRC32 do payload
    - [x] Montar mensagem completa
  - [x] Method `deserializeMessage(Uint8List data)`: Message
    - [x] Validar magic number
    - [x] Validar version
    - [x] Ler header
    - [x] Ler payload
    - [x] Validar checksum
    - [x] Retornar Message object
  - [x] Method `calculateChecksum(Uint8List data)`: int (CRC32)
  - [x] Method `validateChecksum(Uint8List data, int expectedChecksum)`: bool
- [x] Criar testes unitários `test/unit/infrastructure/protocol/binary_protocol_test.dart`
  - [x] Teste serialização de todos os message types
  - [x] Teste deserialização com dados inválidos
  - [x] Teste checksum calculation
  - [ ] Performance test (serializar 1000 mensagens) – opcional

#### 1.1.3 Compressão de Payload

- [x] Criar arquivo `lib/infrastructure/protocol/compression.dart`
  - [x] Class `PayloadCompression`
  - [x] Method `compress(Uint8List data)`: Uint8List
    - [x] Usar `dart:io` ZLibCodec(level: 6)
  - [x] Method `decompress(Uint8List data)`: Uint8List
  - [x] Method `shouldCompress(int size)`: bool (static, > 1KB)
- [x] Atualizar `BinaryProtocol` para usar compressão
  - [x] Flag `compressed` no header (flags[0] & 0x01)
  - [x] Comprimir payload antes de enviar quando shouldCompress
  - [x] Descomprimir ao receber quando flag set
- [x] Criar testes unitários `test/unit/infrastructure/protocol/compression_test.dart`
  - [x] Teste compressão/descompressão (round-trip, tamanho menor para conteúdo repetitivo)
  - [x] Teste shouldCompress (false <= 1024, true > 1024)
  - [ ] Performance test – opcional

#### 1.1.4 File Chunking

- [x] Criar arquivo `lib/infrastructure/protocol/file_chunker.dart`
  - [x] Class `FileChunk`
    - [x] chunkIndex, totalChunks, data (Uint8List), checksum (int CRC32)
    - [x] Method `toJson()` / `fromJson()`
    - [x] getter `isValidChecksum`
  - [x] Class `FileChunker`
    - [x] Method `chunkFile(String filePath, [int? chunkSize])`: Future<List<FileChunk>>
      - [x] Ler arquivo em chunks (default SocketConfig.chunkSize 128KB)
      - [x] Calcular CRC32 de cada chunk
    - [x] Method `assembleChunks(List<FileChunk> chunks, String outputPath)`: Future<void>
      - [x] Validar checksum de cada chunk, escrever em ordem
- [x] Criar testes unitários `test/unit/infrastructure/protocol/file_chunker_test.dart`
  - [x] Teste chunking de arquivo pequeno (< chunkSize)
  - [x] Teste chunkFile + assembleChunks reproduz arquivo
  - [x] Teste default chunkSize
  - [x] Teste validação de checksum (inválido → exceção)
  - [x] Teste chunk faltando (exceção), arquivo inexistente, chunks vazios

---

### 1.2 Socket Server

#### 1.2.1 Implementação Base do Server

- [x] Criar pasta `lib/infrastructure/socket/server/`
- [x] Criar interface `lib/infrastructure/socket/server/socket_server_service.dart`
  - [x] Abstract class `SocketServerService`
    - [x] `Future<void> start({int port = 9527})`
    - [x] `Future<void> stop()`, `restart()`
    - [x] `bool get isRunning`, `int get port`
    - [x] `Stream<Message> get messageStream`
    - [x] `Future<List<ConnectedClient>> getConnectedClients()`
    - [x] `Future<void> disconnectClient(String clientId)`
    - [x] `Future<void> broadcastToAll(Message message)`
    - [x] `Future<void> sendToClient(String clientId, Message message)`
- [x] Criar implementação `lib/infrastructure/socket/server/tcp_socket_server.dart`
  - [x] Class `TcpSocketServer` implements `SocketServerService`
  - [x] Method `start({int port = 9527})` – ServerSocket.bind(anyIPv4, port)
  - [x] Method `stop()`, `restart()`
  - [x] Para cada conexão, criar `ClientHandler`
  - [x] Method `sendToClient`, `broadcastToAll`, `getConnectedClients`, `disconnectClient`
- [x] Criar entity `lib/domain/entities/connection/connected_client.dart`
- [x] Criar testes `test/unit/infrastructure/socket/tcp_socket_server_test.dart`
  - [x] Teste start/stop, porta custom, getConnectedClients vazio, não start duas vezes
  - [x] Teste múltiplas conexões (2 clientes, disconnect um)
  - [x] Teste envio de mensagem (sendToClient → cliente recebe)

#### 1.2.2 Client Handler

- [x] Criar `lib/infrastructure/socket/server/client_handler.dart`
  - [x] Class `ClientHandler` (Socket, BinaryProtocol, onDisconnect)
  - [x] Buffer para receber dados completos, parse header+length+payload+checksum
  - [x] Method `_tryParseMessages()` – deserializar e emitir no stream
  - [x] Method `send(Message message)` – serializar e socket.add/flush
  - [x] Method `disconnect()` – fechar stream, destroy socket, onDisconnect
  - [x] Campos `isAuthenticated`, `clientName`; `toConnectedClient(connectedAt)`
- [x] Criar testes `test/unit/infrastructure/socket/server/client_handler_test.dart`
  - [x] Teste autenticação (sem auth → isAuthenticated; com mock auth → authResponse)
  - [x] Teste recebimento de mensagem (messageStream emite mensagem recebida)
  - [x] Teste envio de mensagem (send serializa e cliente lê)
  - [x] Teste desconexão (onDisconnect chamado, stream fechado)
  - [x] Teste toConnectedClient (campos corretos)

#### 1.2.3 Autenticação de Clientes

- [x] Criar `lib/infrastructure/socket/server/server_authentication.dart`
  - [x] Class `ServerAuthentication`
    - [x] final ServerCredentialDao \_dao
  - [x] Method `validateAuthRequest(Message message)`: Future<bool>
    - [x] Extrair serverId e passwordHash do payload
    - [x] Buscar credenciais no DAO
    - [x] Comparar hash (constantTimeEquals)
    - [x] Retornar resultado, log sucesso/falha
- [ ] Criar credencial default para testes
  - [ ] Server ID: `test-server-123`
  - [ ] Password: `test-password`
  - [ ] Hash: SHA-256 (salt = serverId)

#### 1.2.4 Gerenciamento de Clientes

- [x] Criar `lib/infrastructure/socket/server/client_manager.dart`
  - [x] Class `ClientManager`
    - [x] final Map<String, ClientHandler> \_handlers = {}
    - [x] final Map<String, DateTime> \_connectedAt = {}
  - [x] Method `register(ClientHandler handler, DateTime connectedAt)`
  - [x] Method `unregister(String clientId)`
  - [x] Method `getHandler(String clientId)`: ClientHandler?
  - [x] Method `getHandlers()`: List<ClientHandler>
  - [x] Method `getConnectedClients()`: Future<List<ConnectedClient>>
  - [x] Method `disconnectClient(String clientId)`
  - [x] Method `disconnectAll()`, `clear()`
- [x] Integrar ClientManager opcional em TcpSocketServer (construtor ClientManager?)

---

### 1.3 Socket Client

#### 1.3.1 Implementação Base do Client

- [x] Criar pasta `lib/infrastructure/socket/client/`
- [x] Criar interface `lib/infrastructure/socket/client/socket_client_service.dart`
  - [ ] Abstract class `ISocketClientService`
    - [ ] `Future<Result<void>> connect({required String host, required int port, required String serverId, required String password})`
    - [ ] `Future<void> disconnect()`
    - [ ] `bool get isConnected`
    - [ ] `ConnectionStatus get status`
    - [ ] `Stream<Message> get messageStream`
    - [ ] `Future<Result<List<RemoteScheduleControl>>> listSchedules()`
    - [ ] `Future<Result<void>> updateSchedule({...})`
    - [ ] `Future<Result<void>> executeSchedule(String scheduleId)`
    - [x] `Future<Result<DashboardMetrics>> getServerMetrics()` (FASE 6)
    - [ ] `Stream<FileTransferProgress> receiveFile({...})`
- [x] Criar implementação `lib/infrastructure/socket/client/tcp_socket_client.dart`
  - [x] Class `TcpSocketClient` implements `SocketClientService`
    - [ ] Socket? \_socket
    - [ ] ConnectionStatus \_status = ConnectionStatus.disconnected
    - [ ] final StreamController<Message> \_messageController
    - [ ] String? \_currentServerId
  - [x] Method `connect({required host, required port, serverId?, password?})` – Socket.connect, buffer, parse
  - [x] Method `disconnect()`, `send(Message message)`
  - [x] Auth (authRequest após connect; authResponse → status connected/authenticationFailed)
- [x] Criar testes `test/unit/infrastructure/socket/tcp_socket_client_test.dart`
  - [x] Teste status quando desconectado, disconnect sem throw
  - [x] Teste send quando desconectado (StateError)
  - [x] Teste connect a porta inválida (error status)
  - [x] Teste connect/disconnect com servidor real
  - [x] Teste messageStream recebe mensagem do servidor
  - [ ] Teste autenticação com credenciais inválidas (integração com auth)

#### 1.3.2 Connection Manager

- [x] Criar `lib/infrastructure/socket/client/connection_manager.dart`
  - [x] Class `ConnectionManager` (activeClient, connect(host, port), disconnect, send)
  - [x] connectToSavedConnection(connectionId), getSavedConnections() – opcional ServerConnectionDao no construtor
- [x] Criar testes `test/unit/infrastructure/socket/connection_manager_test.dart`
  - [x] Teste estado inicial (não conectado)
  - [x] Teste connect/disconnect com servidor real
  - [x] Teste send quando conectado (mensagem chega ao servidor)
  - [x] Teste send quando desconectado (StateError)
  - [x] getSavedConnections sem dao (lista vazia), com mock dao (retorna getAll)
  - [x] connectToSavedConnection sem dao (StateError), id inexistente (StateError), id válido (conecta)

#### 1.3.3 Auto-Reconnect

- [x] Adicionar em `TcpSocketClient`
  - [x] Timer? \_reconnectTimer, int \_reconnectAttempts, \_reconnectHost/Port/ServerId/Password
  - [x] connect(..., enableAutoReconnect: bool) – salva params para reconnect
  - [x] Method `_scheduleReconnect()` – backoff 2^attempts segundos, max SocketConfig.maxReconnectAttempts (5)
  - [x] Method `_attemptReconnect()` – incrementa attempts, chama \_doConnect com credenciais salvas
  - [x] \_handleDisconnect(scheduleReconnect) – onDone/timeout chama com true; disconnect() com false
- [x] Criar testes (tcp_socket_client_test)
  - [x] Teste reconnect após server restart (enableAutoReconnect)
  - [x] Teste server para e não volta → cliente fica desconectado
  - [ ] Teste backoff exponencial – opcional (requer tempo longo)

---

### 1.4 Heartbeat e Monitoramento

#### 1.4.1 Heartbeat (Bidirectional)

- [x] Criar `lib/infrastructure/socket/heartbeat.dart`
  - [x] createHeartbeatMessage(), isHeartbeatMessage(Message)
  - [x] Class `HeartbeatManager` (start, stop, onHeartbeatReceived, interval 30s, timeout 60s)
- [x] Integrar no Server (ClientHandler)
  - [x] Iniciar heartbeat em start(), responder heartbeat recebido, onTimeout → disconnect
- [x] Integrar no Client (TcpSocketClient)
  - [x] Iniciar heartbeat em connect(), listen messageStream para heartbeat, onTimeout → disconnect
- [x] Criar testes `test/unit/infrastructure/socket/heartbeat_test.dart`
  - [x] createHeartbeatMessage, isHeartbeatMessage
  - [x] HeartbeatManager start/stop, sendHeartbeat no interval, onHeartbeatReceived
  - [ ] Teste timeout detection (opcional)
  - [ ] Teste reconnect após timeout (integração)

---

### 1.5 Logging Estruturado

- [x] Adicionar logs em todos os pontos críticos
  - [x] Server start/stop
  - [x] Client connect/disconnect
  - [x] Auth success/failure
  - [x] Errors com stack trace
  - [x] Heartbeat timeout (HeartbeatManager)
- [x] Usar `LoggerService` existente
- [ ] Message sent/received (debug level) – opcional
- [ ] Configurar diferentes níveis por ambiente

---

### 1.6 Testes de Integração Iniciais

- [x] Criar `test/integration/socket_integration_test.dart`
  - [x] Teste: Server start → Client connect (no auth) → getConnectedClients → Disconnect
  - [x] Teste: Client receives message from server (sendToClient)
  - [x] Teste: Server broadcastToAll reaches connected client
  - [x] Teste: Auth (credencial correta / senha errada)
  - [x] Teste: Auth então permanece conectado (heartbeat path)
  - [x] Teste: Múltiplos clientes recebem broadcastToAll
  - [x] Teste: Server para → restart → Client com autoReconnect reconecta
  - [ ] Teste: Large message (>1MB payload) – opcional

---

## ✅ FASE 1 - Critérios de Aceitação (Revisão)

- [x] Server pode aceitar conexões TCP na porta 9527
- [x] Client pode conectar ao Server via Socket
- [x] Autenticação básica funciona (Server ID + Password)
- [x] Heartbeat/ping-pong funciona
- [x] Mensagens podem ser enviadas e recebidas
- [x] Testes unitários passando (30+ em protocol, socket, heartbeat, server_authentication)
- [x] Zero memory leaks (revisão: timers/streams cancelados ou fechados em disconnect/stop; TcpSocketServer fecha messageController em stop())

---

## Observações FASE 1

<!-- Espaço para notas durante implementação -->

---

## 🔑 FASE 2: Autenticação e Gerenciamento de Conexões (Semana 3)

### Objetivo

Sistema robusto de autenticação e gerenciamento de conexões

### Critérios de Aceitação

- [x] Server tem credenciais configuráveis via UI
- [x] Client salva e gerencia múltiplas conexões
- [x] Server monitora clientes conectados em tempo real
- [x] Histórico de conexões no Server
- [x] Validação de credenciais com SHA-256

---

### 2.1 Autenticação no Servidor

#### 2.1.1 Entity e Repository - Server Credential

- [x] Criar entity `lib/domain/entities/server_credential.dart`
  - [x] Class `ServerCredential`
    - [x] id: String (UUID)
    - [x] serverId: String (único, configurável)
    - [x] passwordHash: String (SHA-256)
    - [x] createdAt: DateTime
    - [x] isActive: bool
    - [x] lastUsedAt: DateTime?
- [x] Criar DAO `lib/infrastructure/datasources/daos/server_credential_dao.dart`
  - [x] Table `server_credentials`
  - [x] Methods: getAll, getById, save, update, delete
- [x] Criar repository interface `lib/domain/repositories/i_server_credential_repository.dart`
- [x] Criar repository implementation `lib/infrastructure/repositories/server_credential_repository.dart`
- [x] Registrar no DI `lib/core/di/service_locator.dart`
- [x] Criar testes unitários

#### 2.1.2 Tela de Configuração de Credenciais (Server)

- [x] Criar `lib/presentation/pages/server_settings_page.dart`
  - [x] FluentUI Page com tabs:
    - [x] Tab 1: Credenciais de Acesso
    - [x] Tab 2: Clientes Conectados
    - [x] Tab 3: Log de Conexões
  - [x] Listar credenciais existentes
  - [x] Botão "Nova Credencial"
- [x] Criar dialog `lib/presentation/widgets/server/server_credential_dialog.dart`
  - [x] TextField: Server ID (obrigatório, único)
  - [x] TextField: Password (obrigatório, com confirmação)
  - [x] Switch: Ativo/Inativo
  - [x] Botão "Gerar Password Aleatório"
  - [x] Validações:
    - [x] Server ID único
    - [x] Password mínimo 8 caracteres
    - [x] Passwords conferem
- [x] Criar Provider `lib/application/providers/server_credential_provider.dart`
  - [x] loadCredentials()
  - [x] createCredential(ServerCredential)
  - [x] updateCredential(ServerCredential)
  - [x] deleteCredential(String id)
  - [x] validatePassword(String password) → String hash
- [x] Integrar com `ServerAuthentication`
- [ ] Criar testes de widget

#### 2.1.3 Validação e Hash de Senha

- [x] Criar `lib/core/security/password_hasher.dart`
  - [x] Class `PasswordHasher`
  - [x] Method `hashPassword(String password)` / hash(plainPassword, serverId)
  - [x] Method `verifyPassword(String password, String hash, String serverId)`: bool
- [x] Atualizar `ServerAuthentication` para usar `PasswordHasher`
- [ ] Adicionar testes de segurança

#### 2.1.4 Gerar Credencial Default na Instalação

- [x] Criar `lib/application/services/initial_setup_service.dart`
  - [x] Method `createDefaultCredentialIfNotExists()`
    - [x] Gerar Server ID aleatório
    - [x] Gerar Password aleatória
    - [x] Salvar no banco
    - [ ] Mostrar para usuário na primeira execução (opcional)
- [x] Chamar no bootstrap (`AppInitializer._initializeDefaultCredential()` após `_setupDependencies()`)

---

### 2.2 Gerenciamento de Conexões (Client)

#### 2.2.1 Entity e Repository - Server Connection

- [x] Criar entity `lib/domain/entities/server_connection.dart`
  - [x] Class `ServerConnection`
    - [x] id: String (UUID local)
    - [x] name: String (nome personalizável)
    - [x] serverId: String (ID do servidor para autenticação)
    - [x] host: String (IP ou hostname)
    - [x] port: int (default 9527)
    - [x] password: String (senha do servidor)
    - [x] lastConnectedAt: DateTime?
    - [x] createdAt: DateTime, updatedAt
    - [x] isOnline: bool
- [x] Criar DAO `lib/infrastructure/datasources/daos/server_connection_dao.dart`
  - [x] Table `server_connections`
  - [x] Methods: getAll, getById, save, update, delete, watchAll
- [x] Criar repository interface `lib/domain/repositories/i_server_connection_repository.dart`
- [x] Criar repository implementation `lib/infrastructure/repositories/server_connection_repository.dart`
- [x] Registrar no DI
- [x] Criar testes unitários

#### 2.2.2 Tela de Login do Client

- [x] Criar `lib/presentation/pages/server_login_page.dart`
  - [x] Layout FluentUI:
    - [x] Lista de servidores salvos (cards)
    - [x] Botão "Adicionar Servidor"
    - [x] Botão "Conectar" em cada card
  - [x] Indicador de status (online/offline/conectando)
- [x] Criar dialog `lib/presentation/widgets/client/connection_dialog.dart`
  - [x] TextField: Nome da Conexão
  - [x] TextField: Host/IP
  - [x] TextField: Porta (default 9527)
  - [x] TextField: Server ID
  - [x] TextField: Password
  - [x] Botão "Testar Conexão"
  - [x] Validações
- [x] Criar Provider `lib/application/providers/server_connection_provider.dart`
  - [x] loadConnections()
  - [x] saveConnection / updateConnection / deleteConnection
  - [x] connectTo(String connectionId)
  - [x] disconnect()
  - [x] testConnection(ServerConnection)
- [x] Integrar com `ConnectionManager` (ServerConnectionDao no DI)
- [ ] Criar testes de widget

#### 2.2.3 Lista de Servidores Salvos

- [x] Widget `lib/presentation/widgets/client/server_list_item.dart`
  - [x] Card com:
    - [x] Nome da conexão
    - [x] Host:Porta
    - [x] Server ID
    - [x] Status (Conectado/Offline/Conectando)
    - [x] Botões: Testar, Conectar/Desconectar, Editar, Excluir
  - [x] Hover effects
- [x] Ações disponíveis:
  - [x] Editar configurações
  - [x] Excluir conexão
  - [x] Conectar/Desconectar
  - [ ] Duplicar conexão (não implementado)
- [ ] Drag and drop para reordenar (não implementado)

---

### 2.3 Monitoramento de Clientes (Server)

#### 2.3.1 Entity - Connected Client

- [x] Criar entity `lib/domain/entities/connection/connected_client.dart`
  - [x] Class `ConnectedClient`
    - [x] id: String (clientId)
    - [x] clientId: String
    - [x] clientName: String
    - [x] host: String
    - [x] port: int
    - [x] connectedAt: DateTime
    - [x] lastHeartbeat: DateTime?
    - [x] isAuthenticated: bool
    - [ ] monitoredScheduleIds: List<String> (FASE 3)

#### 2.3.2 Repository - Connected Client (In-Memory)

- [x] Usar `ClientManager` em `TcpSocketServer` (getConnectedClients, register/unregister, disconnectClient)
- [x] Registrar no DI (ClientManager, TcpSocketServer, SocketServerService)
- [ ] Repository separado para persistência (não necessário; estado em memória no ClientManager)

#### 2.3.3 Tela de Clientes Conectados (Server)

- [x] Criar widget `lib/presentation/widgets/server/connected_clients_list.dart`
  - [x] Lista com: Client Name/ID, Host:Port, Connected At, Last Heartbeat, Status (Autenticado/Não autenticado)
  - [x] Atualização via Provider (polling 5s)
  - [x] Iniciar/Parar servidor, Atualizar
- [x] Ações disponíveis:
  - [x] Disconnect Client
  - [ ] View Details / View Monitored Schedules (FASE 3)
- [x] Criar Provider `lib/application/providers/connected_client_provider.dart`
  - [x] refresh() (polling 5s)
  - [x] disconnectClient(String clientId)
  - [x] startServer() / stopServer()
- [ ] Criar testes de widget

#### 2.3.4 Log de Tentativas de Conexão (2.4)

- [x] Criar entity `lib/domain/entities/connection_log.dart`
  - [x] Class `ConnectionLog`
    - [x] id: String
    - [x] clientHost: String
    - [x] serverId: String?
    - [x] success: bool
    - [x] errorMessage: String?
    - [x] timestamp: DateTime
    - [x] clientId: String?
- [x] Criar `IConnectionLogRepository` + `ConnectionLogRepository` (getAll, getRecentLogs, watchAll)
- [x] `ConnectionLogDao.insertConnectionAttempt()`; ClientHandler grava tentativas de auth (sucesso/falha)
- [x] Tela para visualizar logs: aba **Log de Conexões** em Server Settings
  - [x] Filtrar por Todos / Sucesso / Falha
  - [x] Lista com clientHost, serverId, timestamp, status, errorMessage
  - [ ] Filtrar por período (não implementado)
  - [ ] Exportar para CSV (não implementado)

---

## ✅ FASE 2 - Critérios de Aceitação (Revisão)

- [x] Server tem credenciais configuráveis via UI
- [x] Client salva e gerencia múltiplas conexões
- [x] Server monitora clientes conectados em tempo real
- [x] Histórico de conexões no Server
- [x] Validação de credenciais com SHA-256

---

## Observações FASE 2

- FASE 2.1–2.4 concluídas em 01/02/2026.
- FASE 4, 5, 6 e 7 já concluídas. FASE 0: plano + teste auto criados; testes manuais pendentes.

---

## ✅ FASE 3: Protocolo de Controle Remoto – Agendamentos (Concluída)

**Completado em**: 01/02/2026

### Objetivo

Permitir que o cliente liste, atualize e execute agendamentos no servidor via socket.

### Implementado

- [x] **Protocolo compartilhado** (`lib/infrastructure/protocol/`)
  - [x] `schedule_serialization.dart`: `scheduleToMap()`, `scheduleFromMap()` (Schedule ↔ Map, enums por nome, DateTime ISO8601)
  - [x] `schedule_messages.dart`: criação e parse de mensagens listSchedules, scheduleList, updateSchedule, scheduleUpdated, executeSchedule, error (com requestId)
- [x] **Servidor**
  - [x] `ScheduleMessageHandler`: processa listSchedules, updateSchedule, executeSchedule (IScheduleRepository, UpdateSchedule, ExecuteScheduledBackup); envia respostas ao cliente
  - [x] `TcpSocketServer`: injeta ScheduleMessageHandler e delega mensagens de agendamento
  - [x] Registro no DI
- [x] **Cliente**
  - [x] `ConnectionManager`: requestId + Completer para parear requisição/resposta; `listSchedules()`, `updateSchedule(Schedule)`, `executeSchedule(String scheduleId)`; timeout e tratamento de erro
- [x] **UI**
  - [x] `RemoteSchedulesProvider`: estado dos agendamentos remotos, chamadas ao ConnectionManager
  - [x] `RemoteSchedulesPage`: lista agendamentos do servidor, atualizar, ativar/desativar, executar agora
  - [x] Rota `/remote-schedules`, item "Agendamentos Remotos" no MainLayout (FluentIcons.calendar_agenda)
  - [x] Provider e rota registrados no DI e app_widget

### Pendente (FASE 3 – opcional ou FASE 4+)

- [ ] Testes unitários/integração para ScheduleMessageHandler e fluxo listSchedules/updateSchedule/executeSchedule
- [x] Métricas remotas (metricsRequest/metricsResponse) – implementado na FASE 6

---

## ✅ FASE 4: Transferência de Arquivos (Concluída)

**Concluída em**: 01/02/2026

### Objetivo

Transmitir arquivos de backup do servidor para o cliente via socket (fileTransferStart → fileChunk → fileTransferComplete).

### Implementado

- [x] **Protocolo compartilhado** (`lib/infrastructure/protocol/file_transfer_messages.dart`)
  - [x] fileTransferStart (request: filePath, scheduleId?); fileTransferStart (metadata: fileName, fileSize, totalChunks)
  - [x] fileChunk (FileChunk.toJson), fileTransferProgress, fileTransferComplete, fileTransferError, fileAck
  - [x] listFiles / fileList (listagem de arquivos sob allowedBasePath; payload: files com path, size, lastModified)
  - [x] Funções create/parse e predicados (isFileTransferStartRequest, isFileTransferStartMetadata, getFileChunkFromPayload, isListFilesRequest, isFileListMessage, getFileListFromPayload, etc.)
- [x] **Servidor**
  - [x] `FileTransferMessageHandler`: allowedBasePath (só serve arquivos sob esse path), FileChunker 128KB; envia metadata → chunks → progress → complete; em erro envia fileTransferError
  - [x] Tratamento de listFiles: lista recursiva sob allowedBasePath, envia fileList com List&lt;RemoteFileEntry&gt;
  - [x] Resolução de filePath relativo (request) em relação a allowedBasePath
  - [x] Integrado em `TcpSocketServer` (parâmetro opcional fileTransferHandler)
  - [x] DI: `allowedBasePath = getApplicationDocumentsDirectory()/backups`
- [x] **Cliente**
  - [x] `ConnectionManager.requestFile(filePath, outputPath, { scheduleId })`: envia request (path relativo ou absoluto), coleta metadata + chunks em `_activeTransfers`, monta arquivo com `FileChunker.assembleChunks`, timeout 5 min
  - [x] `ConnectionManager.listAvailableFiles()`: envia listFiles, recebe fileList, retorna `Result<List<RemoteFileEntry>>`
  - [x] Disconnect completa transferências ativas com Failure
- [x] **Domínio**
  - [x] `RemoteFileEntry` (path, size, lastModified)
- [x] **UI no cliente**
  - [x] `RemoteFileTransferProvider`: loadAvailableFiles(), selectedFile, outputPath, requestFile(), estados loading/transferring/error
  - [x] Página "Transferir Backups" (`TransferBackupsPage`): lista de arquivos remotos, seleção, pasta de destino (FilePicker), botão Transferir; rota `/transfer-backups`, item no MainLayout
  - [x] Provider e rota registrados no DI e app_widget
- [x] **Testes de integração**
  - [x] `file_transfer_integration_test.dart`: sucesso, path não permitido, arquivo não encontrado, listAvailableFiles retorna arquivos sob base path

### Opcional (pós-FASE 4) ✅ Concluído

- [x] Stream de progresso na UI (fileTransferProgress em tempo real: callback `onProgress` em `requestFile`, barra de progresso na página Transferir Backups)
- [x] Integração com FileTransferDao para registrar transferências concluídas (sucesso/falha) após cada transferência
- [x] Histórico de transferências na UI (seção "Histórico de transferências" na página Transferir Backups; `loadTransferHistory()`, `FileTransferHistoryEntry`, últimas 50)

---

## FASE 5.1 – Pasta padrão para backups recebidos ✅

- [x] Preferência `received_backups_default_path` (SharedPreferences)
- [x] Provider: `getDefaultOutputPath()`, `setDefaultOutputPath()`; preenchimento automático do destino ao carregar lista
- [x] UI: checkbox "Salvar como pasta padrão para backups recebidos" na página Transferir Backups

---

## ✅ FASE 5.2 – Destinos remotos do client (Enviar também para)

- [x] Interface `ISendFileToDestinationService` (domínio) e `SendFileToDestinationService` (application)
- [x] `RemoteFileTransferProvider`: seleção de destinos remotos (FTP, Google Drive, Dropbox, Nextcloud), upload após transferência local
- [x] UI: seção "Enviar também para" na página Transferir Backups com checkboxes por destino

---

## ✅ FASE 5.3 – Vinculação Agendamento ↔ Destino

- [x] Persistência: mapeamento `scheduleId → List<destinationId>` (SharedPreferences via RemoteFileTransferProvider)
- [x] UI Transferir Backups: dropdown "Agendamento" preenche checkboxes "Enviar também para" conforme vínculos
- [x] UI RemoteSchedulesPage: botão por agendamento abre ContentDialog para configurar destinos vinculados

---

## ✅ FASE 6 – Dashboard de métricas

- [x] Protocolo: `metricsRequest` / `metricsResponse`
- [x] Servidor: `MetricsMessageHandler` (calcula métricas a partir dos repositórios locais), integrado em TcpSocketServer
- [x] Cliente: `ConnectionManager.getServerMetrics()`; `DashboardProvider` busca e armazena métricas do servidor quando conectado
- [x] UI DashboardPage: seções "Local" e "Servidor" com cards de métricas (total backups, backups hoje, etc.)

---

## ✅ FASE 7 – Installer e integração

- [x] `lib/core/config/app_mode.dart`: enum `AppMode` (server, client, unified), `getAppMode(args)` (args, env `APP_MODE`, `config/mode.ini`), `currentAppMode`, `setAppMode`, `getWindowTitleForMode`
- [x] `main.dart`: detecção do modo e título da janela conforme `currentAppMode`
- [x] Instalador (`installer/setup.iss`): atalhos no menu Iniciar "Backup Database (Servidor)" (`--mode=server`) e "Backup Database (Cliente)" (`--mode=client`)

---

## _Próximas fases (8+)_

> **NOTA**: Este documento será atualizado conforme as fases são implementadas.
> Cada fase será expandida com o mesmo nível de detalhe da Fase 1 e 2.

---

## Links Rápidos

- [Plano Detalhado](plano_cliente_servidor.md)
- [Anotações Iniciais](anotacoes.txt)
- [Branch no GitHub](https://github.com/cesar-carlos/backup_database/tree/feature/client-server-architecture)

---

**Última Atualização**: 01/02/2026
**Responsável**: @cesar-carlos
**Status**: FASE 2.1–2.4 ✅ | FASE 3 ✅ | FASE 4 ✅ | Opcionais FASE 4 ✅ | FASE 5.1–5.3 ✅ | FASE 6 ✅ | FASE 7 ✅ | FASE 0: plano + teste auto ✅; pendente: testes manuais (migration v14)
