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
| 🔴 P0 | Backup Antes de DROP com Rollback | ⏳ Em desenvolvimento |
| 🟠 P1 | Recriação Através de Drift Schema | ⏳ Pendente |
| 🟠 P1 | Desempenho | Consulta Única ao sqlite_master | ⏳ Pendente |
| 🟡 P2 | Confiabilidade | Remover schedules_table do DROP | ⏳ Pendente |
| 🟡 P2 | UX | Tratamento Diferenciado de Erros | ⏳ Pendente |
| 🟢 P3 | Manutenibilidade | Transação SQLite | ⏳ Pendente |
| 🟢 P3 | Debugabilidade | Logging Estruturado | ⏳ Pendente |

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

## 🟠 P1: Melhorias de Alta Prioridade

### P1.1 Recriação Através de Drift Schema ⏳

**Status:** Em desenvolvimento
**Estimativa:** 8 horas

**Problema Atual:**
As tabelas são recriadas via SQL manual hardcoded no `beforeOpen` do AppDatabase, divergindo do schema definido em Drift.

**Arquivos a Modificar:**
- `lib/infrastructure/datasources/local/database.dart`:
  - Remover funções `_ensureSqlServerConfigsTableExistsDirect()`
  - Remover funções `_ensureSybaseConfigsTableExistsDirect()`
  - Remover funções `_ensurePostgresConfigsTableExistsDirect()`
  - Remover funções `_ensureSchedulesTableExistsDirect()`
  - Modificar `beforeOpen` para chamar apenas verificação de tabelas principais existentes

---

### P1.2 Consulta Única ao sqlite_master ⏳

**Status:** Pendente
**Estimativa:** 2 horas

**Problema Atual:**
4 consultas separadas ao `sqlite_master`, uma para cada tabela de configuração.

**Solução:**
Usar uma única consulta com `IN` para verificar todas as tabelas de uma vez.

**Implementação:**
```dart
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
```

**Benefícios:**
- ✅ ~4x mais rápido (1 consulta vs 4)
- ✅ Menos round-trips ao banco
- ✅ Reduz uso de CPU

---

## 🟡 P2: Melhorias de Média Prioridade

### P2.1 Remover schedules_table do DROP ⏳

**Status:** Pendente
**Estimativa:** 1 hora

**Problema Atual:**
`schedules_table` está sendo dropada para evitar problemas de dependência, mas isso causa perda de dados importantes do usuário.

**Solução:**
Remover `schedules_table` da lista inicial de DROP. A tabela não será dropada, apenas as 3 tabelas de configuração de banco.

**Arquivos a Modificar:**
- `lib/core/di/core_module.dart`:
  - Remover `'schedules_table'` da lista `tablesToDrop`

---

### P2.2 Tratamento Diferenciado de Erros ⏳

**Status:** Pendente
**Estimativa:** 4 horas

**Problema Atual:**
Todos os erros são tratados de forma idêntica, sem distinção entre erros recuperáveis e críticos.

**Solução:**
Criar enum de tipos de erro e tratamento diferenciado.

---

## 🟢 P3: Melhorias de Baixa Prioridade

### P3.1 Transação SQLite ⏳

**Status:** Pendente
**Estimativa:** 3 horas

**Problema Atual:**
DROPs são executados sequencialmente sem proteção de transação.

**Solução:**
Envolver todos os DROPs em uma transação SQLite para garantir atomicidade.

---

### P3.2 Logging Estruturado ⏳

**Status:** Pendente
**Estimativa:** 2 horas

**Problema Atual:**
Logs não têm estrutura clara, dificultando debugging de problemas.

**Solução:**
Criar sistema de logging estruturado com fases e medição de tempo.

---

## 📋 Cronograma de Implementação (Atualizado)

| Fase | Período | Tarefas | Status |
|-------|---------|--------|--------|
| 1 | Preparação (1-2 dias) | Revisão, aprovação | ⏳ |
| 2 | P0 Críticas (2-3 dias) | P0.1, P0.2, P0.3 | ✅ P0.1, ✅ P0.2 |
| 3 | P1 Altas (2-3 dias) | P1.1, P1.2 | ⏳ P1.1, ⏳ P1.2 |
| 4 | P2 Médias (1-2 dias) | P2.1, P2.2 | ⏳ P2.1, ⏳ P2.2 |
| 5 | P3 Baixas (1 dia) | P3.1, P3.2 | ⏳ P3.1, ⏳ P3.2 |
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
