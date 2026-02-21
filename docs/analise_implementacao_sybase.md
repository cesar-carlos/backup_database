# Análise da Implementação de Backup para Sybase SQL Anywhere

## 📋 Visão Geral

Este documento consolida todas as informações sobre a implementação de backup para **Sybase SQL Anywhere (ASA)** no sistema de backup de bancos de dados.

---

## 🏗️ Arquitetura

### Estrutura de Camadas

A implementação segue **Clean Architecture** com as seguintes camadas:

#### **Domain Layer**

- **Entidade**: `SybaseConfig` (`lib/domain/entities/sybase_config.dart`)
- **Interface**: `ISybaseBackupService` (`lib/domain/services/i_sybase_backup_service.dart`)
- **Use Case**: `ExecuteSybaseBackup` (`lib/domain/use_cases/backup/execute_sybase_backup.dart`)

#### **Infrastructure Layer**

- **Service**: `SybaseBackupService` (`lib/infrastructure/external/process/sybase_backup_service.dart`)
- **Repository**: `SybaseConfigRepository` (`lib/infrastructure/repositories/sybase_config_repository.dart`)
- **DAO**: `SybaseConfigDao` (`lib/infrastructure/datasources/daos/sybase_config_dao.dart`)

#### **Application Layer**

- **Orchestrator**: `BackupOrchestratorService` (execução e compressão do backup)
- **Scheduler**: `SchedulerService` (envio para destinos e estado final da execução)
- **Provider**: `SybaseConfigProvider` (`lib/application/providers/sybase_config_provider.dart`)

#### **Presentation Layer**

- **Page**: `SybaseConfigPage` (`lib/presentation/pages/sybase_config_page.dart`)
- **Dialog**: `SybaseConfigDialog` (`lib/presentation/widgets/sybase/sybase_config_dialog.dart`)
- **Widgets**: `SybaseConfigList`, `SybaseConfigListItem`

---

## 🔧 Configuração da Entidade SybaseConfig

### Campos da Entidade

```dart
class SybaseConfig {
  final String id;                    // UUID único
  final String name;                  // Nome da configuração
  final String serverName;            // Engine Name (nome do servidor)
  final String databaseName;          // Nome do banco de dados (DBN)
  final String databaseFile;          // Caminho do arquivo .db (opcional)
  final int port;                     // Porta (padrão: 2638)
  final String username;              // Usuário (ex: DBA)
  final String password;              // Senha
  final bool enabled;                 // Habilitado/Desabilitado
  final DateTime createdAt;           // Data de criação
  final DateTime updatedAt;           // Data de atualização
}
```

### Observações Importantes

1. **Engine Name (serverName)**: Geralmente é o nome do arquivo `.db` sem extensão (ex: "Data7" para "Data7.db")
2. **Database Name (databaseName)**: Nome lógico do banco de dados dentro do servidor
3. **Database File**: Campo opcional, não necessário para backup quando usando conexão via ENG+DBN

---

## 📦 Tipos de Backup Suportados

### 1. **Full (Completo)**

- **Comando SQL**: `BACKUP DATABASE DIRECTORY '<path>'`
- **Comando dbbackup**: `dbbackup -c '<connection>' -y <path>`
- **Estrutura**: Cria um diretório com o nome do banco de dados contendo todos os arquivos
- **Status**: Banco ONLINE durante o backup
- **Uso**: Base para backups diferenciais e logs

### 2. **Differential (Diferencial)**

- **Comportamento**: Convertido automaticamente para Full
- **Motivo**: Sybase SQL Anywhere não suporta backup diferencial nativo via comandos de linha
- **Implementação**: `backupType == BackupType.differential` → tratado como `BackupType.full`
- **UI atual**: Opção não é exibida para Sybase no agendamento
- **Compatibilidade**: Agendamentos legados com `Differential` são normalizados para `Full` ao editar/salvar

### 3. **Log (Transação)**

- **Comando SQL (TRUNCATE)**: `BACKUP DATABASE DIRECTORY '<path>' TRANSACTION LOG TRUNCATE`
- **Comando SQL (ONLY)**: `BACKUP DATABASE DIRECTORY '<path>' TRANSACTION LOG ONLY`
- **Comando dbbackup (TRUNCATE)**: `dbbackup -t -x -c '<connection>' -y <path>`
- **Comando dbbackup (ONLY)**: `dbbackup -t -r -c '<connection>' -y <path>`
- **Saída**: arquivo de log dentro de um diretório por execução
- **Truncate Log**: Opção para liberar espaço após backup
- **Status**: Banco ONLINE durante o backup

### 4. **Full Single**

