# Análise da Implementação de Backup para SQL Server

## 📋 Visão Geral

Este documento consolida todas as informações sobre a implementação de backup para **Microsoft SQL Server** no sistema de backup de bancos de dados.

---

## 🏗️ Arquitetura

### Estrutura de Camadas

A implementação segue **Clean Architecture** com as seguintes camadas:

#### **Domain Layer**

- **Entidade**: `SqlServerConfig` (`lib/domain/entities/sql_server_config.dart`)
- **Interface**: `ISqlServerBackupService` (`lib/domain/services/i_sql_server_backup_service.dart`)
- **Use Case**: `ExecuteSqlServerBackup` (`lib/domain/use_cases/backup/execute_sql_server_backup.dart`)

#### **Infrastructure Layer**

- **Service**: `SqlServerBackupService` (`lib/infrastructure/external/process/sql_server_backup_service.dart`)
- **Repository**: `SqlServerConfigRepository` (`lib/infrastructure/repositories/sql_server_config_repository.dart`)
- **DAO**: `SqlServerConfigDao` (`lib/infrastructure/datasources/daos/sql_server_config_dao.dart`)

#### **Application Layer**

- **Orchestrator**: `BackupOrchestratorService` (integração com SQL Server)
- **Provider**: `SqlServerConfigProvider` (`lib/application/providers/sql_server_config_provider.dart`)

#### **Presentation Layer**

- **Page**: `SqlServerConfigPage` (`lib/presentation/pages/sql_server_config_page.dart`)
- **Dialog**: `SqlServerConfigDialog` (`lib/presentation/widgets/sql_server/sql_server_config_dialog.dart`)
- **Widgets**: `SqlServerConfigList`, `SqlServerConfigListItem`

---

## 🔧 Configuração da Entidade SqlServerConfig

### Campos da Entidade

```dart
class SqlServerConfig {
  final String id;                    // UUID único
  final String name;                  // Nome da configuração
  final String server;                 // Nome do servidor ou IP
  final String database;               // Nome do banco de dados
  final String username;               // Usuário (ex: sa)
  final String password;               // Senha
  final int port;                      // Porta (padrão: 1433)
  final bool enabled;                  // Habilitado/Desabilitado
  final DateTime createdAt;            // Data de criação
  final DateTime updatedAt;            // Data de atualização
}
```

### Observações Importantes

1. **Server**: Pode ser nome do servidor (ex: "localhost", "SERVER01") ou endereço IP
2. **Database**: Nome do banco de dados específico a ser feito backup
3. **Autenticação**: Suporta autenticação SQL Server (`-U`/`-P`) ou Windows (`-E`)

---

## 📦 Tipos de Backup Suportados

### 1. **Full (Completo)**

- **Comando SQL**: `BACKUP DATABASE [<database>] TO DISK = N'<path>' WITH ...`
- **Extensão**: `.bak`
- **Status**: Banco ONLINE durante o backup
- **Uso**: Base para backups diferenciais e logs
- **Características**:
  - Backup completo de todos os dados e objetos
  - Suporta CHECKSUM para verificação de integridade
  - Usa `NOINIT` para anexar ao arquivo existente (se houver)

### 2. **Differential (Diferencial)**

- **Comando SQL**: `BACKUP DATABASE [<database>] TO DISK = N'<path>' WITH DIFFERENTIAL, ...`
- **Extensão**: `.bak`
- **Status**: Banco ONLINE durante o backup
- **Uso**: Backup apenas das alterações desde o último backup Full
- **Requisito**: Requer backup Full anterior
- **Características**:
  - Menor tamanho que backup Full
  - Mais rápido que backup Full
  - Suporta CHECKSUM

### 3. **Log (Transação)**

- **Comando SQL**: `BACKUP LOG [<database>] TO DISK = N'<path>' WITH ...`
- **Extensão**: `.trn`
- **Status**: Banco ONLINE durante o backup
- **Truncate Log**: Opção para liberar espaço após backup
- **Características**:
  - `truncateLog = true`: Backup padrão que libera espaço (`BACKUP LOG ...`)
  - `truncateLog = false`: Backup COPY_ONLY que não afeta a cadeia de logs (`BACKUP LOG ... WITH COPY_ONLY`)
  - Suporta CHECKSUM

### 4. **Full Single**

- **Comportamento**: Tratado como Full
- **Implementação**: `backupType == BackupType.fullSingle` → tratado como `BackupType.full`

---

## 🛠️ Ferramentas Utilizadas

### sqlcmd

