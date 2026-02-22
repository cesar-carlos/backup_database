# Plano de Melhorias - Reset de Tabelas na Versão 2.2.3

**Data:** 2026-02-22
**Versão:** 2.2.3
**Status:** Em Planejamento

---

## 📋 Resumo Executivo

Este plano documenta as melhorias identificadas na análise da implementação atual do reset de tabelas de configuração de banco de dados na versão 2.2.3, organizadas por prioridade de execução.

### Problema Atual

A versão 2.2.3 implementa um reset seletivo de tabelas (`sql_server_configs_table`, `sybase_configs_table`, `postgres_configs_table`, `schedules_table`) através de:

1. **DROP TABLE** via `sqlite3` antes da inicialização do AppDatabase
2. **Recriação** via SQL manual no `beforeOpen` do AppDatabase
3. **Verificação de versão** com `startsWith('2.2.3')`

### Prioridades de Melhoria

| Prioridade | Categoria | Melhorias | Estimativa de Esforço |
|-----------|---------|----------|----------------------|
| 🔴 P0 | Confiabilidade | Validação exata da versão | Médio |
| 🔴 P0 | Confiabilidade | Flag de reset em secure storage | Médio |
| 🔴 P0 | Confiabilidade | Backup antes de DROP | Alto |
| 🟠 P1 | Confiabilidade | Recriação via Drift schema | Alto |
| 🟠 P1 | Desempenho | Consulta única ao sqlite_master | Baixo |
| 🟡 P2 | Confiabilidade | Remover schedules_table do DROP | Baixo |
| 🟡 P2 | UX | Tratamento diferenciado de erros | Médio |
| 🟢 P3 | Manutenibilidade | Transação SQLite | Baixo |
| 🟢 P3 | Debugabilidade | Logging estruturado | Baixo |

---

## 🔴 P0: Melhorias Críticas de Confiabilidade

### P0.1 Validação Exata da Versão

**Problema Atual:**
```dart
final shouldReset = version.startsWith('2.2.3');
```

**Risco:** Qualquer versão futura começando com `2.2.3` (`2.2.30`, `2.2.31`, `2.2.4-beta`) vai erroneamente resetar as configurações.

**Solução:**
Usar validação de versão semântica com `pub_semver` para garantir igualdade exata.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`
- `pubspec.yaml` (adicionar `pub_semver` se necessário)

**Implementação:**

```dart
import 'package:pub_semver/pub_semver.dart';

Version? _parseVersion(String versionStr) {
  try {
    return Version.parse(versionStr.split('+').first);
  } catch (e) {
    return null;
  }
}

Future<bool> _shouldResetForVersion(String version) async {
  final parsedVersion = _parseVersion(version);
  if (parsedVersion == null) return false;

  final targetVersion = Version(2, 2, 3);
  final shouldReset = parsedVersion == targetVersion;

  LoggerService.info(
    'Versão: $version, Parseada: $parsedVersion, '
    'Target: $targetVersion, Reset: $shouldReset',
  );

  return shouldReset;
}
```

**Benefícios:**
- ✅ Evita resets acidentais em versões futuras
- ✅ Tratamento robusto de versões com build number
- ✅ Validação semântica correta

---

### P0.2 Flag de Reset em Armazenamento Seguro

**Problema Atual:**
Cada vez que a versão 2.2.3 inicia, o reset é executado, mesmo que já tenha sido feito anteriormente. Se o usuário fechar e reabrir o app, o reset é executado novamente.

**Solução:**
Usar `flutter_secure_storage` para armazenar um flag indicando que o reset já foi executado para a versão 2.2.3.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _resetFlagKey = 'reset_v2_2_3_done';

Future<bool> _hasAlreadyResetForVersion223() async {
  final storage = const FlutterSecureStorage();
  try {
    final flag = await storage.read(key: _resetFlagKey);
    return flag == 'true';
  } catch (e) {
    LoggerService.warning('Erro ao ler flag de reset: $e');
    return false;
  }
}

Future<void> _markResetCompletedForVersion223() async {
  final storage = const FlutterSecureStorage();
  try {
    await storage.write(key: _resetFlagKey, value: 'true');
    LoggerService.info('Flag de reset v2.2.3 marcada como concluída');
  } catch (e) {
    LoggerService.warning('Erro ao gravar flag de reset: $e');
  }
}

Future<void> _clearResetFlagForVersion223() async {
  final storage = const FlutterSecureStorage();
  try {
    await storage.delete(key: _resetFlagKey);
    LoggerService.info('Flag de reset v2.2.3 removida');
  } catch (e) {
    LoggerService.warning('Erro ao remover flag de reset: $e');
  }
}
```

