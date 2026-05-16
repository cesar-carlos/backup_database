# ADR-004: Adoção de ports genéricos e template para SGBDs

- Status: accepted
- Data: 2026-05-15
- Decisores: time aplicativo (Clean Architecture + desktop Windows)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (PR‑E, E1–E15)

## Contexto

Cada SGBD (SQL Server, Sybase, PostgreSQL) tinha **repositório de
configuração**, **serviço de backup**, **provider** e **estratégia**
com duplicação de padrões: CRUD drift, validações pré‑backup, registro
no `GetIt` espalhado. Adicionar Firebird ou outro motor exigia copiar
blocos grandes e aumentava risco de divergência (ex.: `Result.fold`
async sem `await`, histórico em `running` após falha).

Precisávamos de um **template** estável (OCP) sem violar limites de
camada: domínio sem Flutter/IO; aplicação sem infraestrutura direta;
apresentação sem repositórios concretos.

## Decisão

Adotar **ports genéricos no domínio** e **implementações enxutas** nas
camadas inferiores, com quatro pilares:

1. **`DatabaseConnectionConfig`** + `IDatabaseConfigRepository<T>` +
   `IDatabaseBackupPort<T>` (marker services por SGBD onde já existiam).
2. **`BaseDatabaseConfigRepository<TConfig, TData>`** na infra para CRUD
   comum Drift com `RepositoryGuard` e hooks.
3. **`DatabaseConfigProviderBase<T>`** na aplicação para estado de
   configs; **`GenericDatabaseBackupStrategy<T>`** com
   `BackupValidationRule<T>` e `BackupResultEnricher<T>` + factories por
   SGBD.
4. **`registerSgbd<...>`** em `GetIt` e **`registerBackupDatabaseDefaultSgbds`**
   para registrar repositório, port de backup e provider de UI em um
   único ponto por motor (hoje SQL Server, Sybase, PostgreSQL).

## Consequências

### Positivas

- Novo SGBD segue checklist curto (domain → infra → application → DI →
  UI) com menos linhas e menos `switch` ad‑hoc no orchestrator.
- Regras de backup e enriquecimento de resultado **testáveis** de forma
  isolada.
- DI explícito para “fatia” SGBD (`registerSgbd`) reduz esquecimento de
  registrar provider ou port.

### Negativas

- `sgbd_registration.dart` em `core/di` importa **application** e
  **infrastructure** para montar o stack padrão — aceito como exceção
  pragmática do módulo de composição DI (evita arquivo espalhado sem
  ganho).
- Manter **guardas na infra** onde o port ainda pode ser chamado sem
  passar pela estratégia (duplicação defensiva controlada).

### Neutras

- Fachadas `*BackupStrategy` / `*ConfigProvider` permanecem como
  superfície estável para testes e leitura, delegando para generic +
  factory.

## Alternativas consideradas

### Opção A: Monolito `DatabaseBackupService` com `switch (DatabaseType)`

- Um serviço gigante com todos os SGBDs.
- **Rejeitada**: viola SRP/OCP; regressões difíceis de isolar.

### Opção B: Apenas extrair repositório base, sem ports genéricos

- Reduz duplicação de CRUD mas não alinha backup + DI.
- **Rejeitada**: metade do ganho do PR‑E; Firebird continuaria cara.

### Opção C: Plugin / isolado por package por SGBD

- Máximo isolamento; custo de build e descoberta no Flutter desktop.
- **Adiada**: possível evolução; hoje o time prioriza um repo monolítico
  com boundaries por pasta.

## Notas de implementação

- Arquivos‑chave: `lib/domain/entities/database_connection_config.dart`,
  `lib/domain/repositories/i_database_config_repository.dart`,
  `lib/domain/services/i_database_backup_port.dart`,
  `lib/infrastructure/repositories/base_database_config_repository.dart`,
  `lib/application/services/strategies/generic_database_backup_strategy.dart`,
  `lib/core/di/sgbd_registration.dart`.
- Regra de sintaxe Dart: no `registerSgbd`, o último type parameter deve
  ser `TProvider extends Object>({` (sem vírgula antes de `>(`) para o
  parser aceitar e satisfazer `GetIt.registerFactory`.
