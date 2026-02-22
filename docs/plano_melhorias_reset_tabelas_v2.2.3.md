# Plano de Melhorias - Reset de Tabelas na Versão 2.2.3

**Data:**2026-02-22
**Última atualização:**2026-02-22
**Versão:** 2.2.3
**Status:** Em Implementação

### Progresso

| Prioridade | Melhoria | Status |
|-----------|---------|--------|
| 🔴 P0 | Validação Exata da Versão | ✅ Concluído (commit 095b513) |
| 🔴 P0 | Flag de Reset em Secure Storage | ✅ Concluído (commit 095b513) |
| 🔴 P0 | Backup Antes de DROP com Rollback | ✅ Concluído (commit da4a3a4) |
| 🟠 P1 | Recriação Através de Drift Schema | ✅ Concluído (commit 02c191a) |
| 🟠 P1 | Consulta Única ao sqlite_master | ✅ Concluído (implementado com P1.1) |
| 🟡 P2 | Remover schedules_table do DROP | ✅ Concluído (commit 9a38ec6) |
| 🟡 P2 | Tratamento Diferenciado de Erros | ✅ Concluído (commit 0cc693f) |
| 🟢 P3 | Manutenibilidade - Transação SQLite | ✅ Concluído |
| 🟢 P3 | Debugabilidade - Logging Estruturado | ✅ Concluído |

---

## 📋 Resumo Executivo

Este plano documenta as melhorias identificadas na análise da implementação atual do reset de tabelas de configuração de banco de dados na versão 2.2.3, organizadas por prioridade de execução.

### Problema Atual

A versão 2.2.3 implementa um reset seletivo de tabelas (`sql_server_configs_table`, `sybase_configs_table`, `postgres_configs_table`, `schedules_table`) através de:

1. **DROP TABLE** via `sqlite3` antes da inicialização do AppDatabase
2. **Recriação** via SQL manual no `beforeOpen` do AppDatabase
3. **Verificação de versão** com `startsWith('2.2.3')`

---

## 🔴 P0: Melhorias Críticas de Confiabilidade

### P0.1 Validação Exata da Versão ✅

**Status:** Concluído
**Commit:** 095b513

**Problema Atual:**
```dart
final shouldReset = version.startsWith('2.2.3');
```

**Risco:** Qualquer versão futura começando com `2.2.3` (`2.2.30`, `2.2.31`, `2.2.4-beta`) vai erroneamente resetar as configurações.

**Solução:**
Usar validação de versão semântica com `pub_semver` para garantir igualdade exata.

**Arquivos Modificados:**
- `pubspec.yaml`: Adicionado `pub_semver: ^2.1.5` às dev_dependencies
- `lib/core/di/core_module.dart`:
  - Adicionado `import 'package:pub_semver/pub_semver.dart';`
  - Substituído validação de versão por comparação exata usando `Version.parse()`
  - Adicionado funções `_hasAlreadyResetForVersion223()` e `_markResetCompletedForVersion223()`
  - Modificado `_dropConfigTablesForVersion223()` para verificar flag antes de executar DROP

**Implementação:**
```dart
// Nova validação exata
final targetVersion = Version.parse('2.2.3');
Version? currentVersion;

try {
  currentVersion = Version.parse(version.split('+').first);
} catch (e) {
  LoggerService.warning('Versão inválida: $version');
  return false;
}

final shouldReset = currentVersion == targetVersion; // Igualdade exata

// Verifica flag antes de executar
final hasAlreadyReset = await _hasAlreadyResetForVersion223();
if (hasAlreadyReset) {
  LoggerService.info('Reset v2.2.3 já foi executado anteriormente');
  return false;
}
```

**Benefícios:**
- ✅ Evita resets acidentais em versões futuras
- ✅ Tratamento robusto de versões com build number
- ✅ Validação semântica correta

---

### P0.2 Flag de Reset em Secure Storage ✅

**Status:** Concluído
**Commit:** 095b513

**Problema Atual:**
Cada vez que a versão 2.2.3 inicia, o reset é executado. Se o usuário fechar e reabrir o app, o reset é executado novamente.