- **Comportamento**: Tratado como Full
- **Implementação**: `backupType == BackupType.fullSingle` → tratado como `BackupType.full`

---

## 🔄 Estratégias de Conexão

### Método 1: dbisql (SQL BACKUP DATABASE)

A implementação tenta primeiro usar `dbisql` com comando SQL `BACKUP DATABASE`:

#### Estratégias de Conexão (em ordem de tentativa):

1. **ENG+DBN (serverName + databaseName)**

   ```
   ENG=<serverName>;DBN=<databaseName>;UID=<username>;PWD=<password>
   ```

2. **ENG apenas (serverName)**

   ```
   ENG=<serverName>;UID=<username>;PWD=<password>
   ```

3. **ENG+DBN (databaseName como ambos)**
   ```
   ENG=<databaseName>;DBN=<databaseName>;UID=<username>;PWD=<password>
   ```

### Método 2: dbbackup (Fallback)

Se `dbisql` falhar, tenta `dbbackup` com as seguintes estratégias:

1. **ENG+DBN (serverName + databaseName)**

   ```
   ENG=<serverName>;DBN=<databaseName>;UID=<username>;PWD=<password>
   ```

2. **ENG+DBN (databaseName como ambos)**

   ```
   ENG=<databaseName>;DBN=<databaseName>;UID=<username>;PWD=<password>
   ```

3. **Apenas ENG por serverName**

   ```
   ENG=<serverName>;UID=<username>;PWD=<password>
   ```

4. **Conexão via TCPIP**
   ```
   HOST=localhost:<port>;DBN=<databaseName>;UID=<username>;PWD=<password>;LINKS=TCPIP
   ```

---

## 🛠️ Ferramentas Utilizadas

### 1. **dbisql**

- **Propósito**: Executar comandos SQL diretamente
- **Uso**: Backup via comando `BACKUP DATABASE`
- **Argumentos**: `-c '<connection>' -nogui '<sql_command>'`
- **Timeout**: 2 horas

### 2. **dbbackup**

- **Propósito**: Ferramenta nativa de backup do Sybase
- **Uso**: Fallback quando dbisql falha
- **Argumentos**:
  - (sem `-t`): Backup completo (full)
  - `-t`: Backup de transaction log
  - `-x`: Backup de log com truncate
  - `-t -r`: Backup de log sem truncate
  - `-c '<connection>'`: String de conexão
  - `-y <path>`: Caminho de destino
- **Timeout**: 2 horas

### 3. **dbvalid**

- **Propósito**: Verificar integridade de arquivo `.db` de backup (preferencial)
- **Uso**: Quando `verifyAfterBackup = true` e há backup Full com `.db` disponível
- **Argumentos**: `-c 'UID=<user>;PWD=<pass>;DBF=<backup_file.db>'`
- **Timeout**: 30 minutos

### 4. **dbverify** (fallback)

- **Propósito**: Verificação por conexão ativa ao banco
- **Uso**: Fallback quando `dbvalid` não é aplicável/falha
- **Argumentos**: `-c '<connection>' -d <databaseName>`
- **Timeout**: 30 minutos

---

## 📁 Estrutura de Arquivos de Backup

### Backup Full

```
<outputDirectory>/
  └── <databaseName>/
      ├── <databaseName>.db
      ├── <databaseName>.log
      └── ... (outros arquivos do banco)
```

### Backup Log

```
<outputDirectory>/
  └── <databaseName>_log_<timestamp>/
      └── <arquivo_gerado_pelo_sybase>.trn (ou .log)
```

---

## ✅ Verificação de Integridade

### dbvalid + dbverify (fallback)

Quando `verifyAfterBackup = true`, o sistema tenta:

1. `dbvalid` no arquivo `.db` do backup Full (validação offline preferencial)
2. `dbverify` por conexão (fallback)

```dart
dbvalid -c 'UID=<user>;PWD=<pass>;DBF=<backup_file.db>'
dbverify -c '<connection>' -d <databaseName>
```

**Estratégias de Conexão** (em ordem):

1. `ENG=<serverName>;DBN=<databaseName>;UID=<username>;PWD=<password>`
2. `ENG=<databaseName>;DBN=<databaseName>;UID=<username>;PWD=<password>`
3. `ENG=<serverName>;UID=<username>;PWD=<password>`

**Observação**: Se a verificação falhar em modo atual, o backup não é marcado como falha; é registrado warning.

---

## 🔍 Teste de Conexão

### Implementação

O método `testConnection` tenta conectar usando `dbisql`:

```dart
dbisql -c '<connection>' -q 'SELECT 1' -nogui
```

### Estratégias de Conexão (em ordem):

