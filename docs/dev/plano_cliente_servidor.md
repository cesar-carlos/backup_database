# Plano Detalhado - Sistema Cliente-Servidor Backup Database

> **⚠️ IMPORTANTE**: Leia primeiro [README_CONTEXT_ATUAL.md](README_CONTEXT_ATUAL.md) para entender o estado atual do projeto
>
> **Status**: Planejamento (FASE 0: 85% implementado)
> **Branch**: `feature/client-server-architecture` > **Data de Criação**: Janeiro 2026
> **Prioridade**: Alta

## Visão Geral

Transformar o projeto atual em um sistema **Cliente-Servidor** onde:

- **Server (Atual)**: Continua com todas as funcionalidades atuais + Socket Server para clientes remotos
- **Client (Novo)**: Controle remoto de agendamentos e recebimento de backups via Socket TCP/IP

### Objetivos

1. Permitir que clientes remotos controlem agendamentos de um ou múltiplos servidores
2. Transmitir arquivos de backup compactados do Server para o Client via TCP Socket
3. Client configurar seus próprios destinos para salvar backups recebidos (FTP, Google Drive, etc.)
4. Dashboard do Client com métricas dos servidores conectados
5. Sistema de autenticação simples (ID + Senha) para conexão de clientes

## Decisão Arquitetural: Protocolo de Comunicação

### TCP Socket vs gRPC

Baseado em pesquisa de performance e casos de uso:

| Aspecto              | TCP Socket                                   | gRPC                                      |
| -------------------- | -------------------------------------------- | ----------------------------------------- |
| **Velocidade**       | ✅ Velocidade bruta para arquivos grandes    | 3-5x mais rápido que REST                 |
| **Overhead**         | ✅ Mínimo                                    | Protocol buffers + HTTP/2                 |
| **File Transfer**    | ✅ Ideal para streaming de arquivos binários | Requer workarounds                        |
| **Implementação**    | Manual, mas controle total                   | Estruturado, mas mais abstrato            |
| **Performance Dart** | ✅ Nativo (dart:io)                          | ⚠️ Histórico de problemas (~40ms por RPC) |

### Escolha: **TCP Socket (dart:io)**

**Motivos:**

1. **Arquivos Grandes**: Backups podem ter GBs - streaming raw TCP é mais eficiente
2. **Controle Total**: Protocolo binário customizado para otimizar transferência
3. **Performance Nativa**: Usa `dart:io` sem dependências externas
4. **Simplicidade**: Menos overhead para transferência de arquivos ponto-a-ponto
5. **Compatibilidade**: Funciona em Windows Desktop (Server e Client)

**Fontes:**

