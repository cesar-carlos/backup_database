# Análise Técnica - UI, Banco de Dados e Pacotes

> **⚠️ IMPORTANTE**: Leia primeiro [README_CONTEXT_ATUAL.md](README_CONTEXT_ATUAL.md) para entender o estado atual do projeto
>
> **Branch**: `feature/client-server-architecture`
> **Data**: 01/02/2026
> **Status**: ✅ **Banco de Dados COMPLETO** (11/13 itens)
> **Commit**: `2dbc725`

## 📋 Índice

1. [UI - Componentes Padronizados](#1-ui---componentes-padronizados)
2. [Banco de Dados - Schema e Migrações](#2-banco-de-dados---schema-e-migrações)
3. [Pacotes Disponíveis vs Necessários](#3-pacotes-disponíveis-vs-necessários)
4. [Arquitetura de Camadas](#4-arquitetura-de-camadas)
5. [Decisões Finais](#5-decisões-finais)

---

## 1. UI - Componentes Padronizados

### 1.1 Framework UI Atual

**Framework**: ✅ **Fluent UI** (`fluent_ui: ^4.13.0`)

O projeto **JÁ USA** Fluent UI consistentemente. Não há mistura com Material.

**Vantagens**:
- Look & feel nativo Windows 11
- Componentes prontos para desktop
- Tema claro/escuro já configurado
- Cores e tipografia consistentes

### 1.2 Componentes Comuns Existentes

**Localização**: `lib/presentation/widgets/common/` (808 linhas totais)

| Componente | Linhas | Uso | Reutilizar? |
|------------|--------|-----|-------------|
| `app_button.dart` | 63 | Botões padrão (primary/secondary) | ✅ **SIM** |
| `app_card.dart` | 34 | Cards padrão | ✅ **SIM** |
| `app_text_field.dart` | ~50 | Inputs de texto | ✅ **SIM** |
| `app_dropdown.dart` | ~60 | Dropdowns | ✅ **SIM** |
| `password_field.dart` | ~40 | Senhas com toggle visibility | ✅ **SIM** |
| `config_list_item.dart` | 81 | Item de lista com ações | ✅ **SIM** |
| `save_button.dart` | ~30 | Botão salvar | ✅ **SIM** |
| `cancel_button.dart` | ~30 | Botão cancelar | ✅ **SIM** |
| `loading_indicator.dart` | ~40 | Indicador de carregamento | ✅ **SIM** |
| `empty_state.dart` | ~50 | Estado vazio | ✅ **SIM** |
| `message_modal.dart` | ~80 | Modais de mensagem | ✅ **SIM** |
| `error_widget.dart` | ~40 | Widget de erro | ✅ **SIM** |
| `action_button.dart` | ~30 | Botão de ação genérico | ✅ **SIM** |
| `numeric_field.dart` | ~50 | Campo numérico | ✅ **SIM** |

**Total**: 14 componentes reutilizáveis ✅

### 1.3 Padrões de UI Identificados

#### Padrão 1: Card com ListItem + Actions

**Exemplo**: `sql_server_config_list_item.dart`

```dart
Card(
  child: ListTile(
    leading: CircleAvatar(child: Icon(icon)),
    title: Text(name),
    subtitle: Column(info),
    trailing: Row([
      if (onToggleEnabled != null)
        ToggleSwitch(checked: enabled, onChanged: onToggleEnabled),
      IconButton(icon: Icon(Icons.edit), onPressed: onEdit),
      IconButton(icon: Icon(Icons.delete), onPressed: onDelete),
    ]),
  ),
)
```

**Reutilizar para**:
- ✅ Server connections list items
- ✅ Connected clients list items
- ✅ Remote schedules list items

#### Padrão 2: Button com Loading

**Exemplo**: `app_button.dart`

```dart
AppButton(
  label: 'Salvar',
  icon: Icons.save,
  isLoading: _saving,
  onPressed: _onSave,
)
```

**Reutilizar para**:
- ✅ Todos os botões de ação
- ✅ Botões de conectar/desconectar
- ✅ Botões de executar backup

#### Padrão 3: Provider + ChangeNotifier

**Exemplo**: `sql_server_config_provider.dart`

```dart
class SqlServerConfigProvider extends ChangeNotifier {
  List<SqlServerConfig> _configs = [];
  bool _isLoading = false;

  Future<void> loadConfigs() async { /* ... */ }
  Future<void> saveConfig(SqlServerConfig config) async { /* ... */ }
}
```

**Reutilizar para**:
- ✅ `ServerConnectionProvider` (client)
- ✅ `ConnectedClientProvider` (server)
- ✅ `ServerCredentialProvider` (server)
- ✅ `RemoteScheduleProvider` (client)

### 1.4 Componentes NOVOS Necessários

#### Server Mode

| Componente | Baseado em | Complexidade |
|------------|------------|--------------|
| `ConnectedClientsList` | `config_list_item.dart` | Baixa |
| `ServerCredentialDialog` | Dialog padrão FluentUI | Média |
| `QRCodeWidget` | Novo (pacote `qr_flutter`) | Média |
| `ConnectionLogTable` | DataTable FluentUI | Média |

#### Client Mode

| Componente | Baseado em | Complexidade |
|------------|------------|--------------|
| `ServerConnectionCard` | `app_card.dart` | Baixa |
| `ConnectionProgressDialog` | `loading_indicator.dart` | Baixa |
| `RemoteScheduleCard` | `config_list_item.dart` + custom | Média |
| `FileTransferProgressCard` | Novo | Alta |
| `TransferStatusIndicator` | Novo | Média |

### 1.5 Diagrama de Herança de Componentes

```
ConfigListItem (EXISTENTE - base reutilizável)
├── SqlServerConfigListItem (existente)
├── SybaseConfigListItem (existente)
├── PostgresConfigListItem (existente)
├── BackupDestinationListItem (existente)
├── 📝 ServerConnectionListItem (NOVO - client)
├── 📝 ConnectedClientListItem (NOVO - server)
└── 📝 RemoteScheduleListItem (NOVO - client)

AppButton (EXISTENTE)
├── Usado em TODAS as telas
├── 📝 ConnectButton (NOVO)
├── 📝 DisconnectButton (NOVO)
└── 📝 ExecuteScheduleButton (NOVO)

AppCard (EXISTENTE)
├── Usado em TODAS as telas
├── 📝 StatusIndicatorCard (NOVO)
├── 📝 TransferProgressCard (NOVO)
└── 📝 ConnectionStatusCard (NOVO)
```

---

## 2. Banco de Dados - Schema e Migrações

### 2.1 Schema Atual (Drift/SQLite)

**ORM**: ✅ **Drift** (`drift: ^2.29.0`)
**Banco**: SQLite via `sqlite3_flutter_libs: ^0.5.40`
**Schema Version**: 13
**Arquivo**: `lib/infrastructure/datasources/local/database.dart`

### 2.2 Tabelas Existentes

| Tabela | Uso | Migração Necessária? |
|--------|-----|----------------------|
| `sql_server_configs_table` | Configs SQL Server | ❌ Não |
| `sybase_configs_table` | Configs Sybase ASA | ❌ Não |
| `postgres_configs_table` | Configs PostgreSQL | ❌ Não |
| `backup_destinations_table` | Destinos (FTP, GD, etc) | ❌ Não |
| `schedules_table` | Agendamentos de backup | ❌ Não |
| `backup_history_table` | Histórico de backups | ❌ Não |
| `backup_logs_table` | Logs de backup | ❌ Não |
| `email_configs_table` | Configs de email | ❌ Não |
| `licenses_table` | Licenças | ❌ Não |

### 2.3 Tabelas NOVAS Necessárias (Client-Server)

#### 2.3.1 Server Mode - Credenciais de Acesso

**Tabela**: `server_credentials_table`

```dart
class ServerCredentialsTable extends Table {
  TextColumn get id => text()();
  TextColumn get serverId => text()(); // ID único do servidor
  TextColumn get passwordHash => text()(); // SHA-256 da senha
  TextColumn get name => text()(); // Nome amigável
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastUsedAt => dateTime().nullable()();
  TextColumn get description => text().nullable()(); // Descrição opcional

  @override
  Set<Column> get primaryKey => {id};
}
```

**Propósito**: Armazenar credenciais para clientes remotos se conectarem

#### 2.3.2 Server Mode - Log de Conexões

**Tabela**: `connection_logs_table`

```dart
class ConnectionLogsTable extends Table {
  TextColumn get id => text()();
  TextColumn get clientHost => text()(); // IP do cliente
  TextColumn get serverId => text().nullable(); // ID que tentou autenticar
  BoolColumn get success => boolean()(); // true = autenticado
  TextColumn get errorMessage => text().nullable()(); // Erro se falhou
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get clientId => text().nullable(); // ID do cliente autenticado

  @override
  Set<Column> get primaryKey => {id};
}
```

**Propósito**: Auditoria de tentativas de conexão

#### 2.3.3 Client Mode - Conexões Salvas

**Tabela**: `server_connections_table`

```dart
class ServerConnectionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()(); // Nome amigável (ex: "Servidor Produção")
  TextColumn get serverId => text()(); // ID do servidor para autenticação
  TextColumn get host => text()(); // IP ou hostname
  IntColumn get port => integer().withDefault(const Constant(9527))();
  TextColumn get password => text()(); // Senha (armazenada de forma segura)
  BoolColumn get isOnline => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastConnectedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```

**Propósito**: Client salva conexões com servidores

#### 2.3.4 Shared - Transferências de Arquivo

**Tabela**: `file_transfers_table` (Client e Server podem usar)

```dart
class FileTransfersTable extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId => text()(); // Agendamento relacionado
  TextColumn get fileName => text()();
  IntColumn get fileSize => integer()();
  IntColumn get currentChunk => integer()();
  IntColumn get totalChunks => integer()();
  TextColumn get status => text()(); // pending, started, completed, failed
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  TextColumn get sourcePath => text()(); // Caminho completo do arquivo
  TextColumn get destinationPath => text()(); // Onde foi salvo
  TextColumn get checksum => text()(); // SHA-256

  @override
  Set<Column> get primaryKey => {id};
}
```

**Propósito**: Histórico de transferências de arquivo (Client e Server)

### 2.4 DAOs Novos Necessários

| DAO | Tabela | Modo |
|-----|--------|------|
| `ServerCredentialDao` | `server_credentials_table` | Server |
| `ConnectionLogDao` | `connection_logs_table` | Server |
| `ServerConnectionDao` | `server_connections_table` | Client |
| `FileTransferDao` | `file_transfers_table` | Server e Client |

### 2.5 Migrações de Banco de Dados

#### Schema Version: 13 → 14

**Novas tabelas**:
1. `server_credentials_table`
2. `connection_logs_table`
3. `server_connections_table`
4. `file_transfers_table`

**Novos DAOs**:
1. `ServerCredentialDao`
2. `ConnectionLogDao`
3. `ServerConnectionDao`
4. `FileTransferDao`

**Migration Script**:

```dart
if (from < 14) {
  // Criar tabelas para cliente-servidor
  await customStatement('''
    CREATE TABLE server_credentials_table (
      id TEXT PRIMARY KEY,
      server_id TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      name TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      last_used_at INTEGER,
      description TEXT
    )
  ''');

  await customStatement('''
    CREATE TABLE connection_logs_table (
      id TEXT PRIMARY KEY,
      client_host TEXT NOT NULL,
      server_id TEXT,
      success INTEGER NOT NULL,
      error_message TEXT,
      timestamp INTEGER NOT NULL,
      client_id TEXT
    )
  ''');

  await customStatement('''
    CREATE TABLE server_connections_table (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      server_id TEXT NOT NULL,
      host TEXT NOT NULL,
      port INTEGER NOT NULL DEFAULT 9527,
      password TEXT NOT NULL,
      is_online INTEGER NOT NULL DEFAULT 0,
      last_connected_at INTEGER,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  await customStatement('''
    CREATE TABLE file_transfers_table (
      id TEXT PRIMARY KEY,
      schedule_id TEXT NOT NULL,
      file_name TEXT NOT NULL,
      file_size INTEGER NOT NULL,
      current_chunk INTEGER NOT NULL DEFAULT 0,
      total_chunks INTEGER NOT NULL,
      status TEXT NOT NULL,
      error_message TEXT,
      started_at INTEGER,
      completed_at INTEGER,
      source_path TEXT NOT NULL,
      destination_path TEXT NOT NULL,
      checksum TEXT NOT NULL
    )
  ''');

  // Criar índices para performance
  await customStatement('''
    CREATE INDEX idx_server_credentials_active
    ON server_credentials_table(is_active)
  ''');

  await customStatement('''
    CREATE INDEX idx_connection_logs_timestamp
    ON connection_logs_table(timestamp DESC)
  ''');

  await customStatement('''
    CREATE INDEX idx_file_transfers_schedule
    ON file_transfers_table(schedule_id)
  ''');

  LoggerService.info('Migração v14: Tabelas cliente-servidor criadas');
}
```

### 2.6 Atualização do AppDatabase

**Arquivo**: `lib/infrastructure/datasources/local/database.dart`

```dart
@DriftDatabase(
  tables: [
    // ... tabelas existentes (9 tabelas)
    SqlServerConfigsTable,
    SybaseConfigsTable,
    PostgresConfigsTable,
    BackupDestinationsTable,
    SchedulesTable,
    BackupHistoryTable,
    BackupLogsTable,
    EmailConfigsTable,
    LicensesTable,

    // ✅ NOVAS TABELAS (4 tabelas)
    ServerCredentialsTable,      // Server only
    ConnectionLogsTable,          // Server only
    ServerConnectionsTable,      // Client only
    FileTransfersTable,          // Server and Client
  ],
  daos: [
    // ... DAOs existentes (9 DAOs)
    SqlServerConfigDao,
    SybaseConfigDao,
    PostgresConfigDao,
    BackupDestinationDao,
    ScheduleDao,
    BackupHistoryDao,
    BackupLogDao,
    EmailConfigDao,
    LicenseDao,

    // ✅ NOVOS DAOs (4 DAOs)
    ServerCredentialDao,           // Server only
    ConnectionLogDao,               // Server only
    ServerConnectionDao,            // Client only
    FileTransferDao,                // Server and Client
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 14; // ✅ ATUALIZAR: 13 → 14

  // ... migration code
}
```

---

## 3. Pacotes Disponíveis vs Necessários

### 3.1 Pacotes Atuais (pubspec.yaml)

```yaml
# FRAMEWORK UI
fluent_ui: ^4.13.0              # ✅ Windows UI (usado)
cupertino_icons: ^1.0.8         # ✅ Icons

# STATE MANAGEMENT
provider: ^6.1.5+1              # ✅ ChangeNotifier
get_it: ^9.1.1                  # ✅ Dependency Injection

# BANCO DE DADOS
drift: ^2.29.0                  # ✅ SQLite ORM
sqlite3_flutter_libs: ^0.5.40  # ✅ SQLite Native
path_provider: ^2.1.5           # ✅ Caminhos
path: ^1.9.1                    # ✅ Manipulação de paths

# REDE
dio: ^5.9.0                     # ✅ HTTP Client
http: ^1.2.2                    # ✅ HTTP simples

# DESTINOS
ftpconnect: ^2.0.10             # ✅ FTP (existente)
googleapis: ^15.0.0             # ✅ Google Drive API
oauth2_client: ^4.2.1           # ✅ OAuth2

# CRIPTOGRAFIA
crypto: ^3.0.7                  # ✅ SHA-256, etc.
encrypt: ^5.0.3                 # ✅ Encrypt/Decrypt
# flutter_secure_storage: any    # ⚠️ Marcado como "any" (não adicionado)

# ARQUIVOS
archive: ^4.0.7                 # ✅ ZIP compression
file_picker: ^10.3.7             # ✅ File selection

# UTILITÁRIOS
uuid: ^4.5.2                    # ✅ UUIDs
intl: ^0.20.2                   # ✅ Internacionalização
logger: ^2.6.2                  # ⚠️ Logger (temos LoggerService customizado)
xml: ^6.5.0                     # ✅ Parsing (appcast, etc)

# WINDOWS DESKTOP
win32: ^5.15.0                  # ✅ Windows API
window_manager: ^0.5.1          # ✅ Janela
tray_manager: ^0.5.2            # ✅ System Tray

# SCHEDULING
cron: ^0.6.2                    # ✅ Cron expressions
timezone: ^0.10.1               # ✅ Timezones

# EMAIL
mailer: ^6.6.0                 # ✅ SMTP email

# UPDATE
auto_updater: ^1.0.0            # ✅ Auto-update

# OUTROS
result_dart: ^2.1.1              # ✅ Result pattern
shared_preferences: ^2.3.3      # ✅ Key-Value storage
flutter_dotenv: ^6.0.0           # ✅ Environment variables
package_info_plus: ^8.0.0        # ✅ Package info
url_launcher: ^6.3.1             # ✅ URLs
go_router: ^14.6.2               # ✅ Routing
google_fonts: ^6.2.1            # ✅ Fonts
flutter_svg: ^2.0.10+1          # ✅ SVG images
brasil_fields: ^1.18.0           # ✅ BR formatting
zard: ^0.0.24                   # ✅ (não identificado uso)
```

### 3.2 Pacotes FALTANTES (Necessários para Client-Server)

#### 3.2.1 QR Code Generator

**Pacote**: `qr_flutter: ^4.1.0`

**Por que?** Server vai gerar QR code com credenciais de conexão

**Implementação**:
```dart
import 'package:qr_flutter/qr_flutter.dart';

QrImageView(
  data: '${serverId}:${host}:${port}',
  version: QrVersions.auto,
  size: 200.0,
)
```

**Fontes**:
- [qr_flutter on pub.dev](https://pub.dev/packages/qr_flutter)
- [qr_flutter GitHub](https://github.com/theyakka/qr.flutter)

#### 3.2.2 TCP Socket

**Pacote**: ✅ **NENHUM** (dart:io nativo)

**Por que?** Dart tem `Socket` e `ServerSocket` nativos em `dart:io`

**Implementação**:
```dart
import 'dart:io';

// Server
final server = await ServerSocket.bind(host, port);
server.listen((Socket client) {
  // Handle connection
});

// Client
final socket = await Socket.connect(host, port);
socket.add(data);
```

#### 3.2.3 Secure Storage (Opcional)

**Status**: ⚠️ Marcado como `any` no pubspec.yaml (não adicionado)

**Pacotes**:
- ✅ `flutter_secure_storage: ^9.2.2` (recomendado)
- ✅ OU `local_secure_storage: ^1.0.1` (alternativa mais simples)

**Por que?** Armazenar senhas de conexões do Client

**Decisão**:
- Se senhas NÃO precisam ser muito seguras → usar `encrypt` (já tem) + SQLite
- Se senhas PRECISAM ser muito seguras → adicionar `flutter_secure_storage`

**Recomendação**: ✅ **Usar `encrypt` existente + SQLite por enquanto** (mais simples)

#### 3.2.4 CRC32 Checksum

**Pacote**: `crc32: ^0.0.1` ou implementação própria

**Por que?** Validar integridade de chunks e mensagens

**Decisão**: ✅ **Implementar próprio** (mais leve, sem dependência externa)

```dart
import 'dart:convert';
import 'dart:typed_data';

class CRC32 {
  static int calculate(List<int> data) {
    // Implementação simples de CRC32
    // Ou usar package crypto
  }
}
```

### 3.3 Resumo de Pacotes

| Categoria | Status | Ação |
|------------|--------|-------|
| UI Framework | ✅ Fluent UI existente | Reutilizar 100% |
| State Management | ✅ Provider existente | Reutilizar 100% |
| Banco de Dados | ✅ Drift existente | Adicionar 4 tabelas/DAOs |
| TCP Socket | ✅ Dart nativo | Usar dart:io |
| QR Code | ❌ Falta | ✅ **Adicionar `qr_flutter`** |
| Secure Storage | ⚠️ Marcado "any" | ✅ **Usar `encrypt` + SQLite** |
| Criptografia | ✅ Crypto existente | Reutilizar para hash SHA-256 |
| HTTP | ✅ Dio existente | Reutilizar para outras APIs |
| File Transfer | ❌ Falta | ✅ **Implementar com dart:io + chunks** |

---

## 4. Arquitetura de Camadas

### 4.1 Separação Server/Client

```
┌─────────────────────────────────────────────────────────────┐
│                    SHARED CODE (100%)                       │
│  (Usado por Server e Client)                              │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Domain Layer                                                 │
│  ├── protocol/          ✅ Message, FileChunk             │
│  ├── value_objects/    ✅ ServerId, PortNumber            │
│  └── entities/          ✅ RemoteScheduleControl         │
│                                                               │
│  Infrastructure Layer                                       │
│  ├── protocol/          ✅ BinaryProtocol, Compression     │
│  ├── external/          ✅ Destinos (FTP, GD, etc.)       │
│  └── core/              ✅ LoggerService, EncryptService    │
│                                                               │
│  Core                                                         │
│  ├── constants/         ✅ SocketConfig (porta 9527)        │
│  ├── theme/             ✅ AppTheme, AppColors            │
│  └── utils/             ✅ PasswordHasher, CRC32            │
│                                                               │
│  Presentation Layer                                         │
│  ├── widgets/common/    ✅ AppButton, AppCard, etc.      │
│  └── providers/         ✅ BackupProgressProvider         │
│                                                               │
└─────────────────────────────────────────────────────────────┘
           ↕                             ↕
┌─────────────────────┐    ┌─────────────────────────────┐
│  SERVER-SPECIFIC     │    │  CLIENT-SPECIFIC             │
│                      │    │                               │
│  Domain Layer         │    │  Domain Layer                 │
│  ├── -                │    │  ├── -                        │
│  ├── entities/        │    │  ├── entities/                │
│  │   └── ServerCredential    │    │  │   └── ServerConnection       │
│  │       ConnectedClient      │    │  │       RemoteScheduleControl│
│  │                               │    │  │                               │
│  Infrastructure      │    │  Infrastructure               │
│  ├── socket/server/   │    │  ├── socket/client/           │
│  │   └── TcpSocketServer      │    │  │   └── TcpSocketClient        │
│  ├── dao/             │    │  ├── dao/                      │
│  │   ├── ServerCredentialDao    │    │  │   └── ServerConnectionDao     │
│  │   └── ConnectionLogDao       │    │  │                               │
│  └── repositories/     │    │  └── repositories/               │
│      └── ServerCredentialRepo    │    │      └── ServerConnectionRepo    │
│                      │    │                               │
│  Presentation         │    │  Presentation                  │
│  ├── pages/            │    │  ├── pages/                     │
│  │   ├── ConnectedClientsPage  │    │  │   ├── ServerLoginPage         │
│  │   ├── ServerSettingsPage     │    │  │   ├── RemoteSchedulesPage     │
│  │   └── CredentialsDialog      │    │  │   └── ClientDashboardPage     │
│  └── widgets/         │    │  └── widgets/                   │
│      └── server/      │    │      └── client/                   │
└─────────────────────┘    └─────────────────────────────┘
```

### 4.2 Modo de Execução

**Detecção em `main.dart`**:

```dart
enum AppMode { server, client }

AppMode detectAppMode(List<String> args) {
  // 1. Command line args
  if (args.contains('--mode=server')) return AppMode.server;
  if (args.contains('--mode=client')) return AppMode.client;

  // 2. Config file (criado pelo instalador)
  final configFile = File('config/mode.ini');
  if (configFile.existsSync()) {
    final contents = configFile.readAsStringSync();
    if (contents.contains('Type=Server')) return AppMode.server;
    if (contents.contains('Type=Client')) return AppMode.client;
  }

  // 3. Default para server (backward compatibility)
  return AppMode.server;
}

void setupDependencies(AppMode appMode) {
  // Shared (ambos modos)
  getIt.registerLazySingleton(() => LoggerService());
  getIt.registerLazySingleton(() => BinaryProtocol());
  getIt.registerLazySingleton(() => PasswordHasher());

  if (appMode == AppMode.server) {
    // Server-only
    getIt.registerLazySingleton(() => TcpSocketServer());
    getIt.registerLazySingleton(() => ServerCredentialDao(db));
  } else if (appMode == AppMode.client) {
    // Client-only
    getIt.registerFactory(() => TcpSocketClient());
    getIt.registerLazySingleton(() => ServerConnectionDao(db));
  }
}
```

---

## 5. Decisões Finais

### 5.1 UI e Componentes

✅ **Manter Fluent UI 100%**
- Não há motivo para mudar
- Componentes comuns já são bem feitos
- Padrão de código é consistente

✅ **Reutilizar 14 componentes existentes**
- AppButton, AppCard, ConfigListItem
- Text fields, dropdowns, dialogs
- Loading indicators, empty states

✅ **Criar apenas componentes NOVOS necessários**
- ConnectedClientListItem (baseado em ConfigListItem)
- ServerConnectionCard (baseado em AppCard)
- FileTransferProgressCard (novo)
- QRCodeWidget (pacote `qr_flutter`)

### 5.2 Banco de Dados

✅ **Usar Drift/SQLite existente**
- Schema Version: 13 → 14
- 4 novas tabelas
- 4 novos DAOs
- Migration automática

✅ **Tabelas novas**:
1. `server_credentials_table` (Server)
2. `connection_logs_table` (Server)
3. `server_connections_table` (Client)
4. `file_transfers_table` (Server e Client)

✅ **Zero conflito com banco atual**
- Tabelas são independentes
- Migração segura
- Rollback possível

### 5.3 Pacotes

✅ **Adicionar apenas 1 pacote**:

```yaml
dependencies:
  qr_flutter: ^4.1.0  # ✅ QR code generator
```

❌ **NÃO adicionar**:
- TCP socket packages (usar dart:io nativo)
- Secure storage (usar encrypt + SQLite)
- CRC32 packages (implementar próprio)

✅ **Remover**:
- `logger: ^2.6.2` (temos LoggerService customizado)

### 5.4 Arquitetura

✅ **Clean Architecture mantida**
- Domain Layer compartilhado
- Infrastructure Layer separado (server/client)
- Application Layer separado (server/client)
- Presentation Layer separado (server/client)
- Core compartilhado

✅ **DRY principle aplicado**
- Zero duplicação de código de protocolo
- Destinos reutilizados 100%
- UI components compartilhados

---

## 6. Checklist de Implementação

### 6.1 Banco de Dados ✅

- [x] Criar `ServerCredentialsTable` (Drift table class) - **COMPLETO**
- [x] Criar `ConnectionLogsTable` (Drift table class) - **COMPLETO**
- [x] Criar `ServerConnectionsTable` (Drift table class) - **COMPLETO**
- [x] Criar `FileTransfersTable` (Drift table class) - **COMPLETO**
- [x] Criar `ServerCredentialDao` - **COMPLETO**
- [x] Criar `ConnectionLogDao` - **COMPLETO**
- [x] Criar `ServerConnectionDao` - **COMPLETO**
- [x] Criar `FileTransferDao` - **COMPLETO**
- [x] Atualizar `AppDatabase` (adicionar tabelas e DAOs) - **COMPLETO**
- [x] Atualizar schemaVersion: 13 → 14 - **COMPLETO**
- [x] Criar migration script (v14) - **COMPLETO**
- [x] Plano de testes: [fase0_migration_v14_test_plan.md](fase0_migration_v14_test_plan.md) - **COMPLETO**
- [x] Teste de integração automatizado: `test/integration/database_migration_v14_test.dart` - **COMPLETO**
- [ ] Testar migration manualmente - **PENDENTE**
- [ ] Testar migration com dados existentes - **PENDENTE**

### 6.2 UI Components

- [x] Adicionar pacote `qr_flutter: ^4.1.0` - **COMPLETO**
- [ ] Criar `ConnectedClientListItem` (baseado em ConfigListItem)
- [ ] Criar `ServerConnectionCard` (baseado em AppCard)
- [ ] Criar `RemoteScheduleCard` (baseado em ConfigListItem)
- [ ] Criar `FileTransferProgressCard` (novo)
- [ ] Criar `TransferStatusIndicator` (novo)
- [ ] Criar `QRCodeWidget` (usando qr_flutter)
- [ ] Criar `ConnectionProgressDialog` (baseado em loading)
- [ ] Criar `ConnectionLogTable` (DataTable FluentUI)

### 6.3 Providers

- [ ] Criar `ServerCredentialProvider` (Server)
- [ ] Criar `ConnectedClientProvider` (Server)
- [ ] Criar `ServerConnectionProvider` (Client)
- [ ] Criar `RemoteScheduleProvider` (Client)
- [ ] Criar `FileTransferProvider` (Server e Client)

### 6.4 Constants

- [x] Criar `lib/core/constants/socket_config.dart`
- [x] Definir porta default: 9527
- [x] Definir chunk size: 131072 (128KB)
- [x] Definir heartbeat interval: 30s
- [x] Definir heartbeat timeout: 60s

### 6.5 Utils

- [x] Criar `lib/core/utils/crc32.dart`
- [x] Implementar `Crc32.calculate(List<int> data)` / `Crc32.calculateUint8List(Uint8List data)`
- [ ] Criar testes unitários para CRC32
- [ ] Criar `lib/core/security/password_hasher.dart`
- [ ] Implementar `hashPassword(String password, String salt)`
- [ ] Implementar `verifyPassword(String password, String hash, String salt)`

---

## 7. Riscos e Mitigações

### 7.1 Risco: Quebra de compatibilidade com banco de dados atual

**Mitigação**:
- ✅ Migration controlada (v13 → v14)
- ✅ Tabelas novas são independentes
- ✅ Testar migration com backup do banco
- ✅ Manter rollback plan (restaurar v13)

### 7.2 Risco: Código duplicado Server/Client

**Mitigação**:
- ✅ Protocolo binário 100% compartilhado
- ✅ UI components reutilizados
- ✅ Services compartilhados (logger, encrypt)
- ✅ Validação via código review

### 7.3 Risco: Performance com muitas transferências simultâneas

**Mitigação**:
- ✅ Tamanho de chunk otimizado (128KB)
- ✅ Compressão zlib ativa
- ✅ Table/FileTransferDao para histórico
- ✅ Limite de transferências simultâneas (configurável)

---

## 8. Referências

### Pacotes Pesquisados

- [qr_flutter on pub.dev](https://pub.dev/packages/qr_flutter)
- [qr_flutter GitHub](https://github.com/theyakka/qr.flutter)
- [Drift ORM Documentation](https://drift.simonbinder.eu/)
- [Fluent UI Package](https://pub.dev/packages/fluent_ui)

### Documentos do Projeto

- [Plano Detalhado](plano_cliente_servidor.md)
- [Checklist Implementação](implementacao_cliente_servidor.md)
- [UI/UX e Instalação](ui_instalacao_cliente_servidor.md)

---

**Última Atualização**: 01/02/2026
**Responsável**: @cesar-carlos
**Status**: ✅ **Análise Completa** + **Banco de Dados Implementado**

## 📊 Progresso Atualizado

### ✅ Completado (11/13 itens - 85%)

**Banco de Dados:**
- ✅ 4 tabelas criadas (ServerCredentialsTable, ConnectionLogsTable, ServerConnectionsTable, FileTransfersTable)
- ✅ 4 DAOs criados com métodos especializados
- ✅ Schema version atualizado (13 → 14)
- ✅ Migration script v14 implementado com índices
- ✅ Código gerado com build_runner
- ✅ flutter analyze: No issues found

**Pacotes:**
- ✅ qr_flutter: ^4.1.0 adicionado

**Git:**
- ✅ Commit `2dbc725` criado e push para GitHub
- ✅ Branch `feature/client-server-architecture` atualizado

### ⏳ Pendente (2/13 itens - 15%)

- [ ] Testar migration manualmente (seguir [fase0_migration_v14_test_plan.md](fase0_migration_v14_test_plan.md))
- [ ] Testar migration com dados existentes

### 🚀 Próximos Passos

1. **Testar migration** (FASE 0 - Pré-requisitos)
   - Plano e teste automatizado já criados (ver acima)
   - Executar testes manuais conforme [fase0_migration_v14_test_plan.md](fase0_migration_v14_test_plan.md)
   - Backup do banco de dados atual; testar upgrade v13 → v14; verificar integridade dos dados

2. **Iniciar FASE 1** - Fundamentos Socket
   - Criar protocolo binário compartilhado
   - Implementar TcpSocketServer (Server)
   - Implementar TcpSocketClient (Client)
   - Testar conexão básica

3. **Criar UI Components** (em paralelo)
   - ConnectedClientListItem
   - ServerConnectionCard
   - QRCodeWidget
