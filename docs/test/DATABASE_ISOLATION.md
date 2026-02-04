# Separação de Bancos de Dados - Server vs Client

## 🎯 Problema Resolvido

**Problema Original:**
Ambas as instâncias (server e client) usavam o **MESMO** arquivo de banco de dados:
```
%APPDATA%\backup_database\backup_database.db
```

**Riscos:**
- Write conflicts (duas instâncias escrevendo simultaneamente)
- Database locked (SQLite trava o banco para escritas)
- Corrupção potencial do banco
- Race conditions

---

## ✅ Solução Implementada

### Bancos Separados por Modo

```
%APPDATA%\backup_database\
├── backup_database.db              ← SERVER (mantém compatibilidade)
└── backup_database_client.db       ← CLIENT (isolado)
```

### Como Funciona

**1. AppMode Detection** (`lib/core/config/app_mode.dart`)

```dart
String getDatabaseNameForMode(AppMode mode) {
  return switch (mode) {
    AppMode.client => 'backup_database_client',  // Novo banco isolado
    AppMode.server => 'backup_database',         // Banco original
    AppMode.unified => 'backup_database',        // Banco original
  };
}
```

**2. Database Initialization** (`lib/core/di/service_locator.dart`)

```dart
// Use separate database for client mode to avoid conflicts
final databaseName = getDatabaseNameForMode(currentAppMode);
getIt.registerLazySingleton<AppDatabase>(
  () => AppDatabase(databaseName: databaseName),
);
```

**3. Database Constructor** (`lib/infrastructure/datasources/local/database.dart`)

```dart
class AppDatabase extends _$AppDatabase {
  AppDatabase({String databaseName = 'backup_database'})
      : super(_openConnection(databaseName));
  // ...
}

LazyDatabase _openConnection([String databaseName = 'backup_database']) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, '$databaseName.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

---

## 📊 Estrutura dos Bancos

### Server Database (`backup_database.db`)

**Contém:**
- Todas as tabelas do servidor
- Agendamentos de backup
- Histórico de backups
- Destinos configurados
- Credenciais de acesso (ServerCredentialsTable)
- Logs de conexões recebidas (ConnectionLogsTable)
- Clientes conectados (em memória via ClientManager)

**Usado por:**
- App em modo **Server**
- App em modo **Unified**

### Client Database (`backup_database_client.db`)

**Contém:**
- Configurações locais do cliente
- Conexões salvas (ServerConnectionsTable)
- Histórico de transferências (FileTransfersTable)
- Destinos locais para backups recebidos

**Usado por:**
- App em modo **Client**

**NOTA:**
O client **NÃO** precisa de:
- Agendamentos (vem do servidor via socket)
- Histórico de backups do servidor (vem via socket)
- Credenciais de acesso (client tem as credenciais para conectar)

---

## 🔄 Sincronização de Dados

### Dados que Não São Sincronizados

**Server:**
- Agendamentos
- Histórico de backups
- Configurações de backup

**Client:**
- Conexões salvas
- Histórico de transferências

### Dados que Viajam Via Socket

```
┌─────────────────┐         Socket         ┌─────────────────┐
│   SERVER        │ ←←←←←←←←←←←←←←←←←←←→ │   CLIENT        │
│                 │                        │                 │
│ Agendamentos   │   listSchedules         │ UI: Lista       │
│ Histórico      │   scheduleList          │ Remota         │
│ Métricas       │   metricsResponse       │                 │
│                 │                        │                 │
└─────────────────┘                        └─────────────────┘
```

---

## 🧪 Testando a Separação

### Verificar Bancos Separados

```powershell
# Após rodar server e client
$env:APPDATA\backup_database\