- [How to send file over a socket in Dart - Stack Overflow](https://stackoverflow.com/questions/53295342/how-to-send-file-over-a-socket-in-dart/53298013)
- [Performance Test - gRPC vs Socket vs REST API](https://medium.com/@safvan.kothawala/performance-test-grpc-vs-socket-vs-rest-api-9b9ac25ca3e5)
- [GitHub: flutter_tcp_example](https://github.com/JulianAssmann/flutter_tcp_example)

## Arquitetura do Sistema

### Diagrama de Alto Nível

```
┌─────────────────────────────────────────────────────────────────┐
│                        SERVER (Instalação Tipo 1)              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Funcionalidades Atuais (Mantidas)                       │  │
│  │  - Agendamentos                                          │  │
│  │  - Execução de Backups                                   │  │
│  │  - Destinos (FTP, Google Drive, etc)                     │  │
│  │  - Dashboard de Métricas                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  NOVO: Socket Server                                     │  │
│  │  - TCP Server (porta configurável, ex: 9527)            │  │
│  │  - Autenticação (Server ID + Password)                  │  │
│  │  - Gerencia clientes conectados                         │  │
│  │  - Protocolo binário para transmissão de arquivos       │  │
│  │  - Endpoint de métricas para clientes                   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              ↕ Socket TCP/IP
                              ─────────────
┌─────────────────────────────────────────────────────────────────┐
│                        CLIENT (Instalação Tipo 2)              │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Tela de Login                                           │  │
│  │  - Conectar a servidor (ID + Senha + Host + Porta)      │  │
│  │  - Lista de servidores salvos                           │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Tela de Controle Remoto                                 │  │
│  │  - Listar agendamentos do servidor                      │  │
│  │  - Trocar tipo de backup                                │  │
│  │  - Trocar data de execução                               │  │
│  │  - Executar agendamento remotamente                     │  │
│  │  - Configurar comandos SQL pós-backup                   │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Destinos do Client                                     │  │
│  │  - Local, FTP, Google Drive, Nextcloud, Dropbox         │  │
│  │  - Configurar onde salvar backups recebidos             │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Dashboard de Métricas                                   │  │
│  │  - Métricas locais + Métricas do servidor conectado     │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Fluxo de Backup com Transmissão ao Client

```
1. Server executa backup (fluxo normal)
   ↓
2. Server salva nos destinos configurados (FTP, etc)
   ↓
3. Server verifica se há cliente conectado para este agendamento
   ↓
4. Server converte backup para binário
   ↓
5. Server transmite via Socket TCP/IP para o Client
   ↓
6. Client recebe arquivo binário e descompacta
   ↓
7. Client salva nos seus próprios destinos configurados
   ↓
8. Client envia confirmação de recebimento para Server
```

## Estrutura de Arquivos e Camadas

### Organização de Pastas

```
lib/
├── domain/
│   ├── entities/
│   │   ├── server_connection.dart          # NOVO: Configuração de conexão com servidor
│   │   ├── connected_client.dart            # NOVO: Cliente conectado no servidor
│   │   └── remote_schedule_control.dart     # NOVO: Controle remoto de agendamento
│   ├── repositories/
│   │   ├── i_server_connection_repository.dart    # NOVO
│   │   └── i_remote_schedule_repository.dart      # NOVO
│   └── services/
│       ├── i_socket_server_service.dart           # NOVO: Interface do Server Socket
│       ├── i_socket_client_service.dart           # NOVO: Interface do Client Socket
│       └── i_protocol_service.dart                # NOVO: Protocolo binário
│
├── infrastructure/
│   ├── socket/
│   │   ├── server/
│   │   │   ├── tcp_socket_server.dart            # NOVO: Implementação do servidor
│   │   │   ├── client_handler.dart               # NOVO: Gerencia conexões de clientes
│   │   │   └── server_authentication.dart        # NOVO: Autenticação de clientes
│   │   └── client/
│   │       ├── tcp_socket_client.dart            # NOVO: Implementação do cliente
│   │       ├── connection_manager.dart           # NOVO: Gerencia conexões com servidores
│   │       └── file_transfer_handler.dart        # NOVO: Recebe arquivos do servidor
│   ├── protocol/
│   │   ├── binary_protocol.dart                  # NOVO: Serialização/deserialização binária
│   │   ├── message_types.dart                    # NOVO: Tipos de mensagens
│   │   └── file_chunker.dart                     # NOVO: Divide arquivos em chunks
│   └── repositories/
│       ├── server_connection_repository.dart     # NOVO: SQLite (Client)
│       └── connected_client_repository.dart      # NOVO: Memória/SQLite (Server)
│
├── application/
│   ├── services/
│   │   ├── socket_orchestrator_service.dart      # NOVO: Orquestra comunicação
│   │   ├── remote_backup_coordinator.dart        # NOVO: Coordena backup remoto
│   │   └── connection_ui_service.dart            # NOVO: UI de conexões
│   └── providers/
│       ├── server_connection_provider.dart       # NOVO: State management (Client)
│       └── remote_schedule_provider.dart         # NOVO: State management (Client)
│
├── presentation/
│   ├── pages/
│   │   ├── server_login_page.dart                # NOVO: Tela de login (Client)
│   │   ├── remote_schedules_page.dart            # NOVO: Controla agendamentos (Client)
│   │   └── server_settings_page.dart             # NOVO: Configura servidor (Server)
│   └── widgets/
│       ├── server/
│       │   ├── connection_dialog.dart            # NOVO: Dialogo de conexão
│       │   ├── server_list_item.dart             # NOVO: Item de servidor salvo
│       │   └── connected_clients_list.dart       # NOVO: Lista de clientes (Server)
│       └── remote/
│           ├── remote_schedule_card.dart         # NOVO: Card de agendamento remoto
│           └── file_transfer_progress.dart       # NOVO: Progresso de transferência
│
├── core/
│   ├── config/
│   │   ├── app_mode.dart                         # NOVO: Enum Server/Client
│   │   └── socket_config.dart                    # NOVO: Configurações de socket
│   └── utils/
│       └── binary_converter.dart                 # NOVO: Utilitários binários
```

## Protocolo Binário de Comunicação

### Estrutura da Mensagem

```
┌─────────────┬──────────────┬──────────────┬─────────────────┐
│  Header     │   Message    │    Payload    │     Checksum    │
│  (16 bytes) │   Type      │   (Variable)  │    (4 bytes)    │
├─────────────┼──────────────┼──────────────┼─────────────────┤
│ Magic (4)   │ Type (1)     │              │ CRC32 (4)       │
│ Version (1) │ RequestID(4) │              │                 │
│ Length (4)  │ Flags (3)    │              │                 │
│ Reserved (7)│              │              │                 │
└─────────────┴──────────────┴──────────────┴─────────────────┘
```

### Tipos de Mensagens

```dart
enum MessageType {
  // Autenticação
  authRequest,           // Client → Server
  authResponse,          // Server → Client
  authChallenge,         // Server → Client (handshake)

  // Controle de Agendamento
  listSchedules,         // Client → Server
  scheduleList,          // Server → Client
  updateSchedule,        // Client → Server
  executeSchedule,       // Client → Server
  scheduleUpdated,       // Server → Client

  // Transferência de Arquivo
  fileTransferStart,     // Server → Client
  fileChunk,             // Server → Client
  fileTransferProgress,  // Server → Client
  fileTransferComplete,  // Server → Client
  fileTransferError,     // Server → Client
  fileAck,               // Client → Server

  // Métricas
  metricsRequest,        // Client → Server
  metricsResponse,       // Server → Client

  // Conexão
  heartbeat,             // Bidirectional
  disconnect,            // Bidirectional
  error,                 // Bidirectional
}
```

### Exemplo de Mensagem - Auth Request

```
Hex View:
00 00 00 FA                    // Magic: 0xFA000000 (File Transfer Auth)
01                            // Version: 1
00 00 00 28                   // Length: 40 bytes
01                            // Type: AuthRequest
00 00 01 F4                   // RequestID: 500
00                            // Flags: None
00 00 00 00 00 00 00          // Reserved: 7 bytes

[Payload JSON]
{
  "serverId": "srv_abc123",
  "timestamp": 1704067200000,
  "passwordHash": "sha256_hash_here"
}

[Checksum]
A1 B2 C3 D4                   // CRC32
```

### Fluxo de Transferência de Arquivo

```
┌───────────────────────────────────────────────────────────────┐
│ SERVER → CLIENT: Backup Transfer Flow                         │
├───────────────────────────────────────────────────────────────┤
│                                                               │
│  1. fileTransferStart                                         │
│     {                                                          │
│       "scheduleId": "sched_123",                              │
│       "fileName": "backup_2024-01-01.zip",                    │
│       "fileSize": 1073741824,  // 1GB                        │
│       "chunkSize": 65536,    // 64KB                         │
│       "totalChunks": 16384,                                  │
│       "checksum": "sha256_hash_here"                          │
│     }                                                          │
│                                                               │
│  2. Client responde: fileAck { accepted: true }              │
│                                                               │
│  3. Server envia chunks em loop:                              │
│     for (chunk in chunks) {                                   │
│       fileChunk {                                              │
│         "chunkIndex": 0,                                      │
│         "data": [base64_encoded_binary],                      │
│         "chunkChecksum": "crc32_here"                         │
│       }                                                        │
│       Client: fileAck { received: true, chunkIndex: 0 }      │
│     }                                                          │
│                                                               │
│  4. fileTransferComplete                                       │
│     {                                                          │
│       "totalChunks": 16384,                                   │
│       "finalChecksum": "sha256_hash_here",                     │
│       "duration": 45000  // ms                                │
│     }                                                          │
│                                                               │
└───────────────────────────────────────────────────────────────┘
```

## Entidades e Data Models

### 1. ServerConnection (Client)

```dart
class ServerConnection {
  final String id;
  final String name;                    // Nome personalizável pelo usuário
  final String serverId;                // ID do servidor (autenticação)
  final String host;                    // IP ou hostname
  final int port;                       // Porta (default: 9527)
  final DateTime lastConnected;
  final bool isOnline;
  final ConnectionStatus status;

  enum ConnectionStatus {
    disconnected,
    connecting,
    connected,
    authenticationFailed,
    error,
  }
}
```

### 2. ConnectedClient (Server)

```dart
class ConnectedClient {
  final String id;
  final String clientId;
  final String clientName;              // Nome informado pelo client
  final String host;                    // IP do client
  final int port;
  final DateTime connectedAt;
  final DateTime lastHeartbeat;
  final bool isAuthenticated;

  // Agendamentos que este client está "monitorando"
  final List<String> monitoredScheduleIds;
}
```

### 3. RemoteScheduleControl (Shared)

```dart
class RemoteScheduleControl {
  final String scheduleId;
  final String scheduleName;

  // Controles permitidos pelo client
  final BackupType backupType;          // Client pode alterar
  final DateTime? nextRunAt;            // Client pode alterar
  final String? postBackupScript;       // Client pode alterar

  // Somente leitura (configurado no servidor)
  final String databaseName;
  final DatabaseType databaseType;
  final List<String> serverDestinations; // Destinos do servidor
  final bool enabled;

  // Destino do client (onde salvar backup recebido)
  final String? clientDestinationId;

  // Status de execução
  final BackupStatus? lastStatus;
  final DateTime? lastRunAt;
}
```

### 4. FileTransferProgress

```dart
class FileTransferProgress {
  final String transferId;
  final String scheduleId;
  final String fileName;

  // Progresso
  final int currentChunk;
  final int totalChunks;
  final double bytesTransferred;
  final double totalBytes;
  final double percentage;

  // Status
  final TransferStatus status;

  enum TransferStatus {
    pending,
    started,
    transferring,
    completed,
    failed,
    cancelled,
  }

  // Timing
  final DateTime startedAt;
  final DateTime? completedAt;
  final Duration? duration;

  // Erros
  final String? errorMessage;
}
```

## Services e Casos de Uso

### Domain Services

#### ISocketServerService (Server)

```dart
abstract class ISocketServerService {
  // Lifecycle
  Future<void> start({int port = 9527});
  Future<void> stop();
  Future<void> restart();
  bool get isRunning;
  int get port;

  // Client Management
  Future<List<ConnectedClient>> getConnectedClients();
  Future<void> disconnectClient(String clientId);
  Future<void> broadcastToAll(Message message);
  Future<void> sendToClient(String clientId, Message message);

  // Authentication
  Future<bool> authenticateClient(String serverId, String password);
  Future<void> revokeClient(String clientId);

  // File Transfer
  Future<void> sendFileToClient({
    required String clientId,
    required String filePath,
    required String scheduleId,
    ProgressCallback? onProgress,
  });
}
```

#### ISocketClientService (Client)

```dart
abstract class ISocketClientService {
  // Connection
  Future<Result<void>> connect({
    required String host,
    required int port,
    required String serverId,
    required String password,
  });
  Future<void> disconnect();
  bool get isConnected;
  ConnectionStatus get status;

  // Remote Schedule Control
  Future<Result<List<RemoteScheduleControl>>> listSchedules();
  Future<Result<void>> updateSchedule({
    required String scheduleId,
    BackupType? backupType,
    DateTime? nextRunAt,
    String? postBackupScript,
  });
  Future<Result<void>> executeSchedule(String scheduleId);

  // Metrics
  Future<Result<DashboardMetrics>> getServerMetrics();

  // File Receive
  Stream<FileTransferProgress> receiveFile({
    required String scheduleId,
    required String destinationPath,
  });
}
```

#### IProtocolService (Shared)

```dart
abstract class IProtocolService {
  // Serialization
  Uint8List serializeMessage(Message message);
  Message deserializeMessage(Uint8List data);

  // File handling
  List<FileChunk> chunkFile(String filePath, int chunkSize);
  Future<void> assembleFile({
    required List<FileChunk> chunks,
    required String outputPath,
    required String expectedChecksum,
  });

  // Validation
  bool validateChecksum(Uint8List data, String checksum);
  String calculateChecksum(Uint8List data);
}
```

## Aplicação de Instalação (Installer)

### Tipos de Instalação

O instalador Inno Setup será modificado para oferecer escolha:

```
┌─────────────────────────────────────────┐
│  Backup Database - Setup                │
├─────────────────────────────────────────┤
│                                         │
│  Select Installation Type:              │
│                                         │
│  ○ Server Mode                          │
│    Instala o servidor completo com:     │
│    - Agendamentos de backup             │
│    - Execução de backups                │
│    - Socket Server para clientes        │
│    - Dashboard de métricas              │
│                                         │
│  ○ Client Mode                          │
│    Instala o cliente remoto com:        │
│    - Conexão com servidores             │
│    - Controle remoto de agendamentos    │
│    - Recebimento de backups             │
│    - Dashboard de servidores            │
│                                         │
│  [ Cancel ]  [ Next > ]                │
└─────────────────────────────────────────┘
```

### Modificação do setup.iss

```iss
[Types]
Name: "server"; Description: "Server Mode"; Flags: iscustom
Name: "client"; Description: "Client Mode"; Flags: iscustom

[Components]
Name: "server_app"; Description: "Server Application"; Types: server
Name: "client_app"; Description: "Client Application"; Types: client
Name: "shared"; Description: "Shared Components"; Types: server client

[Files]
; Server files
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Components: server_app; Flags: ignoreversion recursesubdirs

; Client files
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
    Components: client_app; Flags: ignoreversion recursesubdirs

[Icons]
; Server icons
Name: "{group}\Backup Database Server"; Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=server"; Components: server_app
Name: "{autodesktop}\Backup Database Server"; Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=server"; Components: server_app

; Client icons
Name: "{group}\Backup Database Client"; Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=client"; Components: client_app
Name: "{autodesktop}\Backup Database Client"; Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=client"; Components: client_app

[Run]
; Start server or client based on installation type
Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=server --first-run"; \
    Description: "Launch Backup Database Server"; \
    Components: server_app; \
    StatusMsg: "Launching server..."; \
    Flags: nowait postinstall

Filename: "{app}\backup_database.exe"; \
    Parameters: "--mode=client --first-run"; \
    Description: "Launch Backup Database Client"; \
    Components: client_app; \
    StatusMsg: "Launching client..."; \
    Flags: nowait postinstall
```

### Modificação do main.dart

```dart
void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  // Detect mode from args or installer
  final appMode = _detectAppMode(args);

  // Configure dependencies based on mode
  setupDependencies(appMode);

  runApp(MyApp(appMode: appMode));
}

AppMode _detectAppMode(List<String> args) {
  // Check command line args
  if (args.contains('--mode=server')) return AppMode.server;
  if (args.contains('--mode=client')) return AppMode.client;

  // Check environment variable (set by installer)
  final modeFromEnv = dotenv.env['APP_MODE'];
  if (modeFromEnv == 'server') return AppMode.server;
  if (modeFromEnv == 'client') return AppMode.client;

  // Default to server (backward compatibility)
  return AppMode.server;
}

enum AppMode { server, client }
```

## Fases de Implementação

### FASE 1: Fundamentos (Semanas 1-2)

**Objetivo**: Infraestrutura base para comunicação Socket

#### 1.1 Protocolo Binário

- [ ] Criar `MessageType` enum
- [ ] Criar `Message` class com header/payload
- [ ] Implementar `ProtocolService` (serialização/deserialização)
- [ ] Criar testes unitários para protocolo
- [ ] Implementar checksum (CRC32)

#### 1.2 Socket Server Base

- [ ] Criar `TcpSocketServer` (server)
- [ ] Implementar `ClientHandler` (gerencia cada conexão)
- [ ] Criar `ServerAuthentication` (valida credenciais)
- [ ] Implementar heartbeat/ping-pong
- [ ] Adicionar logging estruturado

#### 1.3 Socket Client Base

- [ ] Criar `TcpSocketClient` (client)
- [ ] Implementar `ConnectionManager` (gerencia conexões)
- [ ] Criar tela básica de conexão (Server ID + Password + Host)
- [ ] Implementar auto-reconnect
- [ ] Adicionar tratamento de erros de conexão

**Entregáveis**:

- Server pode aceitar conexões TCP
- Client pode conectar e autenticar
- Mensagens básicas funcionam (auth, heartbeat)

---

### FASE 2: Autenticação e Gerenciamento de Conexões (Semana 3)

**Objetivo**: Sistema robusto de autenticação e gerenciamento

#### 2.1 Autenticação no Servidor

- [ ] Entity `ServerCredential` (ID + senha hash)
- [ ] Repository `ServerCredentialRepository` (SQLite)
- [ ] Tela no Server para gerar/configurar credenciais
- [ ] Validação de clientes conectados
- [ ] Log de tentativas de conexão

#### 2.2 Gerenciamento de Conexões (Client)

- [ ] Entity `ServerConnection` (servidores salvos)
- [ ] Repository `ServerConnectionRepository` (SQLite)
- [ ] Tela de login com lista de servidores salvos
- [ ] Salvar novas conexões
- [ ] Editar/Excluir conexões salvas

#### 2.3 Monitoramento de Clientes (Server)

- [ ] Entity `ConnectedClient`
- [ ] Repository `ConnectedClientRepository`
- [ ] Tela no Server para listar clientes conectados
- [ ] Botão para desconectar cliente
- [ ] Mostrar IP, nome, tempo conectado

**Entregáveis**:

- Server tem credenciais configuráveis
- Client salva e gerencia múltiplas conexões
- Server monitora clientes conectados

---

### FASE 3: Protocolo de Controle Remoto (Semana 4)

**Objetivo**: Client pode listar e controlar agendamentos

#### 3.1 Listar Agendamentos Remotos

- [ ] Message type `listSchedules`
- [ ] Server responde com `scheduleList`
- [ ] Entity `RemoteScheduleControl`
- [ ] Tela no Client com lista de agendamentos do servidor

#### 3.2 Atualizar Agendamento Remoto

- [ ] Message type `updateSchedule`
- [ ] Server valida e atualiza agendamento
- [ ] Client permite alterar: backupType, nextRunAt, postBackupScript
- [ ] Server notifica outros clientes conectados

#### 3.3 Executar Agendamento Remoto

- [ ] Message type `executeSchedule`
- [ ] Server inicia backup imediatamente
- [ ] Client mostra progresso (via dashboard do server)
- [ ] Confirmação de conclusão

#### 3.4 Restrições de Segurança

- [ ] Client NÃO pode alterar destinos do servidor
- [ ] Client NÃO pode criar/excluir agendamentos
- [ ] Client NÃO pode alterar configurações de database
- [ ] Validação no Server para todas as operações

**Entregáveis**:

- Client lista agendamentos do servidor
- Client altera campos permitidos
- Client executa agendamentos remotamente

---

### FASE 4: Transferência de Arquivos (Semanas 5-6)

**Objetivo**: Transmissão binária de backups do Server para Client

#### 4.1 Preparação de Arquivo (Server)

- [ ] Converter backup para binário
- [ ] Calcular SHA-256 checksum
- [ ] Dividir arquivo em chunks (64KB)
- [ ] `FileTransferStart` message com metadados

#### 4.2 Transmissão de Chunks

- [ ] Loop de envio de chunks
- [ ] Acknowledge do Client a cada chunk
- [ ] Controle de congestionamento (se necessário)
- [ ] Resume capability (reconectar e continuar)

#### 4.3 Recebimento e Assembly (Client)

- [ ] `FileTransferHandler` recebe chunks
- [ ] Buffer temporário para chunks
- [ ] Montar arquivo quando todos chunks recebidos
- [ ] Validar checksum SHA-256

#### 4.4 Progresso e UI

- [ ] Entity `FileTransferProgress`
- [ ] Provider `FileTransferProvider`
- [ ] Widget de progresso de transferência
- [ ] Cancelamento de transferência

#### 4.5 Tratamento de Erros

- [ ] Timeout de transferência
- [ ] Reconexão automática
- [ ] Reenvio de chunks perdidos
- [ ] Limpeza de arquivos parciais

**Entregáveis**:

- Server transmite arquivo binário
- Client recebe e monta arquivo
- Progresso visível na UI
- Tratamento robusto de erros

---

### FASE 5: Destinos do Client (Semana 7)

**Objetivo**: Client salva backups recebidos em seus próprios destinos

#### 5.1 Destino Local do Client

- [ ] Configurar pasta local para backups recebidos
- [ ] Salvar arquivo após transferência completa
- [ ] Validação de espaço em disco

#### 5.2 Destinos Remotos do Client

- [ ] Reutilizar serviços existentes: FTP, Google Drive, etc.
- [ ] Configurar destinos para backups recebidos
- [ ] Vincular destino ao agendamento remoto
- [ ] Upload automático após receber do servidor

#### 5.3 Vinculação Agendamento ↔ Destino

- [ ] `RemoteScheduleControl.clientDestinationId`
- [ ] UI para selecionar destino do client
- [ ] Upload automático para destino do client

**Entregáveis**:

- Client salva backups recebidos localmente
- Client envia para seus próprios destinos remotos
- Vinculação automática agendamento ↔ destino

---

### FASE 6: Dashboard de Métricas (Semana 8)

**Objetivo**: Client mostra métricas combinadas (local + servidor)

#### 6.1 Endpoint de Métricas no Server

- [ ] Message type `metricsRequest`
- [ ] Server responde com `metricsResponse`
- [ ] Incluir mesmas métricas do dashboard local

#### 6.2 Dashboard do Client

- [ ] Seletor de servidor conectado
- [ ] Métricas locais (transferências, conexões)
- [ ] Métricas do servidor selecionado
- [ ] Combinar ambas em UI única

#### 6.3 Tempo Real

- [ ] Atualização periódica (via socket)
- [ ] Server notifica clientes sobre mudanças
- [ ] Client atualiza dashboard automaticamente

**Entregáveis**:

- Client dashboard com métricas do servidor
- Atualização em tempo real
- Seletor de servidor para múltiplas conexões

---

### FASE 7: Installer e Integração (Semana 9)

**Objetivo**: Instalador com escolha Server/Client

#### 7.1 Modificação do Inno Setup

- [ ] Adicionar tipos de instalação (Server/Client)
- [ ] Condicionar arquivos por tipo
- [ ] Criar ícones diferentes
- [ ] Passar parâmetros de modo via linha de comando

#### 7.2 Detecção de Modo no App

- [ ] `AppMode` enum (server/client)
- [ ] Detectar modo via args/env
- [ ] Iniciar UI apropriada
- [ ] Registrar dependências corretas

#### 7.3 Testes de Instalação

- [ ] Instalar modo Server
- [ ] Instalar modo Client
- [ ] Testar ambos na mesma máquina
- [ ] Testar desinstalação

**Entregáveis**:

- Instalador com escolha Server/Client
- App inicia no modo correto
- Instalação limpa de ambos modos

---

### FASE 8: Testes e Documentação (Semana 10)

**Objetivo**: Testes finais e documentação

#### 8.1 Testes de Integração

- [ ] Server + Client na mesma máquina
- [ ] Server + Client em máquinas diferentes (LAN)
- [ ] Múltiplos clientes conectados
- [ ] Transferência de arquivos grandes (>1GB)
- [ ] Interrupção de rede durante transferência
- [ ] Reconexão automática

#### 8.2 Testes de Carga

- [ ] 10 clientes simultâneos
- [ ] Transferências concorrentes
- [ ] Memória e CPU do server
- [ ] Memory leaks

#### 8.3 Documentação

- [ ] Guia de instalação Server
- [ ] Guia de instalação Client
- [ ] Guia de configuração de rede/firewall
- [ ] Troubleshooting comum
- [ ] FAQ

#### 8.4 Release

- [ ] Tag da versão
- [ ] Release notes
- [ ] Instaladores (Server e Client)
- [ ] GitHub Actions para build

**Entregáveis**:

- Testes completos passando
- Documentação completa
- Release publicado

---

## Riscos e Mitigações

### Risco 1: Performance de Transferência de Arquivos Grandes

**Problema**: Arquivos de backup podem ter dezenas de GB; transferência pode ser lenta.

**Mitigações**:

- Chunk size otimizado (64KB-1MB)
- Compressão durante transferência (zlib)
- Parallel transfer (múltiplas conexões)
- Resume capability (reconectar e continuar)
- Limpeza automática de arquivos temporários

### Risco 2: Conexões Intermitentes de Rede

**Problema**: Client pode perder conexão durante transferência.

**Mitigações**:

- Auto-reconnect com backoff exponencial
- Checksum de cada chunk
- Resume de transferência interrompida
- Timeout configurável
- Queue de transferências (retry automático)

### Risco 3: Segurança da Autenticação

**Problema**: Senha em texto pode ser interceptada.

**Mitigações**:

- Hash SHA-256 da senha (não enviar em texto)
- Challenge-response authentication
- TLS/SSL wrapper (opcional, via OpenSSL)
- Rate limiting de tentativas de login
- Log de tentativas de autenticação

### Risco 4: Múltiplos Clients Sobrecarregando o Server

**Problema**: Muitos clientes conectados podem degradar performance.

**Mitigações**:

- Limite máximo de clientes conectados
- Thread pool para handlers
- Queue de transferências
- Prioridade de operações (control > transferência)
- Monitoramento de recursos do server

### Risco 5: Compatibilidade com Firewall/Antivírus

**Problema**: Firewall pode bloquear conexões de socket.

**Mitigações**:

- Porta configurável (default: 9527)
- Documentar configuração de firewall
- Testar com Windows Firewall ativo
- Oferecer modo UPnP (abrir porta automaticamente)
- Fallback para WebSocket (HTTPS)

## Cronograma Resumido

| Fase | Descrição                    | Semanas | Status     |
| ---- | ---------------------------- | ------- | ---------- |
| 1    | Fundamentos Socket           | 1-2     | ⏳ Pending |
| 2    | Autenticação e Conexões      | 3       | ⏳ Pending |
| 3    | Protocolo de Controle Remoto | 4       | ⏳ Pending |
| 4    | Transferência de Arquivos    | 5-6     | ⏳ Pending |
| 5    | Destinos do Client           | 7       | ⏳ Pending |
| 6    | Dashboard de Métricas        | 8       | ⏳ Pending |
| 7    | Installer e Integração       | 9       | ⏳ Pending |
| 8    | Testes e Documentação        | 10      | ⏳ Pending |

**Total**: 10 semanas (~2.5 meses)

## Critérios de Sucesso

### Funcionais

- [ ] Server aceita conexões de múltiplos clientes
- [ ] Client conecta e autentica em múltiplos servidores
- [ ] Client lista e controla agendamentos remotos
- [ ] Transferência de arquivos binários funciona
- [ ] Client salva backups em seus próprios destinos
- [ ] Dashboard do Client mostra métricas do servidor
- [ ] Instalador oferece escolha Server/Client

### Não-Funcionais

- [ ] Transferência de 1GB completada em <5 minutos (LAN)
- [ ] Auto-reconnect funciona após queda de conexão
- [ ] Server suporta 10 clientes simultâneos
- [ ] Uso de memória do server <500MB com 5 clientes
- [ ] Documentação completa cobrindo instalação e troubleshooting

### Qualidade

- [ ] Testes unitários para protocolo binário
- [ ] Testes de integração para fluxos críticos
- [ ] Zero memory leaks em transferências longas
- [ ] Logging estruturado para debugging
- [ ] Código segue Clean Architecture

## Próximos Passos

### Imediatos (Esta semana)

1. **Criar branch** `feature/client-server-architecture`
2. **Configurar ambiente** de testes de socket
3. **Implementar PoC** de Socket Server/Client básico
4. **Testar** comunicação básica (auth + heartbeat)

### Decisões Pendentes

1. **Porta default**: 9527 está ok? Alternativas: 8080, 9000, 9999
2. **Tamanho de chunk**: 64KB, 128KB, ou 256KB?
3. **Compressão durante transferência**: Sim ou não?
4. **TLS/SSL**: Implementar agora ou depois (v2)?
5. **Limite de clientes**: 5, 10, ou ilimitado?

## Referências

### Socket em Dart/Flutter

- [How to send file over a socket in Dart - Stack Overflow](https://stackoverflow.com/questions/53295342/how-to-send-file-over-a-socket-in-dart/53298013)
- [GitHub: flutter_tcp_example](https://github.com/JulianAssmann/flutter_tcp_example)
- [Medium: TCP SOCKET in Flutter](https://medium.com/@arunthacharuthodi/tcp-socket-in-flutter-dart-io-library-cc50c65cb23c)

### Performance

- [Performance Test - gRPC vs Socket vs REST API](https://medium.com/@safvan.kothawala/performance-test-grpc-vs-socket-vs-rest-api-9b9ac25ca3e5)
- [gRPC Performance Best Practices](https://grpc.io/docs/guides/performance/)

### Protocolo Binário

- [Protocol Buffers - Google](https://protobuf.dev/)
- [Binary Protocol Design - Best Practices](https://blog.stephencleary.com/2022/05/binary-protocols.html)

### Instalação

- [Inno Setup Documentation](https://jrsoftware.org/isdl.php)
- [Inno Setup Script Examples](https://www.example-code.com/innosetup/)

---

**Documento criado por**: Claude AI
**Data**: Janeiro 2026
**Versão**: 1.0
**Status**: Aprovação Pendente