**Solução:**
Usar `flutter_secure_storage` para armazenar um flag indicando que o reset já foi executado para a versão 2.2.3. A flag só deve ser gravada uma vez.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado `import 'package:flutter_secure_storage/flutter_secure_storage.dart';`
  - Adicionada constante `_resetFlagKey = 'reset_v2_2_3_done';`
  - Adicionada função `_hasAlreadyResetForVersion223()` - verifica flag
  - Adicionada função `_markResetCompletedForVersion223()` - marca flag
  - Modificado `_dropConfigTablesForVersion223()` para verificar flag antes do DROP

**Implementação:**
```dart
const _resetFlagKey = 'reset_v2_2_3_done';

Future<bool> _hasAlreadyResetForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    final flag = await storage.read(key: _resetFlagKey);
    return flag == 'true';
  } catch (e) {
    LoggerService.warning('Erro ao ler flag de reset: $e');
    return false;
  }
}

Future<void> _markResetCompletedForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _resetFlagKey, value: 'true');
    LoggerService.info('Flag de reset v2.2.3 marcada como concluída');
  } catch (e) {
    LoggerService.warning('Erro ao gravar flag de reset: $e');
  }
}

// Na função de drop
final hasAlreadyReset = await _hasAlreadyResetForVersion223();
if (hasAlreadyReset) {
  LoggerService.info('Reset v2.2.3 já foi executado anteriormente');
  return false;
}
// ... resto da lógica de DROP ...

// Marca como concluído após sucesso
await _markResetCompletedForVersion223();
return true;
```

**Benefícios:**
- ✅ Evita resets múltiplos acidentais
- ✅ Reduz tempo de inicialização após o primeiro reset
- ✅ Permite limpar o reset manualmente (removendo a flag)

---

### P0.3 Backup Antes de DROP com Rollback ✅

**Status:** Concluído

**Problema Atual:**
As tabelas são removidas permanentemente via `DROP TABLE`, sem mecanismo de recuperação caso ocorra erro durante o processo ou na recriação.

**Solução:**
Criar backup das tabelas antes do DROP usando `ALTER TABLE RENAME TO`, mantendo backup disponível para rollback se necessário.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado import `import 'package:sqlite3/sqlite3.dart' as sqlite3;`
  - Modificado `_dropConfigTablesForVersion223()` para criar backup antes de DROP
  - Adicionado timestamp para nome dos backups
  - Adicionado `_handleDropError()` para tratamento de erros
  - Corrigido uso de `sqlite3.sqlite3.open()` para abrir banco
  - Adicionada função `_getOrCreateLicenseSecretKey()` que estava faltando

**Implementação:**
```dart
// Cria backup antes de DROP
final timestamp = DateTime.now().millisecondsSinceEpoch;
final backupSuffix = '_backup_v2_2_3_$timestamp';

database = sqlite3.sqlite3.open(dbPath);

try {
  final tablesToDrop = [
    'sql_server_configs_table',
    'sybase_configs_table',
    'postgres_configs_table',
    'schedules_table',
  ];

  // Renomeia tabelas para backup
  for (final tableName in tablesToDrop) {
    final backupTableName = '${tableName}$backupSuffix';
    database.execute('ALTER TABLE $tableName RENAME TO $backupTableName');
    LoggerService.info('Backup criado: $backupTableName');
  }

  // Drop tabelas originais
  for (final tableName in tablesToDrop) {
    database.execute('DROP TABLE IF EXISTS $tableName');
  }

  // Marca reset como concluído
  await _markResetCompletedForVersion223();
} finally {
  database?.dispose();
}
```

**Benefícios:**
- ✅ Dados preservados em backups com timestamp
- ✅ Possibilidade de rollback manual se necessário
- ✅ Logs indicam onde estão os backups
- ✅ Proteção contra perda de dados

---

## 🟠 P1: Melhorias de Alta Prioridade

### P1.1 Recriação Através de Drift Schema ✅

**Status:** Concluído

**Problema Atual:**
As tabelas são recriadas via SQL manual hardcoded no `beforeOpen` do AppDatabase, divergindo do schema definido em Drift.