**Fluxo atualizado:**

```dart
Future<bool> _dropConfigTablesForVersion223() async {
  // Verifica se já foi feito
  final hasReset = await _hasAlreadyResetForVersion223();
  if (hasReset) {
    LoggerService.info('Reset v2.2.3 já foi executado anteriormente');
    return false;
  }

  // ... lógica de DROP ...

  // Marca como concluído
  await _markResetCompletedForVersion223();

  return true;
}
```

**Benefícios:**
- ✅ Evita resets múltiplos acidentais
- ✅ Reduz tempo de inicialização após o primeiro reset
- ✅ Permite limpar o reset manualmente (removendo a flag)

---

### P0.3 Backup Antes de DROP com Rollback

**Problema Atual:**
DROP TABLE destrói dados definitivamente. Se houver qualquer erro após o DROP (bug, crash, etc.), os dados são perdidos permanentemente.

**Solução:**
Implementar mecanismo de backup e rollback antes de executar o DROP.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
Future<void> _dropConfigTablesWithBackup(String dbPath) async {
  final database = await openSqliteApi(dbPath);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final backupSuffix = '_backup_v2_2_3_$timestamp';

  try {
    // 1. Criar backup de cada tabela
    for (final tableName in tablesToDrop) {
      await database.execute('ALTER TABLE $tableName RENAME TO ${tableName}$backupSuffix');
      LoggerService.info('Backup criado: ${tableName}$backupSuffix');
    }

    // 2. Executar DROP
    for (final tableName in tablesToDrop) {
      await database.execute('DROP TABLE IF EXISTS $tableName');
      LoggerService.warning('Tabela dropada: $tableName');
    }

    LoggerService.warning('=== DROP CONCLUÍDO, BACKUPS DISPONÍVEIS ===');

  } catch (e, st) {
    LoggerService.error('Erro no DROP, tentando rollback...', e, st);

    // 3. Rollback: restaurar dos backups
    try {
      for (final tableName in tablesToDrop) {
        await database.execute('DROP TABLE IF EXISTS $tableName');
        await database.execute(
          'ALTER TABLE ${tableName}$backupSuffix RENAME TO $tableName',
        );
        LoggerService.warning('Restaurado backup de: $tableName');
      }
      LoggerService.warning('=== ROLLBACK CONCLUÍDO ===');
    } catch (rollbackError) {
      LoggerService.error('Erro no rollback: $rollbackError');
    }

    rethrow;
  } finally {
    database.dispose();
  }
}
```

**Fluxo de limpeza de backups:**

```dart
// Após verificar que o app funcionou corretamente (ex: no primeiro login)
Future<void> _cleanupBackupsAfterSuccess() async {
  final database = await openSqliteApi(dbPath);

  try {
    final tables = await database.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE '%_backup_v2_2_3_%'"
    ).get();

    for (final row in tables) {
      final tableName = row.read<String>('name').replaceAll('_backup_v2_2_3_%', '');
      await database.execute('DROP TABLE IF EXISTS ${row.read<String>('name')}');
      LoggerService.info('Backup removido: $tableName');
    }

  } finally {
    database.dispose();
  }
}
```

**Benefícios:**
- ✅ Protege contra perda de dados em caso de erro
- ✅ Permite recuperação automática
- ✅ Pode ser executado manualmente se necessário

---

## 🟠 P1: Melhorias de Alta Prioridade

### P1.1 Recriação Através de Drift Schema

**Problema Atual:**
As tabelas são recriadas via SQL manual hardcoded no `beforeOpen`, divergindo do schema definido em Drift.

**Solução:**
Em vez de SQL manual, deixar o Drift criar as tabelas através do sistema de migração.

**Arquivos a modificar:**
- `lib/infrastructure/datasources/local/database.dart`
- Remover funções `_ensureXXXTableExistsDirect()` para tabelas de config

**Implementação:**

```dart
// Remover do beforeOpen:
// await _ensureSqlServerConfigsTableExistsDirect();
// await _ensureSybaseConfigsTableExistsDirect();
// await _ensurePostgresConfigsTableExistsDirect();
// await _ensureSchedulesTableExistsDirect();

