# Plano: Suporte a Backup de Bancos Firebird

Data base: 2026-04-19
Status: Proposto (depende do plano de refatoração estar concluído)
Escopo: adicionar Firebird (versões 2.5, 3.0 e 4.0) como quarto SGBD
suportado, em paridade funcional com SQL Server, Sybase ASA e
PostgreSQL — incluindo execução local, UI e execução remota via socket.

> **Pré-requisito**: este plano assume que o
> [`plano_refatoracao_e_melhorias_2026-04-19.md`](./plano_refatoracao_e_melhorias_2026-04-19.md)
> está mergeado (PRs A, B, C, D, E). Sem ele, a implementação de
> Firebird seria ~3× maior por reintroduzir duplicações que foram
> eliminadas, perder os helpers/abstrações genéricas e ficar fora do
> design system consolidado (tokens, ThemeExtension, slot pattern).

---

## Sumário executivo

3 PRs sequenciais entregam suporte completo a Firebird após o plano de
refatoração:

| PR | Esforço | Linhas | Resultado |
|---|---|---|---|
| **PR-E** Firebird domain + infra + CLI | 1,5 dia | +350 | backup executável via test |
| **PR-F** Firebird UI + UX (U2/U3/U6/U7) | 1,5 dia | +400 | usuário cadastra e executa pelo app |
| **PR-G** Firebird remoto (socket) + U10 | 1 dia | +150 | servidor expõe Firebird ao cliente |
| **Total** | **4 dias** | **+900** | feature completa |

**Comparativo**: sem o plano de refatoração precedente, a entrega
seria ~7-8 dias e +1500 linhas. O ROI vem do reuso de:
- `BaseDatabaseConfigRepository` (PR-E hexagonal)
- `DatabaseConfigProviderBase` (PR-E)
- `GenericDatabaseBackupStrategy` (PR-E)
- `DatabaseConfigDialogShell` (PR-D refator UI)
- `DatabaseTypeMetadata` (PR-D)
- `AppPalette`, `AppSpacing`, `AppRadius`, `AppDuration`,
  `AppSemanticColors` (PR-C design system) — **identidade visual
  Firebird vem automaticamente alinhada com SGBDs existentes**

---

## 1. Estado da Arte: Backup em Firebird (pesquisa 2026-04)