- **Propósito**: Ferramenta de linha de comando do SQL Server para executar comandos T-SQL
- **Uso**: Execução de comandos `BACKUP DATABASE` e `BACKUP LOG`
- **Timeout**: 2 horas para backup, 30 minutos para verificação
- **Argumentos Principais**:
  - `-S <server>,<port>`: Servidor e porta
  - `-d <database>`: Banco de dados
  - `-U <username>`: Usuário (autenticação SQL Server)
  - `-P <password>`: Senha (autenticação SQL Server)
  - `-E`: Autenticação Windows (Trusted Connection)
  - `-Q '<query>'`: Executar query e sair
  - `-t <timeout>`: Timeout de comando (segundos)

---

## 📝 Comandos SQL Utilizados

### Backup Full

```sql
BACKUP DATABASE [<database>]
TO DISK = N'<path>'
WITH CHECKSUM, NOFORMAT, NOINIT,
NAME = N'<database>-Full Database Backup',
SKIP, NOREWIND, NOUNLOAD, STATS = 10
```

**Opções**:
- `CHECKSUM`: Verifica integridade durante backup (quando `enableChecksum = true`)
- `NOFORMAT`: Não formata mídia
- `NOINIT`: Anexa ao arquivo existente (não sobrescreve)
- `SKIP`: Ignora verificação de expiração
- `NOREWIND`: Não rebobina fita
- `NOUNLOAD`: Não descarrega fita após backup
- `STATS = 10`: Mostra progresso a cada 10%

### Backup Differential

```sql
BACKUP DATABASE [<database>]
TO DISK = N'<path>'
WITH DIFFERENTIAL, CHECKSUM, NOFORMAT, NOINIT,
NAME = N'<database>-Differential Database Backup',
SKIP, NOREWIND, NOUNLOAD, STATS = 10
```

**Diferença**: Adiciona `DIFFERENTIAL` para backup apenas das alterações.

### Backup Log (Truncate)

```sql
BACKUP LOG [<database>]
TO DISK = N'<path>'
WITH CHECKSUM, NOFORMAT, NOINIT,
NAME = N'<database>-Transaction Log Backup',
SKIP, NOREWIND, NOUNLOAD, STATS = 10
```

**Comportamento**: Libera espaço no log após backup.

### Backup Log (COPY_ONLY)

```sql
BACKUP LOG [<database>]
TO DISK = N'<path>'
WITH COPY_ONLY, CHECKSUM, NOFORMAT, NOINIT,
NAME = N'<database>-Transaction Log Backup',
SKIP, NOREWIND, NOUNLOAD, STATS = 10
```

**Comportamento**: Não afeta a cadeia de logs, não libera espaço.

---

## ✅ Verificação de Integridade

### RESTORE VERIFYONLY

Quando `verifyAfterBackup = true`, o sistema executa `RESTORE VERIFYONLY` após o backup:

```sql
RESTORE VERIFYONLY FROM DISK = N'<path>'
WITH CHECKSUM
```

**Características**:
- Verifica integridade do arquivo de backup sem restaurar
- `WITH CHECKSUM`: Verifica checksums se foram criados durante backup
- Não restaura dados, apenas valida o arquivo
- Timeout: 30 minutos

**Observação**: Se a verificação falhar, o backup não é considerado como falha, apenas um warning é registrado.

---

## 🔍 CHECKSUM

### Funcionalidade

Quando `enableChecksum = true`:
- **Durante Backup**: SQL Server calcula checksums para cada página e armazena no arquivo
- **Durante Verificação**: `RESTORE VERIFYONLY WITH CHECKSUM` valida os checksums

### Benefícios

- Detecta corrupção de dados durante backup
- Valida integridade do arquivo de backup
- Requer mais processamento durante backup

### Uso

- Habilitado na aba "Configurações" do agendamento
- Disponível apenas para SQL Server
- Recomendado para ambientes críticos

---

## 🔍 Teste de Conexão

### Implementação

O método `testConnection` executa:

```sql
SELECT @@VERSION
```

**Argumentos sqlcmd**:
- `-S <server>,<port>`: Servidor e porta
- `-Q '<query>'`: Query a executar
- `-t 5`: Timeout de 5 segundos
- `-U <username>` / `-P <password>` ou `-E`: Autenticação

**Timeout**: 10 segundos

### Validações

- Verifica conectividade com o servidor
- Valida credenciais de autenticação
- Confirma acesso ao banco de dados

---

## 📋 Listagem de Bancos de Dados

### Implementação

O método `listDatabases` executa:

```sql
SELECT name FROM sys.databases
WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')
ORDER BY name
```