// Substituir por validação simples no beforeOpen:
beforeOpen: (details) async {
  await customStatement('PRAGMA foreign_keys = ON');

  // Valida apenas se as tabelas principais existem (não recria via SQL)
  await _ensureSchemaTablesExist();

  // ... resto das outras verificações
},

Future<void> _ensureSchemaTablesExist() async {
  final tables = ['sql_server_configs_table', 'sybase_configs_table', 'postgres_configs_table'];

  for (final table in tables) {
    final exists = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'"
    ).getSingleOrNull();

    if (exists == null) {
      LoggerService.warning('Tabela $table não encontrada - será criada pelo Drift');
    }
  }
}
```

**Modificação no sistema de migração:**

```dart
// Adicionar método em onUpgrade para garantir recriação
onUpgrade: (Migrator m, int from, int to) async {
  if (from == 0) {
    await m.createAll();  // Usa schema Drift
    LoggerService.info('Tabelas criadas via Drift (schema v$to)');
  } else if (from < 24) {
    // Migrações normais
    await _runMigrations(m, from, to);
  } else {
    // Versão nova (>= 24) - garante schema atual
    LoggerService.info('Schema atual já em v$to');
  }
}
```

**Benefícios:**
- ✅ Consistência garantida entre DROP e schema
- ✅ Índices criados automaticamente
- ✅ Menos código duplicado
- ✅ Manutenibilidade mais fácil

---

### P1.2 Consulta Única ao sqlite_master

**Problema Atual:**
4 consultas separadas ao `sqlite_master`, uma para cada tabela.

**Solução:**
Usar uma única consulta com `IN` para verificar todas as tabelas de uma vez.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
Future<void> _dropConfigTablesForVersion223() async {
  // ... código anterior ...

  try {
    final database = await openSqliteApi(dbPath);

    // Consulta única
    final tablesToCheck = [
      'sql_server_configs_table',
      'sybase_configs_table',
      'postgres_configs_table',
      'schedules_table',
    ];

    final inClause = tablesToCheck.map((t) => "'$t'").join(',');
    final query = "SELECT name FROM sqlite_master WHERE type='table' AND name IN ($inClause)";

    final existingTables = await database.select(query).get();
    final tablesToDrop = existingTables.map((row) => row.read<String>('name')).toList();

    LoggerService.info('Tabelas encontradas para DROP: ${tablesToDrop.length}');

    for (final tableName in tablesToDrop) {
      await database.execute('DROP TABLE IF EXISTS $tableName');
      LoggerService.warning('Tabela dropada: $tableName');
    }

    database.dispose();
  } catch (e, st) {
    LoggerService.error('Erro ao dropar tabelas: $e', e, st);
  }
}
```

**Benefícios:**
- ✅ ~4x mais rápido (1 consulta vs 4)
- ✅ Menos round-trips ao banco
- ✅ Reduz uso de CPU

---

## 🟡 P2: Melhorias de Média Prioridade

### P2.1 Remover schedules_table do Drop Inicial

**Problema Atual:**
`schedules_table` está sendo dropada para evitar problemas de dependência, mas isso causa perda de dados importantes do usuário.

**Solução:**
Remover `schedules_table` da lista inicial de DROP. A tabela não será dropada, apenas as 3 tabelas de configuração de banco.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
Future<void> _dropConfigTablesForVersion223() async {
  final tablesToDrop = [
    'sql_server_configs_table',
    'sybase_configs_table',
    'postgres_configs_table',
    // 'schedules_table',  // REMOVIDO - preserva dados de agendamentos
  ];

  // ... restante do código ...
}
```

**Benefícios:**
- ✅ Preserva dados de agendamentos do usuário
- ✅ Reduz tempo de reset
- ✅ Menos impacto para usuário

**Nota:** Se houver problema de dependência de schedules → config, ele deve ser tratado no código de validação da UI, não no reset.

---

### P2.2 Tratamento Diferenciado de Erros

**Problema Atual:**
Todos os erros são tratados de forma idêntica, sem distinção entre erros recuperáveis e críticos.

**Solução:**
Criar enum de tipos de erro e tratamento diferenciado.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
enum ResetErrorType { locked, corrupted, permission, permissionDenied, databaseInUse, unknown }

void _handleDropError(ResetErrorType type, Object error, StackTrace stackTrace) {
  switch (type) {
    case ResetErrorType.locked:
      LoggerService.error('BANCO BLOQUEADO - Aguardando 3 segundos...');
      await Future.delayed(const Duration(seconds: 3));
      // O retry será feito pelo usuário ao tentar novamente
      break;

    case ResetErrorType.corrupted:
      LoggerService.error('BANCO CORROMPIDO - Contate o suporte técnico');
      // Pode mostrar alerta ao usuário
      break;

    case ResetErrorType.permission:
    case ResetErrorType.permissionDenied:
      LoggerService.error('SEM PERMISSÃO - Verifique permissões do arquivo');
      break;

    case ResetErrorType.databaseInUse:
      LoggerService.warning('BANCO EM USO - Feche outras instâncias do aplicativo');
      break;

    default:
      LoggerService.error('Erro desconhecido ao resetar: $error', error, stackTrace);
  }
}
```

