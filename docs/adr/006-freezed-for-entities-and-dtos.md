# ADR-006: Adoção de freezed para entities e DTOs

- Status: accepted
- Data: 2026-05-18
- Decisores: time desktop Flutter (app backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (M1)

## Contexto

Várias entidades de domínio repetem `copyWith`, igualdade parcial e
construtores verbosos (`BackupHistory`, `BackupLog`, configs SGBD).
O projeto já usa `build_runner` (Drift) e adotou `freezed` como
dependência. Um piloto em `BackupExecutionContext` validou codegen e
testes de igualdade/copyWith.

Migrar tudo de uma vez é arriscado: configs que **estendem**
`DatabaseConnectionConfig` não mapeiam diretamente para `@freezed class X
extends Y` sem um desenho de **union/sealed** ou composição.

## Decisão

1. **Usar `freezed` + `freezed_annotation`** para value objects imutáveis
   de domínio e DTOs de orquestração quando não houver herança profunda.
2. **Ordem de migração** (incremental, um PR ou sub-commit por tipo):
   - Feito: `BackupExecutionContext` (serviço de orquestração).
   - Feito: `BackupLog` (igualdade por `id` preservada).
   - Feito: `BackupHistory` (igualdade por `id` preservada).
   - Feito: `Schedule` — composição com `sqlServerBackupOptions` /
     `sybaseBackupOptions` (subclasses removidas); igualdade por `id`;
     `test/unit/domain/entities/schedule_test.dart`.
   - Feito (**2026-05-18**): `SqlServerConfig`, `SybaseConfig`,
     `PostgresConfig`, `FirebirdConfig` — `@freezed` +
     `implements DatabaseConnectionConfig` (interface class; sem herança);
     getters de contrato (`backupTarget`, `portValue`, etc.) no corpo da
     classe; igualdade por `id` onde aplicável; testes em
     `test/unit/domain/entities/*_config_test.dart` e
     `database_connection_config_test.dart`.
3. **Igualdade intencionalmente por `id`**: quando a entidade já compara
   só pelo identificador (`BackupLog`, `BackupHistory`), usar
   construtor privado `const Entity._()` e override de `==` / `hashCode`
   no corpo da classe freezed (não confiar na igualdade estrutural gerada).
4. **Defaults no factory**: `id` e timestamps via `@Default(fn)` em vez
   de lógica no construtor legado, para manter call sites estáveis.
5. **`json_serializable`**: adiar para a fase em que protocolo/API
   exigir JSON automático nas mesmas classes; até lá, mappers Drift/socket
   permanecem explícitos.
6. **Codegen**: após alterar ficheiros anotados, executar
   `dart run build_runner build --delete-conflicting-outputs` e incluir
   `*.freezed.dart` no commit.

## Consequencias

### Positivas

- Menos boilerplate (`copyWith`, `==` onde a igualdade é estrutural).
- Padrão único alinhado ao piloto `BackupExecutionContext`.
- Testes de regressão focados em igualdade/copyWith por entidade.

### Negativas

- Mais ficheiros gerados no repositório e no review.
- Ports genéricos (`IDatabaseConfigRepository<T>`) exigem `T implements
  DatabaseConnectionConfig` — não há union sealed única para todos os SGBDs.
- Curva de aprendizado para overrides de igualdade em freezed.

### Neutras

- Drift e freezed partilham `build_runner`; tempos de build locais sobem
  ligeiramente.

## Alternativas consideradas

### Opcao A: manter classes manuais

- Sem codegen extra.
- Rejeitada: dívida de `copyWith`/`==` duplicados e erros em refactors.

### Opcao B: migrar configs com `@freezed` + herança

- Tentativa direta `class FirebirdConfig extends DatabaseConnectionConfig`
  com freezed.
- Rejeitada: freezed não modela bem herança; ports genéricos exigem
  contrato estável.

### Opcao C: `equatable` apenas

- Menos features que freezed.
- Rejeitada: não gera `copyWith` imutável nem sealed unions futuras.

## Notas de implementacao

- Exemplos de igualdade por id: `lib/domain/entities/backup_log.dart`,
  `lib/domain/entities/backup_history.dart`.
- Piloto orquestração: `lib/domain/services/backup_execution_context.dart`.
- Configs SGBD: `lib/domain/entities/*_config.dart` + `*.freezed.dart`;
  contrato: `lib/domain/entities/database_connection_config.dart`.