Pesquisa em [`firebirdsql.org/manual`](https://www.firebirdsql.org/),
[`firebirdsql.org/pdfmanual`](https://www.firebirdsql.org/pdfmanual/),
issues do `FirebirdSQL/jaybird` no GitHub, fórum oficial e
documentação Tetrasys (FB 5).

### 1.1 Modelos de backup oficiais

| Modelo | Ferramenta | Tipo |
|---|---|---|
| Lógico full single-file | `gbak` | exporta estrutura + dados em formato portável (`.fbk`) |
| Físico full | `nbackup -B 0` | snapshot binário das páginas (rápido, não-portável) |
| Físico incremental N-níveis | `nbackup -B 1..N` | apenas páginas alteradas; cadeia até 9 níveis |
| Lock/Unlock para ferramenta externa | `nbackup -L`/`-N` | congela `.fdb` redirecionando writes para `.delta` |
| Hot backup via SQL | `ALTER DATABASE BEGIN/END BACKUP` | equivalente SQL ao `-L`/`-N` |
| Services API | `gbak -SE service_mgr` ou `nbackup -SE service_mgr` | até **30% mais rápido em conexões remotas** |

### 1.2 Verificação de integridade — descoberta importante

**Não existe `gbak -t` ou flag dedicada de verify** em nenhuma versão.
A pesquisa confirmou que:

- `-V[ERIFY]` no manual significa **verbose**, não verify
- A única forma robusta de validar integridade de backup gbak é
  **restaurar para banco temporário** (`gbak -C`)
- nbackup também não tem verify; integridade depende da cadeia
  GUID/SCN registrada em `RDB$BACKUP_HISTORY`

**Implicação para o app**:
- Modo `none`/`bestEffort` (default): pula verify + log informativo
- Modo `strict` (opt-in): restore para arquivo temporário (caro,
  exige espaço extra; documentado no tooltip)

### 1.3 Tamanho do banco — query oficial

```sql
SELECT MON$PAGE_SIZE * MON$PAGES AS size_bytes FROM MON$DATABASE
```

Disponível desde Firebird 2.1, idêntico em 2.5/3.0/4.0. Como fallback
adicional: `File(databaseFile).length()` quando local; `gstat -h`
(header) parsing como último recurso.

### 1.4 Diferenças relevantes entre 2.5 / 3.0 / 4.0

| Aspecto | FB 2.5 | FB 3.0 | FB 4.0 |
|---|---|---|---|
| ODS (On-Disk Structure) | 11.2 | 12.0 | 13.0 |
| Auth padrão | `Legacy_Auth` | `Srp` | `Srp256` |
| Auth fallback (config no servidor) | — | `AuthServer = Legacy_Auth, Srp` | `AuthServer = Legacy_Auth, Srp, Srp256` |
| WireCrypt | inexistente | opcional | **`Required` por default** — clientes 2.5/3.0 antigos sem WireCrypt são rejeitados |
| Connection string | `host/port:path` ou `host:port:path` | `host/port:path` | `host/port:path` ou `inet://host:port/path` |
| `gbak -SE service_mgr` | disponível | disponível (~30% mais rápido) | disponível (~30% mais rápido) |
| `nbackup -SE service_mgr` | indisponível | disponível | disponível |
| `nbackup` GUID-based | não | não | **sim** (`-B GUID`) |
| `gbak` encryption | n/a | via plugin externo | nativo (`-CRYPT`, `-KEYHOLDER`, `-KEYNAME`, `-FE`) |
| Embedded plugin | só `fbclient.dll` | + `engine12.dll` em `plugins/` | + `engine13.dll` em `plugins/` |
| Replication nativa | inexistente | inexistente | sim (não cobrimos backup de replica nesta entrega) |

### 1.5 Mapeamento `BackupType` do app → ferramenta Firebird

| `BackupType` no app | Ferramenta Firebird | Justificativa |
|---|---|---|
| `BackupType.fullSingle` | `gbak -B` (com `-SE service_mgr` em FB 3.0+) | backup lógico portável; restore via `gbak -C`/`-R` em qualquer versão/plataforma |
| `BackupType.full` | `nbackup -B 0` | snapshot físico nivelado nível 0 (rápido, mesma plataforma) |
| `BackupType.differential` | `nbackup -B N` (N descoberto pela cadeia) | incremental físico; FB 4.0 usa GUID-based quando disponível |
| `BackupType.log` | `nbackup -B N` no nível mais alto da cadeia | Firebird não tem WAL exportável; o mais próximo de "log" é incremental de nível alto. **Decisão documentada na strategy** com warning na primeira execução |
| `BackupType.convertedDifferential/FullSingle/Log` | rejeitado com `Failure(NotSupported)` | tipos exclusivos do Sybase |

### 1.6 Implicações de design

1. **Detecção de versão (`FirebirdServerVersion`)**: enum interno
   `{ v25, v30, v40, unknown }` em
   `lib/domain/value_objects/firebird_server_version.dart`. Helpers:
   `supportsServiceManager`, `supportsCryptKey`,
   `supportsGuidNbackup`, `requiresWireCryptByDefault`,
   `engineDllName`, `nbackupSupportsServiceManager`,
   `parseFromGbakOutput`, `parseFromGstatOutput`
2. **Cache de versão**: `Map<String, FirebirdServerVersion>` indexado
   por `host:port:databaseFile`; invalidado em mudança de config;
   botão "Testar conexão" no dialog força re-detecção
3. **Resolução de versão em ordem**:
   1. respeitar `config.serverVersionHint` quando `!= auto`
   2. `gbak -z` (rápido, não toca o DB)
   3. fallback `gstat -h <db>` parsing do `Server version`
   4. `unknown` → assume `v30` (meio-termo seguro) com warning único
4. **WireCrypt em FB 4.0**: detectar mensagem `Incompatible wire
   encryption requirements` e propagar erro com remediação clara
5. **Auth fallback em cascata**:
   1. tentar com defaults da versão detectada (SRP em 3.0+, Legacy em
      2.5)
   2. se vier `Your user name and password are not defined` em FB
      3.0/4.0 → reexecutar com `-PROVIDER Engine12` (Legacy compat) +
      warning recomendando `AuthServer = Legacy_Auth, Srp` em
      `firebird.conf`
   3. se vier `Incompatible wire encryption requirements` em FB 4.0 →
      fail fast com remediação ("definir `WireCrypt = Enabled` no
      servidor ou atualizar binários gbak/nbackup para 4.0+")
6. **Embedded validation**: `_validateEmbeddedSetup` checa existência
   das DLLs esperadas (`engine12.dll`/`engine13.dll`) antes de tentar
   backup
7. **`gbak -SE service_mgr` é default em FB 3.0+**: ganho de ~30% em
   conexões remotas. Flag `useServiceManager` na entity (default
   `auto`)
8. **Bancos criptografados (FB 3.0+)**: campo opcional `cryptKey` na
   entity (armazenado via `ISecureCredentialService` com prefixo
   `firebird_cryptkey_`), passado como `-KEYNAME <name>` + `-CRYPT
   <plugin>` quando presente. Em FB 2.5 ignorado com warning único

---

## 2. Faseamento (3 PRs sequenciais)

```
┌──────────────────────────────────────────────────────────────────┐
│ PR-E  Firebird domain + infra + CLI   (1.5 dia)  →  +350 linhas  │
│        Entity, repository (Base), service, strategy (Generic)    │
├──────────────────────────────────────────────────────────────────┤
│ PR-F  Firebird UI + UX (U2/U3/U6/U7)  (1.5 dia)  →  +400 linhas  │
│        DatabaseConfigDialog Firebird; refator schedule_dialog    │
├──────────────────────────────────────────────────────────────────┤
│ PR-G  Firebird remoto + U10           (1 dia)    →  +150 linhas  │
│        Capabilities, protocol, golden tests, InfoBar UX          │
└──────────────────────────────────────────────────────────────────┘
                              Total: 4 dias / +900 linhas (líquido)
```

---

## 3. PR-E — Firebird Domain + Infraestrutura + CLI

**Objetivo**: criar entidade, repository, service, strategy Firebird
usando as abstrações do plano de refatoração; sem UI; backup
executável via integration test.

**Esforço**: 1,5 dia (50% menor graças ao PR-D do plano de
refatoração). **Critério**: `flutter test` verde, `dart analyze` zero,
backup Firebird gera `.fbk` (gbak) e cadeia `.delta` (nbackup) válidos
em diretório temporário.

### TODO list

#### E1 — Domain

- [ ] Adicionar `DatabaseType.firebird` em
      `lib/domain/entities/schedule.dart`
- [ ] Criar `lib/domain/entities/firebird_config.dart`
      `extends DatabaseConnectionConfig` (PR-D) com campos
      Firebird-específicos:
  - `databaseFile` (caminho `.fdb`)
  - `aliasName` (opcional)
  - `useEmbedded` (default `false`)
  - `clientLibraryPath` (opcional, para `fbclient.dll`)
  - `serverVersionHint` (`FirebirdServerVersionHint { auto, v25, v30, v40 }`)
  - `useServiceManager` (`FirebirdServiceManagerMode { auto, always, never }`)
  - `cryptKey` (opcional, FB 3.0+, persistido via secure storage)
  - Override `host`, `port`, `backupTarget` (usa `databaseFile`),
    `databaseType` (= `firebird`)
- [ ] Criar `lib/domain/value_objects/firebird_server_version.dart`:
  - enum `FirebirdServerVersion { v25, v30, v40, unknown }`
  - helpers (lista completa em seção 1.6)
  - `parseFromGbakOutput(String)`, `parseFromGstatOutput(String)`
- [ ] Criar `lib/domain/repositories/i_firebird_config_repository.dart`
      como **marker interface**:
  ```dart
  abstract class IFirebirdConfigRepository
      implements IDatabaseConfigRepository<FirebirdConfig> {}
  ```
- [ ] Atualizar `lib/domain/repositories/repositories.dart`: export
- [ ] Criar `lib/domain/services/i_firebird_backup_service.dart` como
      **marker interface**:
  ```dart
  abstract class IFirebirdBackupService
      implements IDatabaseBackupPort<FirebirdConfig> {}
  ```
- [ ] Atualizar `lib/domain/services/services.dart`: export
- [ ] Atualizar `lib/domain/use_cases/backup/get_database_config.dart`
      com `case DatabaseType.firebird`
- [ ] **Teste**: `test/unit/domain/entities/firebird_config_test.dart`
      (LSP — substituível por `DatabaseConnectionConfig`)
- [ ] **Teste**: `test/unit/domain/value_objects/firebird_server_version_test.dart`
      (parsing `gbak -z`, `gstat -h`, helpers de versão)

#### E2 — Infrastructure data

- [ ] Criar
      `lib/infrastructure/datasources/local/tables/firebird_configs_table.dart`:
  ```dart
  class FirebirdConfigsTable extends Table {
    TextColumn get id => text()();
    TextColumn get name => text()();
    TextColumn get host => text()();
    TextColumn get databaseFile => text()();
    TextColumn get aliasName => text().nullable()();
    TextColumn get username => text()();
    TextColumn get password => text()(); // legacy (sempre vazio)
    IntColumn get port => integer().withDefault(const Constant(3050))();
    BoolColumn get useEmbedded =>
        boolean().withDefault(const Constant(false))();
    TextColumn get clientLibraryPath => text().nullable()();
    TextColumn get serverVersionHint =>
        text().withDefault(const Constant('auto'))();
    TextColumn get useServiceManager =>
        text().withDefault(const Constant('auto'))();
    BoolColumn get enabled =>
        boolean().withDefault(const Constant(true))();
    DateTimeColumn get createdAt => dateTime()();
    DateTimeColumn get updatedAt => dateTime()();

    @override
    Set<Column> get primaryKey => {id};
  }
  ```
  > `cryptKey` **não persiste em texto plano** — vai via
  > `ISecureCredentialService` com prefixo
  > `SecureCredentialKeys.firebirdCryptKey`
- [ ] Atualizar
      `lib/infrastructure/datasources/local/tables/tables.dart`: export
- [ ] Criar
      `lib/infrastructure/datasources/daos/firebird_config_dao.dart`
      DAO Drift padrão
- [ ] Atualizar `lib/infrastructure/datasources/daos/daos.dart`: export
- [ ] Atualizar `lib/infrastructure/datasources/local/database.dart`:
  - registrar `FirebirdConfigsTable` em `tables`
  - registrar `FirebirdConfigDao` em `daos`
  - **bump `schemaVersion` 29 → 30**
  - migration `from < 30`:
    `m.createTable(firebirdConfigsTable)` com
    `_ensureFirebirdConfigsTableExists` defensivo (mesmo padrão de
    `_ensureSybaseConfigsTableExists`)
- [ ] Rodar `dart run build_runner build --delete-conflicting-outputs`
- [ ] **Teste regressão**: migration testada com base v29 existente
      (não apenas `inMemory`)

#### E3 — Repository (trivial graças ao PR-D)

- [ ] Criar
      `lib/infrastructure/repositories/firebird_config_repository.dart`:
  ```dart
  class FirebirdConfigRepository
      extends BaseDatabaseConfigRepository<FirebirdConfig, FirebirdConfigsTableData>
      implements IFirebirdConfigRepository {

    FirebirdConfigRepository(this._database, ISecureCredentialService secure)
        : super(
            secureCredentialService: secure,
            passwordKeyPrefix: SecureCredentialKeys.firebirdPassword,
          );

    final AppDatabase _database;

    @override Future<List<FirebirdConfigsTableData>> daoGetAll() =>
        _database.firebirdConfigDao.getAll();
    // ... (5 hooks adicionais, ~20 linhas)

    @override
    Future<FirebirdConfig> toEntity(FirebirdConfigsTableData data, String password) async {
      // Hook adicional para ler cryptKey de secure storage
      final cryptKey = await SecureCredentialHelper.readPasswordOrEmpty(
        service: secureCredentialService,
        prefix: SecureCredentialKeys.firebirdCryptKey,
        id: data.id,
      );
      return FirebirdConfig(/* ... */);
    }

    @override
    Future<void> daoInsert(FirebirdConfig config) async {
      // Persistir cryptKey em secure storage quando preenchido
      if (config.cryptKey.isNotEmpty) {
        await SecureCredentialHelper.storePasswordOrThrow(
          service: secureCredentialService,
          prefix: SecureCredentialKeys.firebirdCryptKey,
          id: config.id,
          password: config.cryptKey,
        );
      }
      await _database.firebirdConfigDao.insertConfig(_toCompanion(config));
    }
  }
  ```
  Total: ~50 linhas (vs ~150 sem PR-D)
- [ ] **Teste**:
      `test/unit/infrastructure/repositories/firebird_config_repository_test.dart`
      (CRUD + cryptKey roundtrip + senha em secure storage)

#### E4 — Backup service (`IFirebirdBackupService` adapter)

- [ ] Criar
      `lib/infrastructure/external/process/firebird_backup_service.dart`
      implementando `IDatabaseBackupPort<FirebirdConfig>`:

  - `_resolveServerVersion`: cache em memória (map indexado por
    `host:port:databaseFile`); ordem `hint → gbak -z → gstat -h →
    unknown(v30)`

  - `_executeFullSingleBackup` (gbak): args versão-aware:
    - 2.5: `gbak -B -V -USER ... -PASSWORD ... <conn> <out.fbk>`
    - 3.0/4.0: + `-SE service_mgr` quando
      `useServiceManager=auto|always`
    - 4.0: + `-KEYNAME <key>` + `-CRYPT <plugin>` quando `cryptKey`
    - flags opcionais: `-T` (transportable), `-G` (no GC),
      `-FA <factor>` (FB 3.0+)

  - `_executeFullBackup` (nbackup nível 0):
    `nbackup -B 0 <db> <output>` + auth + `-SE service_mgr` em FB 3.0+

  - `_executeDifferentialBackup` (nbackup nível N):
    - **FB 2.5/3.0**: descoberta por timestamp + parsing do nome
    - **FB 4.0**: GUID via `RDB$BACKUP_HISTORY` (consulta `isql`)
      quando disponível; fallback para timestamp
    - se cadeia inconsistente → fallback automático para nível 0,
      registrar `executedBackupType=BackupType.full` no
      `BackupExecutionResult` (orchestrator já trata)

  - `_executeLogBackup`: alias para
    `_executeDifferentialBackup` no nível mais alto + warning
    informativo na primeira execução

  - `_verifyBackup`:
    - `none`/`bestEffort`: skip + log informativo
    - `strict`: restore para arquivo temporário (`gbak -C
      /tmp/<uuid>.fdb` para gbak; `nbackup -R` para chain nbackup);
      cleanup do temp ao final

  - `testConnection`: `isql` com fallback `isql-fb`,
    `SELECT 1 FROM RDB$DATABASE`. Captura versão na mesma chamada
    para popular cache

  - `getDatabaseSizeBytes`: prioridade:
    1. `SELECT MON$PAGE_SIZE * MON$PAGES FROM MON$DATABASE` via
       `isql -t -A -e`
    2. `File(databaseFile).length()` quando local
    3. `gstat -h` (header) parsing

  - `listDatabases`:
    `Failure(NotSupportedFailure(message: 'Firebird usa um arquivo
    por banco; listagem não se aplica'))`

  - **Connection string builder versão-aware**:
    - FB 2.5: `host/port:path` (preferido) com fallback
      `host:port:path` quando o primeiro falha
    - FB 3.0+: `host/port:path` (canônico)
    - FB 4.0: aceita também `inet://host:port/path`

  - **Fallback de auth em cascata**: lista completa em seção 1.6

  - **Tratamento de criptografia em FB 2.5**: ignorar `cryptKey` com
    warning único (não silencioso)

  - **Reuso obrigatório de helpers do plano de refatoração**:
    - `BackupSizeCalculator.ofFile/ofDirectory` (PR-B)
    - `BackupArtifactUtils.safeDeletePartial/waitForStableFile` (PR-B)
    - `ToolPathHelp.buildMessage` (PR-B6 já adicionou família Firebird)
    - `ByteFormat.format` em logs

- [ ] **Estender** `ProcessService.redactCommandForLogging` para
      reconhecer `-PAS`/`-PASSWORD` e env var `FIREBIRD_PASSWORD`
      (sanitização de credenciais em logs)

- [ ] **Teste**: `firebird_backup_service_test.dart` com matriz 3
      versões (FB 2.5/3.0/4.0):
  - [ ] gbak full em FB 2.5 (sem `-SE`, sem `-KEYNAME`, Legacy direto)
  - [ ] gbak full em FB 3.0 (com `-SE service_mgr`, SRP)
  - [ ] gbak full em FB 4.0 (com `-SE service_mgr`, SRP256, com
        `-KEYNAME` quando `cryptKey`)
  - [ ] nbackup level 0 e level 1 (descoberta de cadeia) nas 3 versões
  - [ ] nbackup GUID-based em FB 4.0
  - [ ] fallback de auth: SRP→Legacy quando servidor 3.0+ recusa
  - [ ] falha fast com `WireCrypt incompatible` em FB 4.0
  - [ ] connection string FB 2.5 com fallback `host:port:path`
  - [ ] `_resolveServerVersion` cache hit/miss, hint manual
        respeitada, fallback `gstat -h` quando `gbak -z` falha
  - [ ] `cryptKey` ignorado em FB 2.5 com warning único
  - [ ] `listDatabases` retornando `Failure(NotSupported)`
  - [ ] `getDatabaseSizeBytes` priorizando `MON$DATABASE`

#### E5 — Strategy (factory)

- [ ] Criar
      `lib/application/services/strategies/rules/firebird_reject_converted_types_rule.dart`
      `implements BackupValidationRule<FirebirdConfig>`
- [ ] Criar
      `lib/application/services/strategies/rules/firebird_log_to_differential_rule.dart`
      (transparente — só ajusta `BackupType.log` → `differential` com
      warning na primeira execução)
- [ ] Criar
      `lib/application/services/strategies/firebird_backup_strategy_factory.dart`
      com as rules acima
- [ ] **Teste**: `firebird_backup_strategy_test.dart` cobre:
  - rejeição de tipos convertidos
  - conversão `log` → diferencial alto com warning
  - delegação correta para `IFirebirdBackupService`

#### E6 — Provider (trivial graças ao PR-D)

- [ ] Criar
      `lib/application/providers/firebird_config_provider.dart`:
  ```dart
  class FirebirdConfigProvider
      extends DatabaseConfigProviderBase<FirebirdConfig> {
    FirebirdConfigProvider(super.repository, super.scheduleRepository);

    @override
    FirebirdConfig duplicateConfigCopy(FirebirdConfig source) =>
        FirebirdConfig(
          name: '${source.name} (cópia)',
          host: source.host,
          databaseFile: source.databaseFile,
          // ... demais campos
        );

    // Sem override de verifyToolsOrThrow — pode adicionar futuramente
    // se quisermos verificar gbak/nbackup no PATH antes de salvar
  }
  ```
  Total: ~30 linhas (vs ~150 sem PR-D)
- [ ] Atualizar `lib/application/providers/providers.dart`: export
- [ ] **Teste**: `firebird_config_provider_test.dart`

#### E7 — DI registration

- [ ] Em `lib/core/di/infrastructure_module.dart`:
  ```dart
  getIt.registerSgbd<FirebirdConfig, FirebirdConfigsTableData>(
    repositoryBuilder: () => FirebirdConfigRepository(
      getIt<AppDatabase>(),
      getIt<ISecureCredentialService>(),
    ),
    portBuilder: () => FirebirdBackupService(getIt<ProcessService>()),
    providerBuilder: (repo, scheduleRepo) =>
        FirebirdConfigProvider(repo, scheduleRepo),
    strategyBuilder: (port) => FirebirdBackupStrategyFactory.create(port),
  );
  ```
- [ ] Atualizar `domain_module.dart` (`GetDatabaseConfig` recebe
      `IFirebirdConfigRepository`)
- [ ] Atualizar `application_module.dart` (`BackupOrchestratorService`
      recebe novos campos)
- [ ] Atualizar `presentation_module.dart` (provider na árvore)
- [ ] **Teste**: `infrastructure_module_test.dart` confirma resolução
      bem-sucedida de `FirebirdConfigProvider` e `IFirebirdBackupService`

#### E8 — Outros pontos com `switch DatabaseType` exaustivos

O analyzer aponta. Tocar:
- [ ] `lib/infrastructure/scripts/backup_script_orchestrator_impl.dart`:
      branch Firebird (script SQL pós-backup via `isql -i <script>`)
- [ ] `lib/infrastructure/external/process/sql_script_execution_service.dart`:
      branch Firebird
- [ ] `lib/infrastructure/repositories/schedule_repository.dart`:
      validação `databaseType=firebird`
- [ ] `lib/infrastructure/cleanup/backup_cleanup_service_impl.dart`:
      Firebird sem nuance especial — segue default
- [ ] `lib/infrastructure/compression/backup_compression_orchestrator_impl.dart`:
      detectar arquivo único (gbak) vs pasta (nbackup multi-nível)
- [ ] **Teste regressão**: o analyzer força tocar todos os pontos via
      `switch` exhaustive — nenhum branch oculto

---

## 4. PR-F — Firebird UI + UX (U2, U3, U6, U7)

**Objetivo**: UI Firebird usando componentes genéricos do PR-C/D + 4
melhorias de UX que se beneficiam da chegada de Firebird.

**Esforço**: 1,5 dia. **Critério**: usuário cadastra Firebird, cria
schedule, dispara backup; refator do `schedule_dialog` (U7) mantém
zero regressão nos 3 SGBDs anteriores.

### TODO list

#### F1 — `database_config_page.dart`

- [ ] Adicionar `_FirebirdConfigSection` (espelha
      `_PostgresConfigSection`, mas usa
      `DatabaseConfigDataGrid<FirebirdConfig>` do PR-C3)
- [ ] Headers usam `DatabaseTypeMetadata.of(type)` (PR-C2)
- [ ] **U2 — placeholder em seção vazia**: quando uma seção tem 0
      configs, mostrar accordion fechado: "+ Adicionar SQL Server"
      (em vez de esconder a seção). Comportamento aplicado às 4 seções
- [ ] Adicionar handlers: `_showFirebirdConfigDialog`,
      `_duplicateFirebirdConfig`, `_confirmDeleteFirebird`,
      `_toggleFirebirdEnabled`
- [ ] **Teste**: widget test renderiza 4 seções; placeholder aparece
      quando seção vazia

#### F2 — `firebird_config_dialog.dart`

- [ ] Criar `lib/presentation/widgets/firebird/` com `firebird.dart`
      (barrel)
- [ ] Criar `firebird_config_dialog.dart` usando
      `DatabaseConfigDialogShell` do PR-D5.1 (que por sua vez consome
      tokens do PR-C: `AppSpacing`, `AppRadius`, `AppDuration`,
      `context.colors`):
- [ ] Doc-comment `/// **Organism**` (segue convenção do design
      system)
- [ ] Adicionar `AppPalette.databaseFirebird` em
      `lib/core/theme/tokens/app_palette.dart` (já preparado no PR-C0.1
      como cor oficial `Color(0xFFF40F02)` Firebird red)
- [ ] Adicionar entry de Firebird em
      `DatabaseTypeMetadata._byType` do PR-D2:
  - **Seção básica**:
    - TextBox `host`
    - NumberBox `port`
    - FilePicker `databaseFile`
    - TextBox `aliasName` (opcional)
    - TextBox `username` (autocomplete `SYSDBA`)
    - `PasswordField` (com toggle do PR-C7)
    - Checkbox `useEmbedded`
    - FilePicker `clientLibraryPath` (visível se `useEmbedded=true`)
  - **Seção avançada (collapsible)**:
    - ComboBox `serverVersionHint`: `Auto-detectar`, `Firebird 2.5`,
      `Firebird 3.0`, `Firebird 4.0`
    - ComboBox `useServiceManager`: `Auto`, `Sempre`, `Nunca`
      (desabilitado e fixado em `Nunca` quando `serverVersionHint=v25`)
    - PasswordBox `cryptKey` (visível apenas quando `serverVersionHint != v25`)
    - Botão "Testar conexão" exibe versão detectada (informativo) +
      atualiza cache de `_resolveServerVersion`
  - Validações:
    - `databaseFile` não vazio sempre
    - `host` não vazio quando `useEmbedded=false`
    - `clientLibraryPath` não vazio quando `useEmbedded=true`
    - warning não-bloqueante quando `cryptKey` preenchido com
      `serverVersionHint=v25`
    - warning quando `port ≠ 3050` (informativo)
- [ ] **Teste**: `firebird_config_dialog_test.dart`
  - validação de campos por modo (Embedded vs TCP)
  - hint manual respeitada
  - cryptKey escondido em FB 2.5
  - botão "Testar conexão" exibe versão detectada

#### F3 — U6 Diálogo de duplicar permite editar nome

- [ ] Adicionar `MessageModal.showInputConfirm({title, label,
      initialValue, ...})` ou similar
- [ ] Substituir uso atual em
      `database_config_page._showDuplicateConfirmDialog`
- [ ] **Teste**: widget test simula edição de nome antes de
      confirmar

#### F4 — U3 Indicador "última conexão testada"

- [ ] Adicionar `lastTestedAt` + `lastTestStatus` no
      `DatabaseConfigProviderBase` (não persistir em DB; apenas
      cache em memória do provider)
- [ ] Adicionar coluna opcional "Última verificação" no
      `DatabaseConfigDataGrid` com badge verde/vermelho
- [ ] **Teste**: widget test simula teste e badge aparece

#### F5 — U7 Refatorar `schedule_dialog.dart` em TabView

Esta é a parte mais delicada do PR-F. O `schedule_dialog.dart` (84
KB, 2200 linhas) precisa ganhar o branch Firebird mas adicionar mais
30 `if (_databaseType == X)` em arquivo já gigante é inviável.

**Plano** (refator preventivo):
- [ ] **F5.1** — Extrair `_GeneralSection` (nome, banco config, tipo
      de backup, habilitado)
- [ ] **F5.2** — Extrair `_ScheduleSection` (tipo daily/weekly/monthly/interval + parâmetros)
- [ ] **F5.3** — Extrair `_CompressionVerifySection`
- [ ] **F5.4** — Extrair `_DestinationsSection`
- [ ] **F5.5** — Extrair `_AdvancedSection` polimórfico via factory
      por `DatabaseType` (Sybase log mode, SQL Server stripes,
      Firebird `useServiceManager`/`cryptKey` indicador, etc.)
- [ ] **F5.6** — Adicionar Firebird ao `_AdvancedSection` factory
- [ ] **Teste regressão crítico**: golden tests dos 3 SGBDs ANTES;
      rodar idêntico depois (ou widget test detalhado capturando o
      formulário renderizado)
- [ ] **Teste novo**: `schedule_dialog_firebird_test.dart`
  - tipos de backup oferecidos (sem `convertedXxx`)
  - tooltip explicativo para `log` → diferencial alto

---

## 5. PR-G — Firebird remoto (socket cliente↔servidor) + U10

**Objetivo**: cliente conectado a servidor com `supportsFirebird=true`
opera Firebird remoto.

**Esforço**: 1 dia. **Critério**: cliente moderno em servidor antigo
recebe `unsupportedDatabaseType` e UI esconde Firebird; cliente
moderno em servidor moderno opera Firebird remoto.

> **Pré-requisito**: este PR depende do trabalho descrito em
> [`plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`](./plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md)
> estar com PR-1 (capabilities) já no main. Hoje (2026-04-19) está
> entregue.

### TODO list

#### G1 — Protocolo

- [ ] `lib/infrastructure/protocol/schedule_serialization.dart`:
      branch para serializar/desserializar `DatabaseType.firebird`
- [ ] `lib/infrastructure/protocol/capabilities_messages.dart`: novo
      campo `supportsFirebird` em `ServerCapabilities` (default `false`
      no `legacyDefault`)
- [ ] `lib/infrastructure/protocol/protocol_versions.dart`: bump
      `kCurrentProtocolVersion` (lógico) — wire version permanece
      (mudança é additive backward-compat)
- [ ] `lib/infrastructure/protocol/error_codes.dart`: novo
      `unsupportedDatabaseType` (cliente moderno enviando Firebird
      para servidor antigo deve falhar fast)

#### G2 — Server-side

- [ ] `lib/infrastructure/socket/server/schedule_message_handler.dart`:
      injeção do `IFirebirdConfigRepository` para CRUD remoto (depende
      do PR-2 do plano remoto: `createDatabaseConfig` etc.)

#### G3 — Capabilities flag e UI

- [ ] `ConnectionManager.isFirebirdSupported` (passa-through)
- [ ] `ServerConnectionProvider.isFirebirdSupported` (passa-through)
- [ ] `database_config_page` esconde botão/seção Firebird quando
      conectado em modo remoto e `!isFirebirdSupported`
- [ ] `schedule_dialog` filtra opção Firebird quando remoto e flag
      falsa

#### G4 — U10 InfoBar não-bloqueante

- [ ] Substituir `MessageModal.showSuccess/showInfo` por
      `displayInfoBar` do Fluent UI em fluxos save/refresh:
  ```dart
  displayInfoBar(
    context,
    builder: (_, close) => InfoBar(
      title: const Text('Configuração salva'),
      severity: InfoBarSeverity.success,
      onClose: close,
    ),
  );
  ```
- [ ] Manter `MessageModal.showError` para erros críticos (continuam
      modais)
- [ ] **Teste**: atualizar testes E2E que esperavam modal flash;
      documentar mudança no changelog

#### G5 — Golden tests

- [ ] Criar `test/golden/protocol/capabilities_response_with_firebird.golden.json`
- [ ] Criar `test/golden/protocol/schedule_message_firebird.golden.json`
- [ ] Atualizar fixture existente `capabilities_response_v1.golden.json`
      para refletir novo campo `supportsFirebird=false` no envelope
      legacy default

---

## 6. Riscos específicos de Firebird

| Risco | PR | Mitigação |
|---|---|---|
| `gbak` não tem verify nativo; usuários esperam o mesmo nível de garantia que SQL Server `CHECKSUM`/Postgres `pg_verifybackup` | E + F | Tooltip claro no schedule_dialog: "Firebird não suporta verify nativo. Use 'Strict' apenas se tiver espaço extra para restore temporário". Salvar `verifyMode=skipped\|restoreToTemp` em `BackupMetrics.flags` |
| Confusão `gbak` vs `nbackup` (artefatos com semânticas diferentes) | F | Tooltip por tipo no schedule_dialog explicando ferramenta usada; salvar `tool=gbak\|nbackup` + `firebirdVersion=v25\|v30\|v40` em `BackupMetrics.flags` para auditoria |
| FB 2.5 com Legacy_Auth pode falhar em servidores configurados só para SRP | E | Detectar mensagem `Your user name and password are not defined` e propagar erro com remediação (`AuthServer = Legacy_Auth, Srp` em `firebird.conf`) |
| FB 4.0 com `WireCrypt = Required` rejeita clientes 2.5/3.0 antigos sem WireCrypt | E | Detectar `Incompatible wire encryption requirements` e falhar fast com remediação (`WireCrypt = Enabled` no servidor ou atualizar binários) |
| Detecção automática de versão (`gbak -z`/`gstat -h`) pode falhar em ambientes restritos | E | Respeitar `serverVersionHint` quando preenchido manualmente; em `unknown` assumir `v30` (meio-termo seguro) e logar warning único |
| Cache de versão pode ficar stale após upgrade do servidor | E + F | Cache em memória (perde no restart); botão "Testar conexão" no dialog força re-detecção; documentar que mudança de versão exige restart ou save da config |
| `cryptKey` salvo na storage segura mas usuário muda `serverVersionHint` para `v25` (que ignora) | E + F | Service loga warning único por execução; UI mostra warning não-bloqueante no dialog |
| Backup nbackup com nível incremental sem o nível anterior gera erro críptico | E | Replicar padrão Postgres incremental: `_findPreviousNBackup` valida cadeia, fallback automático para nível 0 quando ausente, registrando `executedBackupType` no `BackupExecutionResult` |
| `nbackup` em FB 4.0 com GUID-based incompatível com cadeia FB 3.0 antiga | E | Cache de versão impede misturar; ao detectar mudança de versão entre execuções na mesma cadeia, forçar fallback para `BackupType.full` (level 0) com log explicativo |
| Embedded em FB 3.0+ exige plugins (`engine12.dll`/`engine13.dll`) na pasta — usuário aponta `clientLibraryPath` mas esquece plugins | E | `_validateEmbeddedSetup` checa existência das DLLs esperadas baseado em `serverVersionHint` antes de tentar backup; falha fast com mensagem clara |
| Tamanho do banco indisponível (`MON$DATABASE` sem permissão, arquivo remoto/UNC inacessível) | E | Cair em fallback `gstat -h` → `BackupConstants.minFreeSpaceForBackupBytes` com warning |
| Refator U7 (TabView no schedule_dialog) muda fluxo de UX que usuários estão acostumados | F | Comunicar mudança no changelog; preferir fluxo conservador com tabs em ordem alinhada à dos campos atuais |
| Migration Drift v29→v30 em base existente pode falhar em ambientes com SQLite corrompido | E | `try { ... ensureTableExists } catch` defensivo igual `_ensureSybaseConfigsTableExists` |
| Capabilities flag `supportsFirebird=false` em clientes antigos quebra UI | G | `ServerConnectionProvider.isFirebirdSupported` cai em `legacyDefault=false`; UI consulta antes de exibir |
| Mudança `MessageModal` → `InfoBar` (U10) muda comportamento esperado em testes E2E | G | Atualizar testes E2E; documentar no changelog |

---

## 7. Fora de escopo

- Restore automatizado de backups Firebird (apenas backup é o foco
  do app)
- Backup de bancos Firebird em modo Embedded multi-arquivo
  (`secondary files`) — usaremos sempre `databaseFile` único; bancos
  com secondaries vão falhar com mensagem clara
- Replicação Firebird 4.0 nativa (não há equivalente ao
  `is_replication_environment` do Sybase; pode entrar em PR futuro)
- Streaming WAL-like (não existe em Firebird; `nbackup` incremental
  é o substituto já coberto)
- Integração com `RDB$BACKUP_HISTORY` para reconstruir histórico de
  backups feitos fora do app (escopo de "import legado", futuro)
- `ALTER DATABASE BEGIN/END BACKUP` exposto diretamente ao usuário
  (usado internamente pelo nbackup; sem motivo para expor)

---

## 8. Checklist de Pré-Entrega Firebird

### PR-E
- [ ] `dart analyze` zero issues
- [ ] `flutter test` todas suítes verde
- [ ] `dart run build_runner build` executado e arquivos `.g.dart`
      commitados
- [ ] Migration testada com base v29 existente (não apenas
      `inMemory`)
- [ ] `gbak -z`, `nbackup -?`, `gstat -z`, `isql -z` documentados
      no README como pré-requisitos do servidor
- [ ] `ToolPathHelp` reconhece família Firebird (já feito no PR-B6
      do plano de refatoração)
- [ ] `ProcessService` redact estendido para `-PAS`/`-PASSWORD` e
      `FIREBIRD_PASSWORD`
- [ ] Logs de execução incluem `tool=gbak\|nbackup` +
      `firebirdVersion=v25\|v30\|v40` em `BackupMetrics.flags`
- [ ] Smoke manual ponta-a-ponta executado nas três versões:
  - [ ] Firebird 2.5 com Legacy_Auth, sem WireCrypt, gbak full +
        nbackup level 0/1
  - [ ] Firebird 3.0 com SRP, WireCrypt opcional, gbak via service
        manager, nbackup multi-nível
  - [ ] Firebird 4.0 com SRP256, WireCrypt=Enabled, gbak com
        `-KEYNAME` (banco criptografado opcional), nbackup
        GUID-based
- [ ] Embedded testado em FB 3.0 (`engine12.dll`) e FB 4.0
      (`engine13.dll`)
- [ ] `_resolveServerVersion` cache validado (uma chamada `gbak -z`
      por execução, não por argumento)
- [ ] `getDatabaseSizeBytes` testado: `MON$DATABASE` priorizado,
      fallback para `gstat -h`, fallback para `File.length()`

### PR-F
- [ ] Refator F5 (TabView no `schedule_dialog`) mantém regressão
      zero nos 3 SGBDs anteriores (golden tests verde antes/depois)
- [ ] `database_config_page` com 4 seções renderizando em
      Light/Dark
- [ ] Botão "Testar conexão" no `firebird_config_dialog` exibe
      versão detectada e mensagem amigável de erro
- [ ] U2/U3/U6 entregues com print/screenshot no PR description

### PR-G
- [ ] Goldens passam para `capabilities_response` com
      `supportsFirebird=true|false`
- [ ] Smoke manual cliente moderno conectando em servidor antigo
      (esconde Firebird na UI)
- [ ] Smoke manual cliente moderno conectando em servidor moderno
      (executa backup Firebird remoto)
- [ ] Documentar em `protocol_versions.dart` o bump de
      `kCurrentProtocolVersion`
- [ ] U10 entregue (InfoBar não-bloqueante para mensagens
      informativas)

---

## 9. Cross-references

- **Plano de refatoração** (pré-requisito): [`plano_refatoracao_e_melhorias_2026-04-19.md`](./plano_refatoracao_e_melhorias_2026-04-19.md)
- Plano de execução remota cliente↔servidor: [`plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md`](./plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md)
- Auditoria de qualidade prévia: [`auditoria_qualidade_2026-04-18.md`](./auditoria_qualidade_2026-04-18.md)
- Rule de padrões arquiteturais: [`.cursor/rules/architectural_patterns.mdc`](../../.cursor/rules/architectural_patterns.mdc)