**Melhor tratamento no catch:**

```dart
try {
  // DROP tables
} on SqliteException catch (e) {
  final errorType = _identifyErrorType(e.message ?? '');
  _handleDropError(errorType, e, stackTrace);
  throw ResetException(errorType, e.message ?? 'Erro ao resetar banco');
} catch (e, st) {
  LoggerService.error('Erro inesperado: $e', e, st);
  throw ResetException(ResetErrorType.unknown, e.toString());
}
```

**Benefícios:**
- ✅ Usuário sabe qual o problema ocorreu
- ✅ Permite ações específicas por tipo de erro
- ✅ Melhor UX e suporte

---

## 🟢 P3: Melhorias de Baixa Prioridade

### P3.1 Transação SQLite

**Problema Atual:**
DROPs são executados sequencialmente sem proteção de transação.

**Solução:**
Envolver todos os DROPs em uma transação SQLite para garantir atomicidade.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
Future<void> _dropConfigTablesForVersion223() async {
  final database = await openSqliteApi(dbPath);

  try {
    // Executa todos os DROPs em uma única transação
    database.transaction((txn) {
      for (final tableName in tablesToDrop) {
        txn.execute('DROP TABLE IF EXISTS $tableName');
      }
    });

    LoggerService.warning('Todas tabelas dropadas em transação atômica');

    database.dispose();
  } catch (e, st) {
    LoggerService.error('Erro ao dropar tabelas: $e', e, st);
  }
}
```

**Benefícios:**
- ✅ Atomicidade garantida
- ✅ Ou todos dropam ou nenhum dropa
- ✅ Reduz chance de banco em estado inconsistente

---

### P3.2 Logging Estruturado

**Problema Atual:**
Logs não têm estrutura clara, dificultando debugging de problemas.

**Solução:**
Criar sistema de logging estruturado com fases e medição de tempo.

**Arquivos a modificar:**
- `lib/core/di/core_module.dart`

**Implementação:**

```dart
enum ResetPhase {
  versionCheck,
  pathCheck,
  databaseOpen,
  checkExistingTables,
  dropTables,
  complete,
}

Future<void> _dropConfigTablesForVersion223() async {
  final stopwatch = Stopwatch()..start();

  try {
    _logPhase(ResetPhase.versionCheck, 'Verificando versão');
    await Future.delayed(const Duration(milliseconds: 500));

    final packageInfo = await PackageInfo.fromPlatform();
    final version = packageInfo.version;
    final shouldReset = version.startsWith('2.2.3');

    _logPhase(ResetPhase.versionCheck, 'Versão: $version, Reset: $shouldReset');

    if (!shouldReset) {
      _logPhase(ResetPhase.complete, 'Versão não requer reset');
      return false;
    }

    _logPhase(ResetPhase.pathCheck, 'Verificando caminho do banco');
    final appDataDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDataDir.path, 'backup_database.db');
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      _logPhase(ResetPhase.complete, 'Banco não encontrado');
      return false;
    }

    _logPhase(ResetPhase.databaseOpen, 'Abrindo banco para DROP');
    final database = await openSqliteApi(dbPath);

    _logPhase(ResetPhase.checkExistingTables, 'Verificando tabelas existentes');
    final inClause = tablesToDrop.map((t) => "'$t'").join(',');
    final query = "SELECT name FROM sqlite_master WHERE type='table' AND name IN ($inClause)";
    final existingTables = await database.select(query).get();
    final tablesToDrop = existingTables.map((row) => row.read<String>('name')).toList();

    _logPhase(ResetPhase.dropTables, 'Executando DROP de ${tablesToDrop.length} tabelas');

    for (final tableName in tablesToDrop) {
      await database.execute('DROP TABLE IF EXISTS $tableName');
    }

    _logPhase(ResetPhase.complete, 'Reset concluído em ${stopwatch.elapsedMilliseconds}ms');

    database.dispose();
    return true;

  } catch (e, st) {
    _logPhase(ResetPhase.complete, 'ERRO em ${stopwatch.elapsedMilliseconds}ms');
    LoggerService.error('Erro ao resetar: $e', e, st);
    return false;
  }
}