1. `ENG=<serverName>;DBN=<databaseName>;UID=<username>;PWD=<password>`
2. `ENG=<databaseName>;DBN=<databaseName>;UID=<username>;PWD=<password>`
3. `ENG=<serverName>;UID=<username>;PWD=<password>`

### Validações

- **serverName vazio**: Retorna erro
- **databaseName vazio**: Retorna erro
- **username vazio**: Retorna erro

### Mensagens de Erro Específicas

- **"unable to connect" / "server not found"**: Verifica servidor, porta, Engine Name e DBN
- **"invalid user" / "login failed"**: Usuário ou senha inválidos
- **"already in use"**: Banco em uso, verifica Engine Name

---

## ⚙️ Parâmetros de Backup

### Parâmetros do Método executeBackup

```dart
Future<Result<BackupExecutionResult>> executeBackup({
  required SybaseConfig config,        // Configuração do banco
  required String outputDirectory,      // Diretório de saída
  BackupType backupType = BackupType.full,
  String? customFileName,               // Nome customizado (opcional)
  String? dbbackupPath,                 // Caminho do dbbackup (opcional)
  bool truncateLog = true,              // Truncar log após backup
  bool verifyAfterBackup = false,       // Verificar integridade
})
```

### Truncate Log

- **Quando aplicável**: Apenas para `BackupType.log`
- **Comportamento**:
  - `truncateLog = true`: Libera espaço após backup (`TRANSACTION LOG TRUNCATE` ou `-x`)
  - `truncateLog = false`: Mantém log (`TRANSACTION LOG ONLY` ou `-t -r`)

---

## 🚨 Tratamento de Erros

### Erros Comuns e Mensagens

1. **"already in use"**

   ```
   O banco de dados está em uso e não foi possível conectar.
   Verifique se o nome do servidor (Engine Name) está correto.
   Geralmente é o nome do arquivo .db sem extensão (ex: "Data7").
   ```

2. **"server not found" / "unable to connect"**

   ```
   Não foi possível encontrar/conectar ao servidor Sybase.
   Verifique:
   1. Se o servidor Sybase está rodando
   2. Se a porta <port> está correta
   3. O Engine Name geralmente é o nome do arquivo .db (ex: "<databaseName>")
   ```

3. **"permission denied"**

   ```
   Permissão negada. Verifique se o usuário tem permissão para fazer backup.
   ```

4. **"invalid user" / "login failed"**
   ```
   Usuário ou senha inválidos.
   ```

### Validações de Backup Criado

Após executar o backup, o sistema:

1. Aguarda até 5 segundos (10 tentativas de 500ms) para o backup ser criado
2. Verifica se o diretório ou arquivo existe
3. Calcula o tamanho total dos arquivos
4. Valida que o tamanho é maior que 0 bytes

### Tratamento Especial para Backup de Log

Para backups de log (`.trn`/`.log`):

- Aguarda até 5 segundos adicionais para o arquivo ser liberado pelo Sybase
- Tenta abrir o arquivo em modo leitura para garantir que está acessível
- Aguarda mais 500ms após confirmar acesso

---

## 📋 Requisitos do Sistema

### Ferramentas Necessárias

1. **dbisql**: Ferramenta de linha de comando do Sybase SQL Anywhere
2. **dbbackup**: Ferramenta nativa de backup do Sybase SQL Anywhere
3. **dbvalid**: Verificação de integridade de backup Full (recomendada)
4. **dbverify**: Verificação por conexão (fallback/opcional)

### Caminhos de Instalação Padrão

#### Sybase SQL Anywhere 16 (64-bit)

```
C:\Program Files\SQL Anywhere 16\Bin64
```

#### Sybase SQL Anywhere 17 (64-bit)

```
C:\Program Files\SQL Anywhere 17\Bin64
```

#### Sybase SQL Anywhere 12 (64-bit)

```
C:\Program Files\SQL Anywhere 12\Bin64
```

#### Sybase SQL Anywhere 11 (64-bit)

```
C:\Program Files\SQL Anywhere 11\Bin64
```

### Configuração do PATH

As ferramentas devem estar no PATH do sistema ou do usuário. Consulte `docs/path_setup.md` para instruções detalhadas.

---

## 🔄 Fluxo de Execução

### 1. Preparação

- Valida configuração do banco
- Cria diretório de saída se não existir
- Determina tipo efetivo de backup (`differential` e `fullSingle` → `full`)

### 2. Execução do Backup

#### Tentativa 1: dbisql (SQL BACKUP DATABASE)

- Tenta 3 estratégias de conexão diferentes
- Executa comando SQL `BACKUP DATABASE DIRECTORY`
- Se bem-sucedido, continua para validação