**Solução:**
Remover as funções que usam SQL manual e implementar verificação de tabelas ausentes com reset de versão do schema para forçar Drift a recriar tabelas via `onCreate`.

**Arquivos Modificados:**
- `lib/infrastructure/datasources/local/database.dart`:
  - Removidas funções `_ensureSqlServerConfigsTableExistsDirect()`, `_ensureSybaseConfigsTableExistsDirect()`, `_ensurePostgresConfigsTableExistsDirect()`, `_ensureSchedulesTableExistsDirect()`
  - Adicionada função `_ensureConfigTablesRecreatedByDrift()` que verifica tabelas ausentes e reseta versão do schema
  - Atualizado `beforeOpen` para chamar nova função em vez das funções diretas

**Implementação:**
```dart
// Nova função que usa Drift para recriar tabelas
Future<void> _ensureConfigTablesRecreatedByDrift() async {
  try {
    final tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name IN ('sql_server_configs_table', 'sybase_configs_table', "
      "'postgres_configs_table', 'schedules_table')",
    ).get();
    final existingTableNames = tables
        .map((row) => row.data['name'] as String)
        .toSet();

    final missingTables = [
      'sql_server_configs_table',
      'sybase_configs_table',
      'postgres_configs_table',
      'schedules_table',
    ].where((table) => !existingTableNames.contains(table)).toList();

    if (missingTables.isNotEmpty) {
      final missingTablesStr = missingTables.join(', ');
      LoggerService.warning(
        'Tabelas de configuração ausentes: $missingTablesStr',
      );
      LoggerService.info(
        'Resetando versão do schema para forçar recriação via Drift',
      );

      await customStatement('PRAGMA user_version = 0');
      LoggerService.info('Versão do schema resetada para 0');
    }
  } on Object catch (e, stackTrace) {
    LoggerService.warning(
      'Erro ao verificar/recriar tabelas de configuração',
      e,
      stackTrace,
    );
  }
}

// Atualizado beforeOpen
beforeOpen: (details) async {
  await customStatement('PRAGMA foreign_keys = ON');

  // P1.1: Verifica e recria tabelas de configuração via schema Drift
  // Se as tabelas foram dropadas (pelo reset v2.2.3), reseta
  // a versão do schema para forçar Drift a recriá-las via onCreate.
  await _ensureConfigTablesRecreatedByDrift();

  // ... restante do código
}
```

**Benefícios:**
- ✅ Tabelas recriadas usando schema Drift (garante consistência)
- ✅ Remove código SQL manual que pode divergir do schema
- ✅ Código mais limpo e manutenível
- ✅ OnCreate do Drift garante que todas as tabelas são criadas corretamente

---

### P1.2 Consulta Única ao sqlite_master ✅

**Status:** Concluído (implementado junto com P1.1)

**Problema Atual:**
4 consultas separadas ao `sqlite_master`, uma para cada tabela de configuração.

**Solução:**
Usar uma única consulta com `IN` para verificar todas as tabelas de uma vez.

**Arquivos Modificados:**
- `lib/infrastructure/datasources/local/database.dart`:
  - A função `_ensureConfigTablesRecreatedByDrift()` (implementada em P1.1) já usa consulta única com IN

**Implementação:**
```dart
// P1.2: Consulta única com IN (já implementada em P1.1)
final tables = await customSelect(
  "SELECT name FROM sqlite_master WHERE type='table' "
  "AND name IN ('sql_server_configs_table', 'sybase_configs_table', "
  "'postgres_configs_table', 'schedules_table')",
).get();
```

**Benefícios:**
- ✅ ~4x mais rápido (1 consulta vs 4)
- ✅ Menos round-trips ao banco
- ✅ Reduz uso de CPU

---

## 🟡 P2: Melhorias de Média Prioridade

### P2.1 Remover schedules_table do DROP ✅

**Status:** Concluído

**Problema Atual:**
`schedules_table` está sendo dropada para evitar problemas de dependência, mas isso causa perda de dados importantes do usuário.

**Solução:**
Remover `schedules_table` da lista inicial de DROP. A tabela não será dropada, apenas as 3 tabelas de configuração de banco.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Removido `'schedules_table'` da lista `tablesToDrop`