void _logPhase(ResetPhase phase, String message) {
  LoggerService.info('[RESET ${phase.name}] $message');
}
```

**Benefícios:**
- ✅ Debugging mais fácil
- ✅ Medição de tempo disponível
- ✅ Logs mais claros e estruturados

---

## 📋 Cronograma de Implementação

### Fase 1: Preparação (1-2 dias)

| Tarefa | Status | Responsável |
|--------|--------|-----------|
| Revisar e aprovar este plano | ⏳ | Produto |
| Preparar ambiente de testes | ⏳ | QA |
| Documentar arquitetura | ⏳ | Produto |

### Fase 2: Prioridade P0 (2-3 dias)

| Tarefa | Estimativa | Status |
|--------|-------------|--------|
| P0.1: Validação exata da versão | 4h | ⏳ |
| P0.2: Flag de reset em secure storage | 3h | ⏳ |
| P0.3: Backup antes de DROP | 6h | ⏳ |

### Fase 3: Prioridade P1 (2-3 dias)

| Tarefa | Estimativa | Status |
|--------|-------------|--------|
| P1.1: Recriação via Drift schema | 8h | ⏳ |
| P1.2: Consulta única ao sqlite_master | 2h | ⏳ |

### Fase 4: Prioridade P2 (1-2 dias)

| Tarefa | Estimativa | Status |
|--------|-------------|--------|
| P2.1: Remover schedules_table do DROP | 1h | ⏳ |
| P2.2: Tratamento diferenciado de erros | 4h | ⏳ |

### Fase 5: Prioridade P3 (1 dia)

| Tarefa | Estimativa | Status |
|--------|-------------|--------|
| P3.1: Transação SQLite | 3h | ⏳ |
| P3.2: Logging estruturado | 2h | ⏳ |

### Fase 6: Testes e Homologação (2-3 dias)

| Tarefa | Status |
|--------|--------|
| Testes unitários | ⏳ |
| Testes de integração | ⏳ |
| Testes de performance | ⏳ |
| Testes de rollback | ⏳ |
| Homologação | ⏳ |

**Total estimado:** 9-14 dias

---

## 🧪 Cenários de Teste

### TC-1: Reset com Sucesso

**Objetivo:** Verificar fluxo normal com sucesso

**Passos:**
1. Iniciar app v2.2.3 pela primeira vez
2. Verificar logs: `RESET versionCheck: Versão: 2.2.3, Reset: true`
3. Verificar logs: `[RESET dropTables] Executando DROP de 3 tabelas`
4. Verificar logs: `Tabelas serão recriadas automaticamente`
5. Tentar acessar UI e configurar uma conexão SQL Server
6. Verificar que tabela foi recriada corretamente

**Critério de Sucesso:**
- ✅ DROP executado sem erros
- ✅ Tabelas recriadas via Drift
- ✅ Flag de reset gravada
- ✅ Nova configuração salva com sucesso

---

### TC-2: Reset com Banco Bloqueado

**Objetivo:** Verificar tratamento de erro de lock

**Passos:**
1. Abrir duas instâncias do app v2.2.3 simultaneamente
2. Aguardar o deadlock
3. Verificar logs: `[RESET dropTables] ERRO: database is locked`
4. Verificar tratamento de retry (3 segundos)
5. Verificar que a segunda instância executou o drop
6. Fechar primeira instância
7. Tentar segunda instância novamente

**Critério de Sucesso:**
- ✅ Erro tratado corretamente
- ✅ Retry automático funciona (se implementado)
- ✅ Uma das instâncias consegue completar o reset

---

### TC-3: Reset com Erro e Rollback

**Objetivo:** Verificar mecanismo de backup/rollback

**Passos:**
1. Iniciar app v2.2.3
2. Forçar erro no DROP (simular problema de corrupção)
3. Verificar logs: Backup criado para cada tabela
4. Verificar logs: DROP executado
5. Verificar logs: `=== ROLLBACK CONCLUÍDO ===`
6. Verificar que tabelas foram restauradas dos backups
7. Verificar que dados antigos estão preservados
8. Iniciar novamente (sem erro forçado)
9. Verificar que reset funciona normalmente

**Critério de Sucesso:**
- ✅ Rollback executado com sucesso
- ✅ Dados preservados
- ✅ Reset normal funciona após rollback

---

### TC-4: Versão Futura com Prefixo Comum

**Objetivo:** Verificar validação exata de versão

**Passos:**
1. Compilar versão 2.2.30
2. Alterar pubspec.yaml para `version: 2.2.30`
3. Build e rodar app
4. Verificar logs: `Versão: 2.2.30, Parseada: 2.2.30, Target: 2.2.3, Reset: false`
5. Verificar que NÃO houve reset
6. Compilar versão 2.2.31
7. Verificar logs: `Versão: 2.2.31, Parseada: 2.2.31, Target: 2.2.3, Reset: false`
8. Verificar que NÃO houve reset

**Critério de Sucesso:**
- ✅ Validação funciona corretamente
- ✅ Não há reset acidental em versões futuras

---

### TC-5: Múltiplos Inícios com Versão 2.2.3

**Objetivo:** Verificar flag de reset em secure storage

**Passos:**
1. Iniciar app v2.2.3 pela primeira vez
2. Verificar logs: `[RESET dropTables] Executando DROP`
3. Verificar logs: `Flag de reset v2.2.3 marcada como concluída`
4. Fechar app
5. Abrir app novamente
6. Verificar logs: `Reset v2.2.3 já foi executado anteriormente`
7. Verificar logs: `DROP CONCLUÍDO` NÃO aparece
8. Verificar que NÃO houve segundo DROP
9. Fechar app
10. Abrir app novamente
11. Verificar: ainda não há DROP (flag protege)

**Critério de Sucesso:**
- ✅ Flag funciona corretamente
- ✅ Segundo início não executa DROP desnecessário
- ✅ Reduz tempo de inicialização após primeiro reset

---

### TC-6: Performance - Comparação de Tempo

**Objetivo:** Verificar melhoria de performance da consulta única

**Passos:**
1. Medir tempo de DROP com implementação atual (4 consultas)
2. Implementar consulta única
3. Medir tempo de DROP com nova implementação (1 consulta)
4. Comparar: Nova versão deve ser ~3-4x mais rápida

**Critério de Sucesso:**
- ✅ Tempo de DROP < 500ms (consulta única)
- ✅ Logs mostram tempo de cada fase

---

### TC-7: Preservação de schedules_table

**Objetivo:** Verificar que agendamentos são preservados

**Passos:**
1. Iniciar app v2.2.3
2. Verificar logs: `[RESET dropTables] Executando DROP de 3 tabelas`
3. Verificar que `schedules_table` NÃO está na lista
4. Verificar logs: `Tabelas serão recriadas automaticamente`
5. Acessar UI e verificar que agendamentos estão intactos
6. Criar novo agendamento
7. Verificar que novo agendamento é salvo corretamente

**Critério de Sucesso:**
- ✅ schedules_table não foi dropada
- ✅ Agendamentos existentes são preservados
- ✅ Novos agendamentos funcionam

---

## 📝 Notas Técnicas

### Dependências Necessárias

**Para P0.1:**
```yaml
pubspec.yaml:
dev_dependencies:
  pub_semver: ^2.1.5  # Adicionar se ainda não existe
```

**Para P0.2:**
```yaml
pubspec.yaml:
dependencies:
  flutter_secure_storage: ^9.2.0  # Já existe
```

### Considerações de Compatibilidade

- **pub_semver:** Suporta validação semântica de versões
- **flutter_secure_storage:** Usa criptografia nativa no Windows
- **sqlite3:** Pacote nativo para SQLite, performance otimizada

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
| Secure Storage | Armazenamento criptografado nativo |
| Transação SQLite | Unidade atômica de operações SQL |
| Rollback | Restauração de dados a partir de backup |
| Race Condition | Condição de corrida onde duas operações competem pelo mesmo recurso |
| Locking | Bloqueio de arquivo quando um processo o está usando |

---

## 📌 Aprovação

Este plano deve ser revisado e aprovado antes da implementação.

**Checklist de Aprovação:**
- [ ] Plano revisto por arquiteto
- [ ] Estimativas de esforço validadas
- [ ] Cronograma realista
- [ ] Cenários de teste cobrem casos de borda
- [ ] Dependências disponíveis
- [ ] Impacto no usuário comunicado

---

**Data de criação:** 2026-02-22
**Última atualização:** -
**Status:** ⏳ Aguardando aprovação