**Características**:
- Exclui bancos de sistema (master, tempdb, model, msdb)
- Retorna apenas bancos de usuário
- Ordenado alfabeticamente
- Timeout padrão: 15 segundos

**Argumentos sqlcmd**:
- `-h -1`: Remove cabeçalho
- `-W`: Remove espaços em branco
- `-t 10`: Timeout de 10 segundos

---

## 📁 Estrutura de Arquivos de Backup

### Backup Full / Differential

```
<outputDirectory>/
  └── <database>_<type>_<timestamp>.bak
```

**Exemplo**:
```
D:\Backups\Full\
  └── MyDatabase_full_2024-12-22T10-30-45.bak
```

### Backup Log

```
<outputDirectory>/
  └── <database>_log_<timestamp>.trn
```

**Exemplo**:
```
D:\Backups\Log\
  └── MyDatabase_log_2024-12-22T10-30-45.trn
```

---

## ⚙️ Parâmetros de Backup

### Parâmetros do Método executeBackup

```dart
Future<Result<BackupExecutionResult>> executeBackup({
  required SqlServerConfig config,        // Configuração do banco
  required String outputDirectory,         // Diretório de saída
  BackupType backupType = BackupType.full,
  String? customFileName,                  // Nome customizado (opcional)
  bool truncateLog = true,                 // Truncar log após backup
  bool enableChecksum = false,             // Habilitar CHECKSUM
  bool verifyAfterBackup = false,          // Verificar integridade
})
```

### Truncate Log

- **Quando aplicável**: Apenas para `BackupType.log`
- **Comportamento**:
  - `truncateLog = true`: Backup padrão que libera espaço (`BACKUP LOG ...`)
  - `truncateLog = false`: Backup COPY_ONLY (`BACKUP LOG ... WITH COPY_ONLY`)

### Enable Checksum

- **Quando aplicável**: Todos os tipos de backup
- **Comportamento**:
  - `enableChecksum = true`: Adiciona `CHECKSUM` ao comando BACKUP
  - `enableChecksum = false`: Não adiciona CHECKSUM

---

## 🚨 Tratamento de Erros

### Validação de Erros na Saída

O sistema verifica palavras-chave na saída (stdout + stderr):
- `error`
- `failed`
- `cannot`
- `unable`

Se encontradas, o backup é considerado como falha.

### Validações de Backup Criado

Após executar o backup, o sistema:

1. Aguarda até 10 segundos (20 tentativas de 500ms) para o arquivo ser criado
2. Verifica se o arquivo existe
3. Calcula o tamanho do arquivo
4. Valida que o tamanho é maior que 0 bytes

### Mensagens de Erro Comuns

1. **Arquivo não criado**
   ```
   Arquivo de backup não foi criado em: <path>
   ```

2. **Arquivo vazio**
   ```
   Arquivo de backup foi criado mas está vazio
   ```

3. **Erro na execução**
   ```
   Erro ao executar backup SQL Server
   STDOUT: <output>
   STDERR: <error>
   ```

---

## 📋 Requisitos do Sistema

### Ferramentas Necessárias

1. **sqlcmd**: Ferramenta de linha de comando do SQL Server

### Caminhos de Instalação Padrão

#### SQL Server 2019/2022

```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn
```

#### SQL Server 2017

```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn
```

#### SQL Server 2014

```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\120\Tools\Binn
```

### Configuração do PATH

O `sqlcmd` geralmente já está no PATH quando o SQL Server está instalado. Se não estiver, adicione o caminho acima ao PATH do sistema. Consulte `docs/path_setup.md` para instruções detalhadas.

---

## 🔄 Fluxo de Execução

### 1. Preparação

- Valida configuração do banco
- Cria diretório de saída se não existir
- Gera nome do arquivo com timestamp
- Normaliza e escapa caminho do arquivo

### 2. Construção do Comando SQL

- Determina tipo de backup (Full, Differential, Log)
- Adiciona CHECKSUM se `enableChecksum = true`
- Adiciona COPY_ONLY se `truncateLog = false` (apenas Log)
- Constrói comando `BACKUP DATABASE` ou `BACKUP LOG`

### 3. Execução do Backup

- Monta argumentos do `sqlcmd`
- Adiciona autenticação (`-U`/`-P` ou `-E`)
- Executa `sqlcmd` com timeout de 2 horas
- Monitora saída para erros

### 4. Validação

- Aguarda criação do arquivo (até 10 segundos)
- Verifica existência do arquivo
- Calcula tamanho do arquivo
- Valida que tamanho > 0

### 5. Verificação de Integridade (Opcional)