#### Tentativa 2: dbbackup (Fallback)

- Se dbisql falhar, tenta dbbackup
- Tenta 4 estratégias de conexão diferentes
- Usa argumentos específicos conforme tipo de backup

### 3. Validação

- Aguarda criação do backup (até 5 segundos)
- Verifica existência do diretório/arquivo
- Calcula tamanho total
- Valida que tamanho > 0

### 4. Verificação de Integridade (Opcional)

- Se `verifyAfterBackup = true`, tenta `dbvalid` no arquivo do backup Full
- Em caso de falha/indisponibilidade, tenta `dbverify` com 3 estratégias de conexão
- Registra warning se falhar (não falha o backup)

### 5. Retorno

- Retorna `BackupExecutionResult` com:
  - `backupPath`: Caminho do backup criado
  - `fileSize`: Tamanho total em bytes
  - `duration`: Duração da execução
  - `databaseName`: Nome do banco de dados

---

## 🎯 Integração com o Sistema

### BackupOrchestratorService

O `BackupOrchestratorService` integra o backup Sybase com:

- Compressão (ZIP/RAR)
- Histórico de backups
- Logs de execução
- Notificações por e-mail

### SchedulerService

O `SchedulerService` integra com:

- Envio para destinos (Local, FTP, Google Drive, etc.)
- Tratamento de falhas de upload por destino
- Status final da execução considerando envio

### ScheduleDialog

Na UI, o usuário pode configurar:

- Tipo de backup (Full, Log)
- Truncate Log (apenas para Log)
- Verificação após backup
- Compressão (ZIP/RAR)
- Destinos de envio

**Observação**: Para Sybase, `Differential` não é exibido na UI; caso exista em agendamento legado, é convertido para `Full` ao editar/salvar.

---

## 📊 Comparação com Outros Bancos

| Característica          | Sybase                    | SQL Server              | PostgreSQL                      |
| ----------------------- | ------------------------- | ----------------------- | ------------------------------- |
| Backup Full             | ✅                        | ✅                      | ✅                              |
| Backup Differential     | ❌ (convertido para Full) | ✅                      | ✅                              |
| Backup Log              | ✅                        | ✅                      | ✅                              |
| Banco ONLINE            | ✅                        | ✅                      | ✅                              |
| Verificação Integridade | ✅ (dbvalid + dbverify)   | ✅ (RESTORE VERIFYONLY) | ✅ (pg_verifybackup/pg_restore) |
| Compressão              | ✅ (ZIP/RAR)              | ✅ (ZIP/RAR)            | ✅ (ZIP/RAR)                    |

---

## 🔧 Limitações Conhecidas

1. **Backup Differential**: Não suportado nativamente, convertido para Full
2. **Múltiplas Estratégias**: Necessário devido à variação nas configurações de conexão do Sybase
3. **Timeout**: 2 horas para backup, 30 minutos para verificação
4. **Arquivo de Log**: Requer aguardo adicional para liberação pelo Sybase

---

## 📝 Notas de Implementação

### Escapamento de Caminhos

Caminhos do Windows são escapados para uso em comandos SQL:

```dart
final escapedBackupPath = backupPath.replaceAll('\\', '\\\\');
```

### Nomenclatura de Arquivos

- **Full**: Diretório com nome do banco (`<databaseName>/`)
- **Log**: Diretório por execução (`<databaseName>_log_<timestamp>/`) contendo arquivo `.trn`/`.log`

### Tratamento de Differential

```dart
final effectiveType = (backupType == BackupType.differential ||
    backupType == BackupType.fullSingle)
    ? BackupType.full
    : backupType;
```

---

## 🎓 Referências

- Documentação Sybase SQL Anywhere
- `docs/path_setup.md` - Configuração de PATH
- `lib/infrastructure/external/process/sybase_backup_service.dart` - Implementação principal
- `lib/domain/entities/sybase_config.dart` - Entidade de configuração

---

## ✅ Checklist de Implementação

- [x] Entidade SybaseConfig criada
- [x] Interface ISybaseBackupService definida
- [x] SybaseBackupService implementado
- [x] Múltiplas estratégias de conexão
- [x] Suporte a Full e Log backups
- [x] Tratamento de Differential (convertido para Full)
- [x] Verificação de integridade (dbvalid + fallback dbverify)
- [x] Teste de conexão
- [x] Tratamento de erros específicos
- [x] Integração com BackupOrchestratorService
- [x] UI para configuração
- [x] UI para agendamento
- [x] Compressão de backups
- [x] Envio para destinos

---

**Última atualização**: 21 de fevereiro de 2026