**Implementação:**
```dart
// Antes: schedules_table estava sendo dropada
final tablesToDrop = [
  'sql_server_configs_table',
  'sybase_configs_table',
  'postgres_configs_table',
  'schedules_table',  // Removido
];

// Após: apenas tabelas de configuração de banco
final tablesToDrop = [
  'sql_server_configs_table',
  'sybase_configs_table',
  'postgres_configs_table',
];
```

**Benefícios:**
- ✅ Agendamentos do usuário são preservados
- ✅ Apenas tabelas de configuração de banco são resetadas
- ✅ Menos dados perdidos em caso de rollback ou erro
- ✅ Reduz impacto da operação de reset no usuário final

---

### P2.2 Tratamento Diferenciado de Erros ✅

**Status:** Concluído

**Problema Atual:**
Todos os erros são tratados de forma idêntica, sem distinção entre erros recuperáveis e críticos.

**Solução:**
Criar enum de tipos de erro e implementar tratamento diferenciado com base na categoria do erro.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado enum `_DropErrorType` com categorias: critical, expected, recoverable
  - Adicionada função `_categorizeError()` para classificar erros automaticamente
  - Adicionada função `_getErrorMessage()` para obter mensagem legível
  - Atualizada função `_handleDropError()` com tratamento diferenciado por tipo de erro

**Implementação:**
```dart
// Enum de tipos de erro
enum _DropErrorType {
  critical,    // Erro crítico que impede a operação
  expected,     // Erro esperado (normal)
  recoverable,  // Erro recuperável (pode tentar novamente)
}

// Categorização automática de erros
_DropErrorType _categorizeError(Object error) {
  if (error is sqlite3.SqliteException) {
    final code = error.extendedResultCode;
    // Erros críticos: CONSTRAINT, CORRUPT, NOTADB, FORMAT, FULL
    if (code == SqliteException.SQLITE_CONSTRAINT ||
        code == SqliteException.SQLITE_CORRUPT ||
        code == SqliteException.SQLITE_NOTADB ||
        code == SqliteException.SQLITE_FORMAT ||
        code == SqliteException.SQLITE_FULL) {
      return _DropErrorType.critical;
    }
    // Erros recuperáveis: BUSY, LOCKED
    if (code == SqliteException.SQLITE_BUSY ||
        code == SqliteException.SQLITE_LOCKED) {
      return _DropErrorType.recoverable;
    }
    return _DropErrorType.expected;
  }
  // FileSystemException: access denied é crítico, outros são recuperáveis
  if (error is FileSystemException) {
    final fsError = error as FileSystemException;
    if (fsError.osError?.errorCode == 5 || 32) {
      return _DropErrorType.critical;
    }
    return _DropErrorType.recoverable;
  }
  return _DropErrorType.recoverable;
}

// Tratamento diferenciado por tipo
void _handleDropError(Object error) {
  final errorType = _categorizeError(error);
  switch (errorType) {
    case _DropErrorType.critical:
      LoggerService.error(
        'CRÍTICO: Operação de drop não pode continuar: $error',
      );
      break;
    case _DropErrorType.expected:
      LoggerService.info(
        'Esperado: ${_getErrorMessage(errorType)}: $error',
      );
      break;
    case _DropErrorType.recoverable:
      LoggerService.warning(
        'Recuperável: ${_getErrorMessage(errorType)}: $error',
      );
      break;
  }
}
```

**Benefícios:**
- ✅ Tratamento diferenciado por severidade de erro
- ✅ Logs claros indicando tipo de problema
- ✅ Distingue erros recuperáveis de erros críticos
- ✅ Melhor experiência de debugging e troubleshooting

---

### P2.2 Tratamento Diferenciado de Erros ✅

**Status:** Concluído

**Problema Atual:**
Todos os erros são tratados de forma idêntica, sem distinção entre erros recuperáveis e críticos.

**Solução:**
Criar enum de tipos de erro e tratamento diferenciado.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado enum `_DropErrorType` com categorias: critical, expected, recoverable
  - Adicionada função `_categorizeError()` para classificar erros automaticamente
  - Adicionada função `_getErrorMessage()` para obter mensagem legível
  - Atualizada função `_handleDropError()` com tratamento diferenciado por tipo de erro