- Se `verifyAfterBackup = true`, executa `RESTORE VERIFYONLY`
- Adiciona `WITH CHECKSUM` se `enableChecksum = true`
- Timeout: 30 minutos
- Registra warning se falhar (não falha o backup)

### 6. Retorno

- Retorna `BackupExecutionResult` com:
  - `backupPath`: Caminho do arquivo criado
  - `fileSize`: Tamanho em bytes
  - `duration`: Duração da execução
  - `databaseName`: Nome do banco de dados

---

## 🎯 Integração com o Sistema

### BackupOrchestratorService

O `BackupOrchestratorService` integra o backup SQL Server com:

- Compressão (ZIP/RAR)
- Envio para destinos (Local, FTP, Google Drive)
- Histórico de backups
- Logs de execução
- Notificações por e-mail

### ScheduleDialog

Na UI, o usuário pode configurar:

- Tipo de backup (Full, Differential, Log)
- Truncate Log (apenas para Log)
- Enable Checksum (apenas para SQL Server)
- Verificação após backup
- Compressão (ZIP/RAR)
- Destinos de envio

---

## 📊 Comparação com Outros Bancos

| Característica          | SQL Server              | Sybase                    | PostgreSQL                      |
| ----------------------- | ----------------------- | ------------------------- | ------------------------------- |
| Backup Full             | ✅                      | ✅                        | ✅                              |
| Backup Differential     | ✅                      | ❌ (convertido para Full) | ✅                              |
| Backup Log              | ✅                      | ✅                        | ✅                              |
| Banco ONLINE            | ✅                      | ✅                        | ✅                              |
| Verificação Integridade | ✅ (RESTORE VERIFYONLY) | ✅ (dbverify)             | ✅ (pg_verifybackup/pg_restore) |
| CHECKSUM                | ✅                      | ❌                        | ✅ (pg_basebackup)              |
| Compressão              | ✅ (ZIP/RAR)            | ✅ (ZIP/RAR)              | ✅ (ZIP/RAR)                    |

---

## 🔧 Limitações Conhecidas

1. **Timeout**: 2 horas para backup, 30 minutos para verificação
2. **Arquivo Único**: Cada backup cria um arquivo único (`.bak` ou `.trn`)
3. **NOINIT**: Usa `NOINIT` para anexar ao arquivo existente (pode crescer indefinidamente)
4. **Autenticação**: Requer credenciais válidas ou acesso Windows

---

## 📝 Notas de Implementação

### Escapamento de Caminhos

Caminhos são normalizados e escapados para uso em comandos SQL:

```dart
final normalizedPath = backupPath.replaceAll('\\', '/');
final escapedBackupPath = normalizedPath.replaceAll("'", "''");
```

### Normalização de Caminhos

- Barras invertidas (`\`) são convertidas para barras normais (`/`)
- Aspas simples (`'`) são duplicadas (`''`) para escape SQL

### Nomenclatura de Arquivos

- **Full/Differential**: `<database>_<type>_<timestamp>.bak`
- **Log**: `<database>_log_<timestamp>.trn`
- **Timestamp**: Formato ISO8601 com `:` substituído por `-`

### Tratamento de Autenticação

```dart
if (config.username.isNotEmpty) {
  arguments.addAll(['-U', config.username]);
  if (config.password.isNotEmpty) {
    arguments.addAll(['-P', config.password]);
  }
} else {
  arguments.add('-E'); // Windows Authentication
}
```

### Detecção de Erros

O sistema verifica palavras-chave na saída combinada (stdout + stderr):
- Não depende apenas do exit code
- Detecta erros mesmo quando exit code é 0

---

## 🎓 Referências

- Documentação Microsoft SQL Server
- `docs/path_setup.md` - Configuração de PATH
- `lib/infrastructure/external/process/sql_server_backup_service.dart` - Implementação principal
- `lib/domain/entities/sql_server_config.dart` - Entidade de configuração

---

## ✅ Checklist de Implementação

- [x] Entidade SqlServerConfig criada
- [x] Interface ISqlServerBackupService definida
- [x] SqlServerBackupService implementado
- [x] Suporte a Full, Differential e Log backups
- [x] Suporte a CHECKSUM
- [x] Verificação de integridade (RESTORE VERIFYONLY)
- [x] Teste de conexão
- [x] Listagem de bancos de dados
- [x] Tratamento de erros específicos
- [x] Integração com BackupOrchestratorService
- [x] UI para configuração
- [x] UI para agendamento
- [x] Compressão de backups
- [x] Envio para destinos

---

**Última atualização**: Dezembro 2024