# Deve ver:
# - backup_database.db          (server)
# - backup_database_client.db   (client)
```

### Teste de Conflito

**ANTES da correção:**
```
1. Iniciar server (abre backup_database.db)
2. Iniciar client (tenta abrir backup_database.db)
3. Resultado: Database locked ou write conflict ❌
```

**DEPOIS da correção:**
```
1. Iniciar server (abre backup_database.db)
2. Iniciar client (abre backup_database_client.db)
3. Resultado: Ambos funcionam sem conflitos ✅
```

---

## 📝 Tabelas por Banco

### Server Database (`backup_database.db`)

| Tabela | Propósito |
|--------|-----------|
| `sql_server_configs` | Configurações SQL Server |
| `sybase_configs` | Configurações Sybase |
| `postgres_configs` | Configurações PostgreSQL |
| `backup_destinations` | Destinos de backup |
| `schedules` | Agendamentos de backup |
| `backup_history` | Histórico de backups |
| `backup_logs` | Logs de operações |
| `email_configs` | Configurações de email |
| `licenses` | Licenças |
| `server_credentials` | Credenciais para clientes |
| `connection_logs` | Logs de conexões de clientes |

### Client Database (`backup_database_client.db`)

| Tabela | Propósito |
|--------|-----------|
| `backup_destinations` | Destinos locais do cliente |
| `server_connections` | Conexões salvas (servidores) |
| `file_transfers` | Histórico de transferências |

**NOTA:** O client também tem tabelas básicas como `email_configs`, `licenses` etc. para sua própria configuração local.

---

## 🔧 Como Foi Implementado

### Passo 1: Adicionar parâmetro no construtor

**Arquivo:** `lib/infrastructure/datasources/local/database.dart`

```dart
class AppDatabase extends _$AppDatabase {
  AppDatabase({String databaseName = 'backup_database'})
      : super(_openConnection(databaseName));
  // ...
}
```

### Passo 2: Atualizar função de conexão

```dart
LazyDatabase _openConnection([String databaseName = 'backup_database']) {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, '$databaseName.db'));
    return NativeDatabase.createInBackground(file);
  });
}
```

### Passo 3: Adicionar helper por modo

**Arquivo:** `lib/core/config/app_mode.dart`

```dart
String getDatabaseNameForMode(AppMode mode) {
  return switch (mode) {
    AppMode.client => 'backup_database_client',
    AppMode.server => 'backup_database',
    AppMode.unified => 'backup_database',
  };
}
```

### Passo 4: Usar no DI

**Arquivo:** `lib/core/di/service_locator.dart`

```dart
import 'package:backup_database/core/config/app_mode.dart';

// ...

// Use separate database for client mode to avoid conflicts
final databaseName = getDatabaseNameForMode(currentAppMode);
getIt.registerLazySingleton<AppDatabase>(
  () => AppDatabase(databaseName: databaseName),
);
```

---

## ⚠️ Backward Compatibility

### Server Mode

- ✅ **Mantém** `backup_database.db` (nome original)
- ✅ **Sem mudanças** em dados existentes
- ✅ **Sem migração** necessária
- ✅ **Totalmente compatível** com versões anteriores

### Client Mode

- ✅ **Novo banco** `backup_database_client.db`
- ✅ **Criado automaticamente** na primeira execução
- ✅ **Isolado** do servidor
- ✅ **Sincronização via socket** para dados do servidor

---

## 🧹 Limpeza

### Remover Banco do Client

Se quiser resetar o banco do client:

```powershell
# Parar todas as instâncias
.\stop_all.ps1

# Remover banco do client
Remove-Item "$env:APPDATA\backup_database\backup_database_client.db" -Force
```

### Remover Banco do Server

⚠️ **CUIDADO:** Isso apaga todos os dados do servidor!

```powershell
# Parar todas as instâncias
.\stop_all.ps1

# Remover banco do server
Remove-Item "$env:APPDATA\backup_database\backup_database.db" -Force
```

---

## 📚 Referências

- **Database Code:** `lib/infrastructure/datasources/local/database.dart`
- **App Mode:** `lib/core/config/app_mode.dart`
- **DI Setup:** `lib/core/di/service_locator.dart`
- **Tables:** `lib/infrastructure/datasources/local/tables/tables.dart`

---

## ✅ Benefícios

1. **Sem Conflitos** - Server e client operam independentemente
2. **Segurança** - Queda do client não afeta server
3. **Performance** - Sem locks entre instâncias
4. **Compatibilidade** - Server mantém banco original
5. **Escalabilidade** - Fácil adicionar mais modos no futuro

---

**Data de Implementação:** 02/02/2026
**Status:** ✅ Completo e Testado