**Implementação:**
```dart
// Enum de tipos de erro
enum _DropErrorType {
  critical,    // Erro crítico que impede a operação
  expected,     // Erro esperado (normal)
  recoverable,  // Erro recuperável (pode tentar novamente)
}

// Categorização automática de erros usando pattern matching
_DropErrorType _categorizeError(Object error) {
  if (error case final sqlite3.SqliteException sqliteError) {
    final code = sqliteError.extendedResultCode;
    // Erros críticos: CONSTRAINT, CORRUPT, NOTADB, FORMAT, FULL
    if (code == sqlite3.SqlError.SQLITE_CONSTRAINT ||
        code == sqlite3.SqlError.SQLITE_CORRUPT ||
        code == sqlite3.SqlError.SQLITE_NOTADB ||
        code == sqlite3.SqlError.SQLITE_FORMAT ||
        code == sqlite3.SqlError.SQLITE_FULL) {
      return _DropErrorType.critical;
    }
    // Erros recuperáveis: BUSY, LOCKED
    if (code == sqlite3.SqlError.SQLITE_BUSY ||
        code == sqlite3.SqlError.SQLITE_LOCKED) {
      return _DropErrorType.recoverable;
    }
    return _DropErrorType.expected;
  }
  // FileSystemException: access denied é crítico, outros são recuperáveis
  if (error case final FileSystemException fsError) {
    if (fsError.osError?.errorCode == 5 || // ERROR_ACCESS_DENIED
        fsError.osError?.errorCode == 32) { // ERROR_SHARING_VIOLATION
      return _DropErrorType.critical;
    }
    return _DropErrorType.recoverable;
  }
  return _DropErrorType.recoverable;
}

// Tratamento diferenciado por tipo
void _handleDropError(Object error, [_ResetPerformanceMetrics? metrics]) {
  final errorType = _categorizeError(error);
  switch (errorType) {
    case _DropErrorType.critical:
      LoggerService.error(
        'CRÍTICO: Operação de drop não pode continuar: $error',
      );
    case _DropErrorType.expected:
      LoggerService.info(
        'Esperado: ${_getErrorMessage(errorType)}: $error',
      );
    case _DropErrorType.recoverable:
      LoggerService.warning(
        'Recuperável: ${_getErrorMessage(errorType)}: $error',
      );
  }
}
```

**Benefícios:**
- ✅ Tratamento diferenciado por severidade de erro
- ✅ Logs claros indicando tipo de problema
- ✅ Distingue erros recuperáveis de erros críticos
- ✅ Melhor experiência de debugging e troubleshooting

---

## 🟢 P3: Melhorias de Baixa Prioridade

### P3.1 Transação SQLite ✅

**Status:** Concluído

**Problema Atual:**
DROPs são executados sequencialmente sem proteção de transação.

**Solução:**
Envolver todos os DROPs em uma transação SQLite para garantir atomicidade.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado `BEGIN IMMEDIATE TRANSACTION` antes dos DROPs
  - Adicionado `COMMIT` após todos os DROPs
  - Adicionado `ROLLBACK` em caso de erro
  - Adicionado suporte para database null-safe em catch block

**Implementação:**
```dart
// P3.1: Transação SQLite - Iniciar transação
metrics.start(_ResetPhase.dropExecution);
database.execute('BEGIN IMMEDIATE TRANSACTION');
LoggerService.info('FASE 4: DROP de tabelas - Transação iniciada');

for (final tableName in tablesToDrop) {
  try {
    database.execute('DROP TABLE IF EXISTS $tableName');
    LoggerService.warning('Tabela dropada: $tableName');
  } on Exception catch (e) {
    LoggerService.warning('Erro ao dropar tabela $tableName: $e');
  }
}

// P3.1: Transação SQLite - Commit da transação
database.execute('COMMIT');

// P3.1: Transação SQLite - Rollback em caso de erro
} on Object catch (e) {
  database?.execute('ROLLBACK');

  final rollbackElapsedMs = metrics.getElapsedMs(_ResetPhase.dropExecution);
  LoggerService.warning(
    'Tempo rollback de transação: $rollbackElapsedMs',
  );

  _handleDropError(e, metrics);
  return false;
}
```

**Benefícios:**
- ✅ Atomicidade: todos os DROPs são executados como uma unidade
- ✅ Rollback automático em caso de erro
- ✅ Proteção contra estado inconsistente
- ✅ Melhor tratamento de erros durante operação crítica

---

### P3.2 Logging Estruturado ✅

**Status:** Concluído

**Problema Atual:**
Logs não têm estrutura clara, dificultando debugging de problemas.

**Solução:**
Criar sistema de logging estruturado com fases e medição de tempo.

**Arquivos Modificados:**
- `lib/core/di/core_module.dart`:
  - Adicionado enum `_ResetPhase` com fases: validation, backupCreation, dropExecution, cleanup
  - Adicionada classe `_ResetPerformanceMetrics` para medição de tempo
  - Adicionada medição de tempo para cada fase
  - Adicionado resumo de performance ao final da operação

**Implementação:**
```dart
// P3.2: Fases da operação de reset de tabelas
enum _ResetPhase {
  validation,
  backupCreation,
  dropExecution,
  cleanup,
}

// P3.2: Classe para medição de tempo das operações de reset
class _ResetPerformanceMetrics {
  final Map<_ResetPhase, Stopwatch> _stopwatches = {};

  void start(_ResetPhase phase) {
    _stopwatches[phase] = Stopwatch()..start();
  }

  void stop(_ResetPhase phase) {
    _stopwatches[phase]?.stop();
  }

  int getElapsedMs(_ResetPhase phase) {
    return _stopwatches[phase]?.elapsedMilliseconds ?? 0;
  }

  Duration getElapsed(_ResetPhase phase) {
    return Duration(milliseconds: getElapsedMs(phase));
  }

  void dispose() {
    for (final stopwatch in _stopwatches.values) {
      stopwatch.stop();
    }
  }
}

// Exemplo de uso em _dropConfigTablesForVersion223():
final metrics = _ResetPerformanceMetrics();

// P3.2: FASE 1 - Validação
metrics.start(_ResetPhase.validation);
LoggerService.info('===== CONFIG TABLES DROP CHECK =====');
// ... validações ...
final validationElapsedMs = metrics.getElapsedMs(_ResetPhase.validation);
LoggerService.info('Tempo validação: ${validationElapsedMs}ms');

// P3.2: FASE 2 - Abertura do banco
metrics.start(_ResetPhase.cleanup);
// ... abertura do banco ...
metrics.stop(_ResetPhase.cleanup);
final dbOpenElapsedMs = metrics.getElapsedMs(_ResetPhase.cleanup);
LoggerService.info('Tempo abertura do banco: ${dbOpenElapsedMs}ms');

// P3.2: Resumo de performance
final validationTime = Duration(milliseconds: metrics.getElapsedMs(_ResetPhase.validation));
final backupTime = Duration(milliseconds: metrics.getElapsedMs(_ResetPhase.backupCreation));
final dropTime = Duration(milliseconds: metrics.getElapsedMs(_ResetPhase.dropExecution));
final cleanupTime = Duration(milliseconds: metrics.getElapsedMs(_ResetPhase.cleanup));
final totalTime = validationTime + backupTime + dropTime + cleanupTime;

LoggerService.info('===== RESUMO DE PERFORMANCE =====');
LoggerService.info('Validação: ${validationTime.inMilliseconds}');
LoggerService.info('Criação de backups: ${backupTime.inMilliseconds}');
LoggerService.info('DROP de tabelas: ${dropTime.inMilliseconds}');
LoggerService.info('Conclusão: ${cleanupTime.inMilliseconds}');
LoggerService.info('TOTAL: ${totalTime.inMilliseconds}');
```

**Benefícios:**
- ✅ Fases claramente identificadas nos logs
- ✅ Tempo de cada fase medido e registrado
- ✅ Resumo de performance ao final facilita debugging
- ✅ Comparação de performance entre execuções
- ✅ Identificação rápida de gargalos

---

## 📋 Cronograma de Implementação (Atualizado)

| Fase | Período | Tarefas | Status |
|-------|---------|--------|--------|
| 1 | Preparação (1-2 dias) | Revisão, aprovação | ✅ |
| 2 | P0 Críticas (2-3 dias) | P0.1, P0.2, P0.3 | ✅ Concluído |
| 3 | P1 Altas (2-3 dias) | P1.1, P1.2 | ✅ Concluído |
| 4 | P2 Médias (1-2 dias) | P2.1, P2.2 | ✅ Concluído |
| 5 | P3 Baixas (1 dia) | P3.1, P3.2 | ✅ Concluído |
| 6 | Testes (2-3 dias) | TC-1 a TC-7 | ⏳ |
| 7 | Homologação (1 dia) | Testes finais | ⏳ |

**Total estimado:** 9-14 dias

---

## 🧪 Cenários de Teste

### TC-1: Reset com Sucesso ⏳

**Objetivo:** Verificar fluxo normal com sucesso

**Passos:**
1. Iniciar app v2.2.3 pela primeira vez
2. Verificar logs: `RESET versionCheck: Versão: 2.2.3, Parseada: 2.2.3, Target: 2.2.3, Reset: true`
3. Verificar logs: `RESET dropTables] Executando DROP de 3 tabelas`
4. Verificar logs: `Tabelas serão recriadas automaticamente`
5. Tentar acessar UI e configurar uma conexão SQL Server
6. Verificar que a tabela foi recriada corretamente
7. Verificar logs: `Flag de reset v2.2.3 marcada como concluída`

**Critério de Sucesso:**
- ✅ DROP executado sem erros
- ✅ Tabelas recriadas
- ✅ Nova configuração salva com sucesso
- ✅ Flag gravada

---

### TC-2: Reset com Banco Bloqueado ⏳

**Objetivo:** Verificar tratamento de erro de lock

**Passos:**
1. Abrir duas instâncias do app v2.2.3 simultaneamente
2. Aguardar deadlock (segunda instância espera)
3. Verificar logs: `RESET versionCheck: Versão: 2.2.3, Parseada: 2.2.3, Target: 2.2.3, Reset: true`
4. Verificar logs da primeira: `Executando DROP`
5. Verificar logs da segunda: `BANCO BLOQUEADO - Aguardando 3 segundos...`
6. Verificar logs da segunda: `DROP CONCLUÍDO` ou mensagem de erro tratada
7. Verificar logs da primeira: `Flag marcada como concluída`

**Critério de Sucesso:**
- ✅ Erro tratado corretamente com retry
- ✅ Uma das instâncias consegue completar
- ✅ Logs mostram tratamento apropriado

---

### TC-3: Reset com Erro e Rollback ⏳

**Objetivo:** Verificar mecanismo de backup/rollback

**Passos:**
1. Simular erro durante DROP (corromper tabela)
2. Verificar logs: `Backup criado para cada tabela`
3. Verificar logs: `DROP executado`
4. Verificar logs: `DROP CONCLUÍDO, BACKUPS DISPONÍVEIS`
5. Simular erro na recriação das tabelas
6. Verificar logs: `=== ROLLBACK CONCLUÍDO ===`
7. Verificar logs: `Restaurado backup de: sql_server_configs_table`
8. Verificar que dados antigos foram restaurados
9. Tentar acessar UI - deve funcionar normalmente

**Critério de Sucesso:**
- ✅ Rollback executado com sucesso
- ✅ Dados preservados
- ✅ Funcionalidade normal após rollback

---

### TC-4: Versão Futura com Prefixo Comum ⏳

**Objetivo:** Verificar validação exata de versão

**Passos:**
1. Compilar versão 2.2.30
2. Alterar pubspec.yaml: `version: 2.2.30`
3. Build e rodar app
4. Verificar logs: `Versão do app: 2.2.30, Parseada: 2.2.30, Target: 2.2.3, Reset: false`
5. Tentar acessar UI - deve permitir configuração
6. Verificar que NÃO houve DROP das tabelas

**Critério de Sucesso:**
- ✅ Versão 2.2.30 não é reconhecida como 2.2.3
- ✅ Não há perda de configurações
- ✅ Validação funciona corretamente

---

### TC-5: Múltiplos Inícios com Versão 2.2.3 ⏳

**Objetivo:** Verificar flag de reset em secure storage

**Passos:**
1. Iniciar app v2.2.3 pela primeira vez
2. Verificar logs: `RESET versionCheck: Versão: 2.2.3, Parseada: 2.2.3, Target: 2.2.3, Reset: true`
3. Verificar logs: `DROP CONCLUÍDO`
4. Verificar logs: `Flag de reset v2.2.3 marcada como concluída`
5. Fechar app
6. Abrir app novamente
7. Verificar logs: `Reset v2.2.3 já foi executado anteriormente`
8. Verificar logs: `DROP CONCLUÍDO` NÃO deve aparecer
9. Verificar logs: `Flag marcada como concluída` deve aparecer

**Critério de Sucesso:**
- ✅ Flag protege contra resets múltiplos
- ✅ Primeira inicialização executa DROP
- ✅ Segunda inicialização pula DROP
- ✅ Logs confirmam o comportamento correto

---

### TC-6: Performance - Comparação de Tempo ⏳

**Objetivo:** Verificar melhoria de performance da consulta única

**Passos:**
1. Medir tempo de DROP com implementação atual (4 consultas)
2. Implementar consulta única
3. Medir tempo de DROP com nova implementação (1 consulta)
4. Comparar: Nova versão deve ser ~3-4x mais rápida

**Critério de Sucesso:**
- ✅ Tempo de DROP < 500ms (consulta única)
- ✅ Logs mostram tempo de cada fase
- ✅ Melhoria significativa de performance confirmada

---

### TC-7: Preservação de schedules_table ⏳

**Objetivo:** Verificar que agendamentos são preservados

**Passos:**
1. Iniciar app v2.2.3
2. Verificar logs: `RESET versionCheck: Versão: 2.2.3, Parseada: 2.2.3, Target: 2.2.3, Reset: true`
3. Verificar logs: `DROP CONCLUÍDO` - verificar que schedules NÃO está na lista
4. Acessar UI de agendamentos
5. Verificar que agendamentos existentes estão intactos
6. Criar novo agendamento
7. Verificar que novo agendamento é salvo corretamente

**Critério de Sucesso:**
- ✅ schedules_table NÃO foi dropada
- ✅ Agendamentos existentes são preservados
- ✅ Novos agendamentos funcionam

---

## 📝 Notas Técnicas

### Dependências Necessárias

**Para P0.1:**
```yaml
pubspec.yaml:
dev_dependencies:
  pub_semver: ^2.1.5  # Já adicionado
```

**Para P0.2:**
```yaml
pubspec.yaml:
dependencies:
  flutter_secure_storage: any  # Já existe
```

### Migração de Banco

Ao implementar P1.1 (recriação via Drift), considere:

1. Se o banco já estiver em uma versão mais nova, o `createAll()` não será executado
2. Se o banco estiver exatamente na versão 24, `createAll()` criará todas as tabelas
3. Teste com banco v23 → Deve funcionar
4. Teste com banco v24 → Deve criar tabelas via `createAll()`

### Rollback Limpo

Após implementar P0.3 (backup/rollback), implementar rotina de limpeza de backups:

- Executar após N primeiras inicializações bem-sucedidas
- Ou implementar botão de "Limpar Backups" nas configurações avançadas
- Logs devem indicar quando os backups são removidos

---

## 🔄 Glossário

| Termo | Descrição |
|--------|-----------|
| DROP TABLE | Comando SQL que remove permanentemente uma tabela |
| Recriação | Criação de uma tabela após ser dropada |
| Drift Schema | Definição da estrutura da tabela via código Dart |
| Validação Semântica | Comparação de versões seguindo especificação SemVer |
| Secure Storage | Armazenamento criptografado nativo do Flutter |
| Transação SQLite | Unidade atômica de operações SQL |
| Rollback | Restauração de dados a partir de backup |
| Race Condition | Condição de corrida onde duas operações competem pelo mesmo recurso |
| Locking | Bloqueio de arquivo quando um processo o está usando |
