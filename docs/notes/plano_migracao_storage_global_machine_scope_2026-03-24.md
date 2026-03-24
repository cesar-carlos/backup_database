# Plano: Migracao de Storage por Usuario para Storage Global da Maquina

Data base: 2026-03-24
Status: **Concluido** (2026-03-24) — mesmo escopo anterior; **pesquisa UAC** passa a preferir `legacy_profile_scanner.exe` (C++17, mesmo JSON que o script PS) ao lado do `.exe` principal, com elevacao via `ShellExecuteEx`/`runas` em `windows_shell_execute_runas.dart`; **fallback** para PowerShell se o auxiliar nao existir (ex.: builds antigos).
Escopo: Windows desktop, UI + modo servico
Objetivo: migrar configuracoes e persistencia operacional hoje dependentes do perfil do usuario para escopo global da maquina, preservando Clean Architecture e reduzindo divergencia entre UI e servico

## Objetivo de Negocio

- Tornar a configuracao operacional compartilhada por todos os usuarios do Windows na mesma maquina.
- Alinhar a persistencia com a regra ja existente de "uma instancia por computador".
- Parar de depender de `%APPDATA%` e de `SharedPreferences` para configuracoes operacionais criticas.
- Centralizar banco, logs, staging, locks e configuracoes machine-scope em `C:\ProgramData\BackupDatabase`.
- Manter o padrao novo de defaults desativados para:
  - `Tema escuro`
  - `Iniciar com o Windows`
  - `Iniciar minimizado`
  - `Minimizar para bandeja`
  - `Fechar para bandeja`

## Registro de implementacao (codigo)

Ultima atualizacao: 2026-03-24 — **melhorias pos-revisao:** `legacy_profile_scanner.exe` escreve JSON de forma **atomica** (`*.tmp` + rename) e inclui `schemaVersion: 1`; Dart: `elevated_legacy_profile_scan_outcome.dart` (decode com validacao de schema, `LegacyElevatedScanMethod`, `ElevatedLegacyScanFailureKind`, detecao **UAC cancelado** via `GetLastError` == 1223 no caminho nativo); `ShellExecuteRunAsResult` em `windows_shell_execute_runas.dart`; logs `developer.log` para caminho **nativo vs PowerShell**; Definicoes gerais: mensagens especificas para UAC recusado e JSON invalido; migracao automatica SQLite: **ate 3 tentativas** de `PRAGMA quick_check` com **200 ms** entre tentativas; script PS de fallback alinhado com `schemaVersion = 1`; testes `elevated_legacy_profile_scan_outcome_test.dart`

### Entregue

- Contratos `IMachineSettingsRepository`, `IUserPreferencesRepository` em `lib/domain/repositories/`
- Tabela Drift `machine_settings_table` (schema v29), DAO `MachineSettingsDao`, repositorio `MachineSettingsRepository`:
  - linha singleton `id = 1`; campos: `start_with_windows`, `start_minimized`, `custom_temp_downloads_path`, `received_backups_default_path`, `schedule_transfer_destinations_json`
  - na primeira leitura sem linha: seed a partir das chaves legadas em `SharedPreferences` e remocao dessas chaves machine-scope dos prefs
- `UserPreferencesRepository` (`SharedPreferences`): `minimize_to_tray`, `close_to_tray`, `dark_mode` + `ensureTrayDefaults()`
- `SystemSettingsProvider`: machine via `IMachineSettingsRepository`, bandeja via `IUserPreferencesRepository` (sem `SharedPreferences` direto)
- `ThemeProvider` movido para `lib/presentation/providers/theme_provider.dart` + `IUserPreferencesRepository`
- `TempDirectoryService`: caminho customizado via `IMachineSettingsRepository`; registro DI em `domain_module.dart` (apos repositorios)
- `RemoteFileTransferProvider`: paths default e mapa de destinos via `IMachineSettingsRepository`
- `AppInitializer.getLaunchConfig`: `start_minimized` via `IMachineSettingsRepository`
- Testes atualizados: `system_settings_provider_test`, `temp_directory_service_test`
- Testes dedicados (2026-03-24): `machine_settings_repository_test.dart` — seed Drift + prefs legadas; `user_preferences_repository_test.dart` — bandeja, tema, assinatura R1; `app_data_directory_resolver_test.dart` — `ProgramData`, subpastas machine-scope, legado `%APPDATA%`, `skip` por plataforma; `theme_provider_test.dart` — init, idempotencia, `setDarkMode`/`toggleTheme`; `temp_directory_service_test.dart` — ampliado (path invalido, `validateDownloadsDirectory`)

- **Fase 4 — startup machine-scope (2026-03-24):**
  - Contrato `IWindowsMachineStartupService` + `WindowsMachineStartupOutcome` em `lib/domain/services/i_windows_machine_startup_service.dart`
  - Implementacao `WindowsMachineStartupService` + XML em `machine_startup_task_xml.dart` (`lib/infrastructure/external/system/`): tarefa `BackupDatabase\MachineStartup` com `LogonTrigger` (qualquer utilizador), criada via `schtasks /Create /XML`
  - Remocao idempotente de legado `HKCU\...\Run\BackupDatabase` em todo `apply`
  - **Modo servidor (`AppMode.server`):** nao instala tarefa de logon; autostart continua a ser o Windows Service; preferencia `start_with_windows` persiste no Drift
  - **Cliente / unificado:** instala ou remove a tarefa; `SystemSettingsProvider` usa `_appModeProvider` injetavel (default `currentAppMode`)
  - Registo em `infrastructure_module`; `BackupDatabaseApp` injeta o servico no provider
  - UI (`general_settings_tab`): texto de apoio por modo (servico vs tarefa para todos os utilizadores / admin)
  - Testes: `machine_startup_task_xml_test.dart`; provider tests com fake do servico de startup

- **Fase 5 — secure storage machine-scope (2026-03-24):**
  - `MachineScopeSecureCredentialService` (`lib/infrastructure/security/machine_scope_secure_credential_service.dart`) como implementacao de `ISecureCredentialService` registada em `core_module`
  - **Windows:** ficheiros `*.bdsecret` em `%ProgramData%\BackupDatabase\secrets\`; payload UTF-8 (versao + chave logica + valor) protegido com **DPAPI** `CRYPTPROTECT_LOCAL_MACHINE` (`windows_dpapi_local_machine.dart` + `win32`)
  - **Migracao lazy:** em `getPassword` / `getToken`, se nao existir blob na maquina le `FlutterSecureStorage` legado, grava blob, apaga chave legada
  - **Nao-Windows:** comportamento anterior apenas com `FlutterSecureStorage` (sem ficheiros machine-scope)
  - `MachineStorageLayout.secrets`, `resolveMachineSecretsDirectory()`, pasta criada em `ensureMachineStorageDirectoriesExist()`
  - Codec testavel: `credential_machine_blob_codec.dart`; testes `credential_machine_blob_codec_test.dart`
  - Repositorios e servicos OAuth/SMTP **inalterados** (mesmas chaves logicas)

- **Fase 6 parcial / PR-6 (2026-03-24):**
  - `MachineLegacyMigrationSummary` + retorno de `ensureLegacyAppDataMigratedToMachineScope()`
  - `findLegacyBackupDatabasePathsOutsideCurrentUser()` (R1; overrides para testes); `countLegacyLogFilesVisibleForCurrentUser()`
  - `recordMachineStorageBootstrapDiagnostics` em `machine_storage_bootstrap_diagnostics.dart`; ficheiro `config\migration_state.json`
  - `setupCoreModule`: apos init do logger, `migrateLegacyUserLogFilesToMachineScopeIfNeeded()`; depois regista paths, migracao DB, backend de segredos, R1 e contagem de logs legados
  - Constantes: `legacyAppdataLogsMigrationMarker`, `legacyImportedLogsSubdirectory`; resultado `LegacyUserLogsMigrationResult`; JSON `legacyUserLogsImport`
  - Testes: perfis + migracao de logs em `machine_storage_migration_test.dart`
  - R1 UI: `MachineScopeR1LegacyPathsHint` (`core/bootstrap/`); `IUserPreferencesRepository` + chave `r1_multi_profile_legacy_hint_dismissed_sig`; `R1MultiProfileLegacyHintHost` + registo em `core_module` / `app_widget`
  - Teste: `machine_scope_r1_legacy_paths_hint_test.dart`
  - **Importacao assistida SQLite (2026-03-24):** `LegacySqliteFolderImportService` — valida cabecalho (`sqlite_database_file_validation.dart`) + `PRAGMA quick_check` em modo leitura; listas extra no resultado (cabecalho invalido, quick_check, falha de copia); `LoggerService.info` quando copia > 0; `SqliteBundleCopyException` na migracao de bundles com try/catch no bootstrap legado; ao copiar chama `migrateSqliteDatabaseBundleIfNeeded(..., runQuickCheck: false)` porque a validacao ja foi feita no servico
  - **Migracao automatica SQLite (2026-03-24):** `migrateSqliteDatabaseBundleIfNeeded` — apos tamanho > 0, exige cabecalho SQLite valido e, se `runQuickCheck` (default `true`), `PRAGMA quick_check` == ok; caso contrario regista em log e nao copia (ficheiro bloqueado / corrompido fica em `%APPDATA%` ate nova tentativa ou import assistido)
  - **UI armazenamento (2026-03-24):** `machine_storage_settings_section.dart` (Definicoes gerais); varredura de perfis no primeiro frame; texto **Ultima pesquisa**; botao **Pesquisar como administrador** (`windows_legacy_profile_elevated_scan.dart`: **nativo** `legacy_profile_scanner.exe` + `windows_shell_execute_runas.dart`, fallback PowerShell; JSON em `%TEMP%`; merge `mergeLegacyProfilePathsExcludingCurrentUser`); `Semantics` em accoes principais; mensagens para `FileSystemException` / ficheiro em uso
  - R1 / listagem de perfis: `_directoryHasNonEmptyLegacySqlite` exige cabecalho SQLite valido (alinhado ao import)
  - Testes: `sqlite_database_file_validation_test.dart`, `windows_legacy_profile_elevated_scan_test.dart` (merge), `sqlite_test_helpers.dart`, `machine_storage_settings_section_test.dart`; import + migracao atualizados para `.db` minimos via `sqlite3`

- API de diretorios machine-scope em `lib/core/utils/app_data_directory_resolver.dart`:
  - `resolveMachineRootDirectory()` -> `%ProgramData%\BackupDatabase` (Windows)
  - `resolveMachineDataDirectory()` -> `...\data` (Windows) ou diretorio de documentos (nao-Windows, sem subpasta `data`)
  - `resolveMachineStagingBackupsDirectory()` -> `...\staging\backups` (Windows) ou `...\backups` (nao-Windows)
  - `resolveMachineLocksDirectory()` -> `...\locks`
  - `resolveMachineSecretsDirectory()` -> `...\secrets` (Windows)
  - `resolveLegacyWindowsUserAppDataDirectory()` -> `%APPDATA%\Backup Database` (apenas Windows)
  - `resolveAppDataDirectory()` permanece como alias de `resolveMachineRootDirectory()` (evitar novos usos ambiguos)
- Constantes de layout em `lib/core/utils/machine_storage_layout.dart`
- Migracao idempotente em `lib/core/utils/machine_storage_migration.dart`:
  - `ensureMachineStorageDirectoriesExist()` cria arvore de pastas (inclui `secrets\` no Windows)
  - `ensureLegacyAppDataMigratedToMachineScope()` copia `.db` / `.db-wal` / `.db-shm` para `data\` se destino inexistente ou vazio e a origem passar cabecalho + `PRAGMA quick_check` (por defeito)
  - marker opcional: `config\legacy_appdata_migration.done` apos copia bem-sucedida
- `setupCoreModule`: executa diretorios + migracao legada **antes** de `_dropConfigTablesForVersion223` e do Drift
- Banco Drift: `lib/infrastructure/datasources/local/database.dart` abre em `resolveMachineDataDirectory()`
- Logs gerais: `core_module` usa `MachineStorageLayout.logs` sob machine root
- Staging/locks: `infrastructure_module` usa `resolveMachineStagingBackupsDirectory()` e `resolveMachineLocksDirectory()`
- `database_migration_224.dart` le caminho do banco via `resolveMachineDataDirectory()`
- Testes: `test/unit/core/utils/machine_storage_migration_test.dart`

### Pendente (alinhado ao plano original)

- Nenhum item bloqueante; PowerShell permanece apenas como **fallback** se `legacy_profile_scanner.exe` nao estiver presente (builds antigos / copia manual incompleta)

## Resumo Executivo

Hoje o projeto tem um modelo misto:

- exclusividade de execucao ja e global por maquina;
- banco e logs da UI ainda priorizam o perfil do usuario atual;
- configuracoes da tela `Geral` e varias preferencias operacionais usam `SharedPreferences`;
- segredos e tokens ficam em `FlutterSecureStorage`, que no Windows tende a seguir contexto do usuario logado;
- o modo servico usa o mesmo `setupCoreModule()` da UI, mas parte dos logs do servico ja vai para `ProgramData`.

Isso cria uma inconsistencia estrutural: o app se comporta como "single machine instance", mas os dados ainda podem ser "single user profile".

## Diagnostico do Codigo Atual

### 1. A regra de instancia unica ja e global da maquina

Evidencias:

- `lib/core/config/single_instance_config.dart:48`
- `lib/core/config/single_instance_config.dart:50`
- `lib/infrastructure/external/system/single_instance_service.dart:75`
- `lib/presentation/boot/single_instance_checker.dart:51`

Analise:

- o mutex usa `Global\BackupDatabase_UIMutex...` e `Global\BackupDatabase_ServiceMutex...`;
- a mensagem para o usuario fala explicitamente em "neste computador";
- portanto, a semantica de execucao ja e machine-scope.

Conclusao:

- persistencia operacional por usuario nao combina com a regra de instancia unica ja implementada.

### 2. O diretorio base de dados da UI ainda prioriza `%APPDATA%`

Evidencias:

- `lib/core/utils/app_data_directory_resolver.dart:8`
- `lib/core/utils/app_data_directory_resolver.dart:10`
- `lib/core/utils/app_data_directory_resolver.dart:12`
- `lib/core/utils/app_data_directory_resolver.dart:16`
- `lib/core/utils/app_data_directory_resolver.dart:17`

Analise:

- em Windows, `resolveAppDataDirectory()` retorna `%APPDATA%\Backup Database` se `APPDATA` existir;
- `ProgramData` hoje e apenas fallback;
- na pratica, a UI roda quase sempre por usuario.

Conclusao:

- esse resolver e o principal ponto de ruptura entre o modelo atual e o modelo desejado.

### 3. Banco SQLite da aplicacao depende desse resolver

Evidencias:

- `lib/infrastructure/datasources/local/database.dart:2004`
- `lib/infrastructure/datasources/local/database.dart:2006`
- `lib/infrastructure/datasources/local/database.dart:2008`

Analise:

- o Drift abre o banco em `resolveAppDataDirectory()`;
- como o resolver hoje prioriza `%APPDATA%`, o banco principal e por usuario;
- como os nomes de banco por modo ja existem (`backup_database`, `backup_database_client`), a separacao por modo esta pronta, mas nao a separacao por escopo.

Conclusao:

- migrar o resolver sem plano de migracao de dados pode mover a UI para outro banco e aparentar "perda" de configuracao.

### 4. UI e servico compartilham bootstrap de core, mas nao o mesmo conceito de path

Evidencias:

- `lib/core/di/service_locator.dart:23`
- `lib/core/di/service_locator.dart:35`
- `lib/core/di/core_module.dart:370`
- `lib/core/di/core_module.dart:376`
- `lib/core/di/core_module.dart:398`
- `lib/core/di/core_module.dart:399`
- `lib/presentation/boot/service_mode_initializer.dart:82`

Analise:

- UI e modo servico passam por `setupCoreModule(getIt)`;
- `setupCoreModule()` monta logs em `appDataDir/logs`;
- como `appDataDir` hoje pode variar por usuario, o servico e a UI podem divergir no banco/logs dependendo do contexto do processo;
- isso e especialmente perigoso quando o servico roda sob `LocalSystem`.

Conclusao:

- a migracao precisa unificar o path base antes de qualquer evolucao de configuracao global.

### 5. Os logs ja estao parcialmente em `ProgramData`, mas de forma inconsistente

Evidencias:

- `lib/core/constants/app_constants.dart:74`
- `lib/core/constants/app_constants.dart:75`
- `lib/presentation/boot/service_mode_initializer.dart:17`
- `lib/presentation/boot/service_mode_initializer.dart:19`
- `lib/presentation/boot/service_mode_initializer.dart:233`
- `lib/infrastructure/external/system/windows_service_service.dart:71`
- `lib/infrastructure/external/system/windows_service_service.dart:73`

Analise:

- logs do controle do servico e bootstrap do servico ja usam `C:\ProgramData\BackupDatabase\logs`;
- logs gerais da aplicacao ainda nascem via `core_module.dart` com base em `resolveAppDataDirectory()`.

Conclusao:

- o projeto ja admite `ProgramData` como local correto para operacao machine-scope;
- falta aplicar a mesma decisao ao restante da aplicacao.

### 6. As configuracoes da tela `Geral` ainda sao por usuario

Evidencias:

- `lib/presentation/providers/system_settings_provider.dart:25`
- `lib/presentation/providers/system_settings_provider.dart:45`
- `lib/presentation/providers/system_settings_provider.dart:94`
- `lib/presentation/providers/system_settings_provider.dart:108`
- `lib/presentation/providers/system_settings_provider.dart:121`
- `lib/presentation/providers/system_settings_provider.dart:139`
- `lib/presentation/providers/system_settings_provider.dart:146`
- `lib/presentation/providers/system_settings_provider.dart:162`

Analise:

- `SystemSettingsProvider` usa `SharedPreferences`;
- `Iniciar com o Windows` usa `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`;
- isso e explicitamente por usuario, nao por maquina;
- os defaults novos ja foram ajustados para `false`, mas a persistencia continua user-scope.

Conclusao:

- apenas trocar defaults nao resolve o problema estrutural;
- o provider precisa ser migrado para um repositrio/store machine-scope.

### 7. Tema escuro tambem e por usuario

Evidencias:

- `lib/core/theme/theme_provider.dart:5`
- `lib/core/theme/theme_provider.dart:16`
- `lib/core/theme/theme_provider.dart:36`

Analise:

- `ThemeProvider` tambem usa `SharedPreferences`.

Conclusao:

- tecnicamente pode permanecer user-scope;
- tornar tema global e uma decisao de produto, nao uma necessidade operacional.

### 8. Pasta temporaria de downloads do cliente ainda e por usuario

Evidencias:

- `lib/core/services/temp_directory_service.dart:7`
- `lib/core/services/temp_directory_service.dart:8`
- `lib/core/services/temp_directory_service.dart:34`
- `lib/core/services/temp_directory_service.dart:41`
- `lib/core/services/temp_directory_service.dart:79`
- `lib/core/services/temp_directory_service.dart:144`

Analise:

- o caminho customizado e salvo em `SharedPreferences`;
- o fallback e `Directory.systemTemp`;
- em Windows, isso tende a apontar para area do usuario ou contexto do processo.

Conclusao:

- se a regra for "configuracao operacional global", esse service precisa sair de `SharedPreferences`.

### 9. Outras preferencias operacionais espalhadas ainda usam `SharedPreferences`

Evidencias:

- `lib/presentation/boot/app_initializer.dart:74`
- `lib/application/providers/remote_file_transfer_provider.dart:119`
- `lib/application/providers/remote_file_transfer_provider.dart:131`
- `lib/application/providers/google_auth_provider.dart:202`
- `lib/application/providers/google_auth_provider.dart:230`
- `lib/application/providers/google_auth_provider.dart:247`
- `lib/application/providers/dropbox_auth_provider.dart:186`
- `lib/application/providers/dropbox_auth_provider.dart:214`
- `lib/application/providers/dropbox_auth_provider.dart:229`

Analise:

- `start_minimized` e lido no boot da UI em `AppInitializer`;
- `received_backups_default_path` e `schedule_transfer_destinations` estao em `RemoteFileTransferProvider`;
- configs OAuth de Google e Dropbox tambem estao em `SharedPreferences`.

Conclusao:

- a migracao precisa tratar tambem preferencias fora da tela `Geral`, senao a aplicacao continua parcialmente por usuario.

### 10. Senhas e tokens (historico: `FlutterSecureStorage`; atual: machine-scope no Windows)

Evidencias (implementacao atual):

- `lib/infrastructure/security/machine_scope_secure_credential_service.dart`
- `lib/infrastructure/security/windows_dpapi_local_machine.dart`

Analise:

- SQL Server, Sybase, PostgreSQL, SMTP, Google OAuth e Dropbox OAuth usam `ISecureCredentialService`;
- **Windows (2026-03-24):** blobs DPAPI `LOCAL_MACHINE` em `%ProgramData%\BackupDatabase\secrets\`, com migracao lazy a partir do `FlutterSecureStorage` legado;
- fora do Windows mantem-se `FlutterSecureStorage` ate decisao futura.

Conclusao:

- migrar apenas arquivos e banco nao basta;
- sera necessario substituir ou encapsular `FlutterSecureStorage` com uma implementacao machine-scope.

## Decisao Arquitetural Recomendada

### Regra principal

Separar explicitamente:

- `machine-scope`: configuracoes operacionais e persistencia compartilhada pela maquina;
- `user-scope`: preferencias puramente de experiencia visual/local do usuario.

### Recomendacao de classificacao

#### Deve virar machine-scope

- banco SQLite principal da aplicacao;
- logs gerais da aplicacao;
- staging de transferencias;
- locks operacionais;
- configuracoes de sistema:
  - `start_with_windows`
  - `start_minimized`
  - `custom_temp_downloads_path`
- preferencias operacionais do fluxo remoto:
  - `received_backups_default_path`
  - `schedule_transfer_destinations`
- credenciais e tokens operacionais:
  - senhas de banco
  - credenciais do servidor
  - segredos SMTP
  - tokens OAuth usados pela operacao

#### Recomendacao: manter user-scope

- `dark_mode`
- `minimize_to_tray`
- `close_to_tray`

Justificativa:

- sao preferencias de UX da sessao interativa;
- nao sao necessarias para consistencia operacional da maquina;
- tornar essas preferencias globais significa que um usuario altera o comportamento de todos os demais.

#### Alternativa, se o produto exigir "tudo global"

Tambem e viavel tornar `dark_mode`, `minimize_to_tray` e `close_to_tray` machine-scope, mas isso deve ser assumido como escolha explicita de produto, nao como necessidade tecnica.

## Modelo de Destino

### Estrutura alvo em disco

```text
C:\ProgramData\BackupDatabase\
  data\
    backup_database.db
    backup_database_client.db
  logs\
    app_YYYY-MM-DD.log
    socket_YYYY-MM-DD.log
    service_bootstrap.log
    service_control_diagnostics.log
  staging\
    backups\
  locks\
  config\
    machine_settings.json        # opcao A
  secrets\
    machine_secrets.dat          # opcao B, se usar arquivo protegido por DPAPI
```

### Fonte de verdade recomendada

Recomendacao principal:

- usar o banco SQLite em `ProgramData` como fonte de verdade para `machine settings`;
- evitar criar um novo centro de persistencia se o projeto ja tem banco, migrations e DI prontos.

Opcao de implementacao:

- criar `machine_settings_table` no Drift para configuracoes machine-scope;
- manter `SharedPreferences` apenas para `user preferences`.

## Proposta de Arquitetura para a Migracao

### 1. Resolver de diretorios por escopo

Criar uma abstracao explicita de path, em vez de usar um unico `resolveAppDataDirectory()` ambiguo.

Proposta:

- `resolveMachineDataDirectory()`
- `resolveUserPreferencesDirectory()` ou manter `SharedPreferences` apenas para user-scope

Arquivos impactados:

- `lib/core/utils/app_data_directory_resolver.dart`
- `lib/core/di/core_module.dart`
- `lib/core/di/infrastructure_module.dart`
- `lib/infrastructure/datasources/local/database.dart`

### 2. Repositorio de configuracoes machine-scope

Criar contrato para leitura/escrita de configuracoes operacionais, desacoplando `SystemSettingsProvider` de `SharedPreferences`.

Proposta:

- interface: `IMachineSettingsRepository`
- implementacao: `MachineSettingsRepository`
- datasource: tabela Drift ou arquivo em `ProgramData`

Arquivos candidatos:

- `lib/domain/repositories/i_machine_settings_repository.dart`
- `lib/infrastructure/repositories/machine_settings_repository.dart`
- `lib/infrastructure/datasources/daos/machine_settings_dao.dart`
- `lib/infrastructure/datasources/local/tables/machine_settings_table.dart`

### 3. Repositorio de preferencias de usuario

Manter um contrato separado para preferencias da UI.

Proposta:

- interface: `IUserPreferencesRepository`
- `ThemeProvider` e possivelmente preferencias de bandeja passam a depender desse contrato, nao diretamente de `SharedPreferences`.

Arquivos candidatos:

- `lib/domain/repositories/i_user_preferences_repository.dart`
- `lib/infrastructure/repositories/user_preferences_repository.dart`
- `lib/core/theme/theme_provider.dart`

### 4. Secret store machine-scope

O ponto mais sensivel da migracao.

Recomendacao:

- introduzir uma nova implementacao de credenciais baseada em DPAPI machine-scope (`CRYPTPROTECT_LOCAL_MACHINE`) ou equivalente seguro;
- manter segredo fora do banco em texto puro;
- nao depender de `FlutterSecureStorage` como fonte final de segredos compartilhados.

Proposta:

- interface existente permanece: `ISecureCredentialService`
- nova implementacao: `MachineScopeSecureCredentialService`
- persistencia:
  - opcao A: arquivo cifrado em `ProgramData\BackupDatabase\secrets`
  - opcao B: valores cifrados no banco, protegidos por DPAPI machine-scope antes da escrita

Arquivos impactados:

- `lib/infrastructure/security/machine_scope_secure_credential_service.dart`
- `lib/core/di/core_module.dart`
- repositrios/servicos que hoje assumem o comportamento atual

## Plano de Migracao por Fases

## Fase 0 - Fundacao e isolamento de responsabilidades

Objetivo:

- preparar a arquitetura sem mudar ainda a semantica completa do produto.

Entregas:

- criar resolveres explicitos de path por escopo;
- introduzir interfaces:
  - `IMachineSettingsRepository`
  - `IUserPreferencesRepository`
- encapsular todo acesso novo a `SharedPreferences` atras dessas interfaces;
- parar de adicionar novos usos diretos de `SharedPreferences` em providers e services;
- documentar classificacao oficial de cada setting.

Arquivos foco:

- `lib/core/utils/app_data_directory_resolver.dart`
- `lib/core/di/core_module.dart`
- `lib/presentation/providers/system_settings_provider.dart`
- `lib/core/theme/theme_provider.dart`
- `lib/core/services/temp_directory_service.dart`
- `lib/application/providers/remote_file_transfer_provider.dart`

DoD:

- nenhum provider novo acessa `SharedPreferences` diretamente para dados operacionais;
- classificacao machine/user esta fechada.

**Parcial (2026-03-24):** resolveres explicitos e layout de pastas entregues; contratos `IMachineSettingsRepository` / `IUserPreferencesRepository` e refatoracao de providers **ainda nao** feitas.

## Fase 1 - Unificacao do path base em ProgramData

Objetivo:

- fazer UI e servico enxergarem a mesma base machine-scope.

Entregas:

- alterar o resolver de dados para `ProgramData` como default real em Windows;
- manter nomes de banco por modo:
  - `backup_database.db`
  - `backup_database_client.db`
- mover logs gerais para `ProgramData\BackupDatabase\logs`;
- mover staging e locks para `ProgramData\BackupDatabase`.

Arquivos foco:

- `lib/core/utils/app_data_directory_resolver.dart`
- `lib/core/di/core_module.dart`
- `lib/core/di/infrastructure_module.dart`
- `lib/infrastructure/datasources/local/database.dart`

Risco principal:

- a UI passar a abrir um banco diferente do banco antigo do usuario.

Mitigacao:

- fase 2 precisa incluir migracao automatica e marker de migracao concluida.

**Implementado (2026-03-24):** Windows usa `ProgramData\BackupDatabase` com subpastas `data`, `logs`, `locks`, `staging\backups`, `config`; Drift e logs da app alinhados a esses paths.

## Fase 2 - Migracao de dados existentes `%APPDATA% -> ProgramData`

Objetivo:

- preservar dados existentes sem "sumir" com configuracoes.

Regra recomendada:

- se `ProgramData` ja possui banco valido, ele e a fonte de verdade;
- se `ProgramData` nao possui banco, migrar o banco do usuario atual;
- nao tentar merge automatico de multiplos perfis Windows;
- se forem detectados multiplos bancos por usuario em perfis distintos, registrar aviso e oferecer migracao assistida/admin, nao merge silencioso.

Entregas:

- rotina de bootstrap:
  - detecta banco atual em `%APPDATA%\Backup Database`;
  - copia para `ProgramData\BackupDatabase\data`;
  - valida integridade basica;
  - grava marker de migracao concluida;
- migracao dos logs antigos e opcional; banco e configs sao prioritarios.

Arquivos foco:

- `lib/core/di/core_module.dart`
- `lib/infrastructure/datasources/local/database_migration_224.dart` ou novo migrador dedicado

DoD:

- primeira execucao apos upgrade nao perde configuracoes nem agendamentos;
- migracao e idempotente.

**Implementado (2026-03-24):** copia idempotente do usuario atual (`%APPDATA%\Backup Database\*.db*`) para `ProgramData\...\data\` quando o destino nao tem banco com dados; marker em `config\legacy_appdata_migration.done`. **R1 (2026-03-24):** varredura sob `C:\Users\<perfil>\AppData\Roaming\Backup Database` (ignora `Public`/`Default`/etc.), exclusao do perfil atual, `LoggerService.warning` se existir outro perfil com `.db` nao vazio; **sem merge automatico**. **Diagnostico boot:** `recordMachineStorageBootstrapDiagnostics` + `config\migration_state.json` (paths, marker, backend segredos, lista R1, contagem de ficheiros de logs legados no perfil atual). **Logs legados (2026-03-24):** uma vez por maquina, apos `LoggerService.init`, `migrateLegacyUserLogFilesToMachineScopeIfNeeded()` copia ficheiros (nao recursivo) de `%APPDATA%\Backup Database\logs` para `%ProgramData%\BackupDatabase\logs\legacy_appdata\`; marker `config\legacy_appdata_logs_migration.done`; se copia falhar, marker nao e gravado (repete no proximo arranque); ficheiros com mesmo nome e tamanho ja no destino sao ignorados. **R1 UI (2026-03-24):** `MachineScopeR1LegacyPathsHint` registado no `GetIt`; `R1MultiProfileLegacyHintHost` no `FluentApp.router` builder; dialogo com texto PT/EN e `SelectableText` dos caminhos; dismiss grava assinatura ordenada em `SharedPreferences` (`IUserPreferencesRepository`) — nova detecao (lista alterada) volta a mostrar. **Importacao manual (2026-03-24):** Definicoes gerais — abrir pasta machine storage; importar SQLite de pasta (mesma logica que migracao automatica; nao sobrescreve `.db` destino nao vazio). **Ainda nao:** elevacao UAC / wizard por perfil, merge multi-perfil, validacao SQLite alem de tamanho > 0.

## Fase 3 - Migracao de machine settings

Objetivo:

- tirar configuracoes operacionais do `SharedPreferences`.

Escopo recomendado:

- `start_with_windows`
- `start_minimized`
- `custom_temp_downloads_path`
- `received_backups_default_path`
- `schedule_transfer_destinations`

Entregas:

- criar tabela `machine_settings_table` no Drift;
- migrar leitura/escrita para repositorio dedicado;
- ajustar providers/services consumidores.

Arquivos foco:

- `lib/presentation/providers/system_settings_provider.dart`
- `lib/core/services/temp_directory_service.dart`
- `lib/presentation/boot/app_initializer.dart`
- `lib/application/providers/remote_file_transfer_provider.dart`

Observacao:

- os defaults novos devem permanecer `false` ao popular os primeiros registros machine-scope.

**Implementado (2026-03-24):** tabela + repositorio + consumidores listados no registro acima; bandeja e tema permanecem user-scope em `SharedPreferences` via `IUserPreferencesRepository`. **Startup:** ver Fase 4 (nao usa mais `HKCU\...\Run` para aplicar inicio automatico).

## Fase 4 - Startup machine-scope real

Objetivo:

- alinhar `Iniciar com o Windows` com a ideia de configuracao global.

Analise:

- ~~hoje o app escreve em `HKCU\...\Run`~~ **(legado removido ao aplicar startup)**;
- tarefa agendada com logon cobre todos os utilizadores no PC (cliente/unificado).

Recomendacao:

- para `server mode`, priorizar servico Windows em vez de `Run`;
- para `client mode`, se for realmente necessario "para todos os usuarios", preferir Task Scheduler "At log on of any user";
- evitar `HKLM\...\Run` como primeira opcao, porque exige elevacao e tem menos controle operacional.

Entregas:

- redefinir semantica de `start_with_windows`;
- decidir comportamento por modo:
  - `server`: servico Windows
  - `client`: scheduler global ou manter por usuario se produto aceitar

Arquivos foco:

- `lib/presentation/providers/system_settings_provider.dart`
- `lib/infrastructure/external/system/windows_service_service.dart`

Ponto de decisao:

- esta flag sera realmente global para todos os modos, ou apenas para o modo servidor?

**Implementado (2026-03-24):** `IWindowsMachineStartupService` + `WindowsMachineStartupService` (schtasks/XML); cliente e unificado instalam `BackupDatabase\MachineStartup`; servidor apenas limpa legado e persiste preferencia (autostart = servico); textos na aba Geral.

## Fase 5 - Migracao do secure storage para machine-scope

Objetivo:

- tornar segredos operacionais acessiveis de forma consistente entre usuarios/processos autorizados da mesma maquina.

Escopo:

- senhas de banco;
- segredos SMTP;
- tokens OAuth;
- credenciais do servidor.

Entregas:

- introduzir nova implementacao de `ISecureCredentialService`;
- criar migrador que:
  - tenta ler do storage antigo;
  - regrava em storage machine-scope;
  - remove ou invalida material legado quando seguro;
- manter chaves logicas existentes para reduzir impacto nos repositrios.

Arquivos foco:

- `lib/infrastructure/security/machine_scope_secure_credential_service.dart`
- `lib/core/di/core_module.dart`
- `lib/infrastructure/repositories/sql_server_config_repository.dart`
- `lib/infrastructure/repositories/sybase_config_repository.dart`
- `lib/infrastructure/repositories/postgres_config_repository.dart`
- `lib/infrastructure/repositories/email_config_repository.dart`
- `lib/infrastructure/external/google/google_auth_service.dart`
- `lib/infrastructure/external/dropbox/dropbox_auth_service.dart`
- `lib/infrastructure/external/email/oauth_smtp_service.dart`

Risco principal:

- tokens e segredos antigos deixarem de ser legiveis apos a troca de backend.

Mitigacao:

- migracao lazy por chave, no primeiro acesso;
- logs claros de migracao;
- fallback controlado apenas durante janela de transicao.

**Implementado (2026-03-24):** `MachineScopeSecureCredentialService` com DPAPI `LOCAL_MACHINE` e ficheiros em `secrets\`; migracao lazy em leituras; fora do Windows mantem `FlutterSecureStorage`; interface `ISecureCredentialService` e consumidores inalterados.

## Fase 6 - Limpeza de legado e endurecimento

Objetivo:

- remover dependencias antigas por usuario e fechar a arquitetura.

Entregas:

- remover usos restantes de `SharedPreferences` para dados operacionais;
- manter `SharedPreferences` apenas para `IUserPreferencesRepository`, se essa decisao for confirmada;
- remover paths legados baseados em `%APPDATA%` do fluxo principal;
- adicionar diagnostico explicito no boot indicando:
  - path machine-scope em uso;
  - status da migracao;
  - backend de segredos em uso.

**Parcialmente implementado (2026-03-24):**

- `ensureLegacyAppDataMigratedToMachineScope()` passa a devolver `MachineLegacyMigrationSummary` (paths, marker, se copiou SQLite nesta execucao).
- Apos `LoggerService.init`, `setupCoreModule` chama `findLegacyBackupDatabasePathsOutsideCurrentUser()`, `countLegacyLogFilesVisibleForCurrentUser()` e `recordMachineStorageBootstrapDiagnostics()` (`machine_storage_bootstrap_diagnostics.dart`): logs INFO/WARNING e escrita de `config\migration_state.json` (`MachineStorageLayout.migrationStateFile`).
- R1: aviso em log quando outro perfil Windows tem dados legados detectaveis (acesso a outras pastas de utilizador pode falhar sem permissoes elevadas).
- Migracao one-shot de ficheiros de log do perfil atual: `logs\legacy_appdata\` sob machine root + marker `legacy_appdata_logs_migration.done` (sem apagar originais em `%APPDATA%`).
- Dialogo R1 no primeiro frame da UI quando existem outros perfis com SQLite legado: `r1_multi_profile_legacy_hint_host.dart` + preferencias `getR1MultiProfileLegacyHintLastDismissedSignature` / `set...`.
- **Definicoes gerais (2026-03-24):** widget `MachineStorageSettingsSection` — `ComboBox` + refresh + **Pesquisar como administrador** (UAC) + import por perfil / por pasta; validacao SQLite no import; ultima pesquisa; Semantics.
- **Migracao automatica SQLite (2026-03-24):** `migrateSqliteDatabaseBundleIfNeeded` alinhado ao import (cabecalho + `quick_check`); `LegacySqliteFolderImportService` evita segundo `quick_check` na copia.

## Plano de Implementacao por Arquivo

### Core e bootstrap

- `lib/core/utils/app_data_directory_resolver.dart`
  - substituir resolver ambiguo por API explicita de escopo;
- `lib/core/di/core_module.dart`
  - inicializar logs e banco com `ProgramData`;
  - registrar novos repositorios/stores;
- `lib/core/di/infrastructure_module.dart`
  - usar paths machine-scope para staging e locks;
- `lib/core/di/service_locator.dart`
  - manter UI e servico convergindo na mesma infraestrutura base.

### Persistencia e banco

- `lib/infrastructure/datasources/local/database.dart`
  - apontar definitivamente para path machine-scope;
- `lib/infrastructure/datasources/local/tables/*`
  - adicionar `machine_settings_table`;
- `lib/infrastructure/datasources/daos/*`
  - criar `machine_settings_dao`;
- `lib/infrastructure/repositories/*`
  - criar repositorio de machine settings.

### Providers e services consumidores

- `lib/presentation/providers/system_settings_provider.dart`
  - remover `SharedPreferences` direto;
  - depender de repositrio machine-scope;
- `lib/core/services/temp_directory_service.dart`
  - ler caminho customizado do store machine-scope;
- `lib/presentation/boot/app_initializer.dart`
  - ler `start_minimized` do store correto;
- `lib/application/providers/remote_file_transfer_provider.dart`
  - migrar defaults/path/destinations vinculados;
- `lib/core/theme/theme_provider.dart`
  - manter user-scope ou migrar conforme decisao de produto.

### Segredos e tokens

- `lib/infrastructure/security/machine_scope_secure_credential_service.dart`
  - implementacao machine-scope (Windows) + migracao lazy;
- `lib/infrastructure/repositories/sql_server_config_repository.dart`
- `lib/infrastructure/repositories/sybase_config_repository.dart`
- `lib/infrastructure/repositories/postgres_config_repository.dart`
- `lib/infrastructure/repositories/email_config_repository.dart`
- `lib/infrastructure/external/google/google_auth_service.dart`
- `lib/infrastructure/external/dropbox/dropbox_auth_service.dart`
- `lib/infrastructure/external/email/oauth_smtp_service.dart`
  - todos precisam ser validados contra o novo backend de segredos.

## Estrategia de Migracao de Dados

### Ordem recomendada

1. criar infraestrutura de escopo e stores novos;
2. migrar path base para `ProgramData`;
3. migrar banco do usuario atual para `ProgramData` na primeira execucao;
4. migrar `machine settings`;
5. migrar segredos;
6. remover legado.

### Regras de precedencia

- `ProgramData` sempre vence se ja existir e estiver marcado como migrado;
- `%APPDATA%` do usuario atual so e usado como origem de migracao, nunca como destino final apos a cutover;
- nao mesclar silenciosamente bancos de usuarios diferentes.

### Marker de migracao

Criar marker machine-scope, por exemplo:

- `C:\ProgramData\BackupDatabase\config\migration_state.json`

Campos recomendados:

- `storageScopeVersion`
- `appDataMigrated`
- `machineSettingsMigrated`
- `secureStoreMigrated`
- `sourceUser`
- `migratedAt`

## Riscos e Pontos de Atencao

### R1. Colisao entre perfis antigos

Se a mesma maquina tiver varios perfis Windows usando bancos diferentes em `%APPDATA%`, a migracao automatica nao pode escolher e mesclar silenciosamente.

Acao:

- migrar apenas a origem detectada na primeira execucao privilegiada;
- gerar log/aviso se outros candidatos forem encontrados.

### R2. Tokens OAuth e segredos antigos

O backend novo de segredos pode invalidar leitura do material salvo hoje.

Acao:

- migracao lazy por chave;
- fallback temporario de leitura do backend antigo;
- write-through para o backend novo.

### R3. Startup global

`HKCU\Run` nao resolve o objetivo de "todos os usuarios".

Acao:

- fechar decisao de produto antes da implementacao;
- preferir Task Scheduler ou servico Windows, dependendo do modo.

### R4. Preferencias de UX realmente globais

Tema e comportamento de bandeja podem se tornar irritantes se um usuario mudar o ambiente de outro.

Acao:

- validar se a exigencia de globalizacao inclui UX ou apenas operacao.

## Testes Necessarios

### Unitarios

- novo teste do resolver de diretorio:
  - `%ProgramData%` como fonte principal em Windows;
- novos testes do repositorio machine-scope;
- testes do `SystemSettingsProvider` usando o novo repositorio;
- testes do `TempDirectoryService` com store machine-scope;
- testes do migrador de dados;
- testes do novo secure credential service.

### Integracao

- UI e servico abrindo o mesmo banco em `ProgramData`;
- migracao de banco do `%APPDATA%` do usuario atual para `ProgramData`;
- leitura de configuracao machine-scope por usuarios diferentes;
- comportamento de startup conforme modo;
- leitura de segredos apos migracao.

### Regressao

- `flutter analyze`
- testes atuais de:
  - `system_settings_provider_test.dart`
  - `single_instance_checker_test.dart`
  - `service_mode_detector_test.dart`
  - integracoes de socket/file transfer

## Checklist de Pronto

- [x] Banco principal em `ProgramData` (`...\BackupDatabase\data\*.db`, Windows)
- [x] Logs gerais em `ProgramData` (`...\BackupDatabase\logs`, Windows)
- [x] Staging e locks em `ProgramData` (`staging\backups`, `locks`)
- [x] `SystemSettingsProvider` sem `SharedPreferences` direto (usa repositorios)
- [x] `TempDirectoryService` sem `SharedPreferences` direto para machine-scope
- [x] `AppInitializer` lendo `start_minimized` via `IMachineSettingsRepository`
- [x] `RemoteFileTransferProvider` sem preferencias operacionais em `SharedPreferences` (usa `IMachineSettingsRepository`)
- [x] Segredos migrados para backend machine-scope (Windows: DPAPI local machine + `secrets\`; migracao lazy desde `FlutterSecureStorage`)
- [x] Politica de implementacao atual (produto pode revisar):
  - [x] `dark_mode` — user-scope (`IUserPreferencesRepository` / `SharedPreferences`)
  - [x] `minimize_to_tray` / `close_to_tray` — user-scope (mesmo)
  - [x] `start_with_windows` — valor no Drift; cliente/unificado = tarefa `BackupDatabase\MachineStartup` (logon); servidor = sem tarefa (servico Windows)
- [x] Rotina de migracao idempotente (SQLite legado -> `data\`, marker em `config\`)
- [x] Nenhum fluxo operacional depende de `%APPDATA%` no caminho principal (banco, logs, staging, locks, segredos no Windows; `SharedPreferences` apenas user prefs)

## Sequencia de PRs Recomendada

- [x] PR-1: fundacao de escopo + resolveres + repositorios de settings (entregue 2026-03-24 com PR-2/3 acoplados no codigo)
- [x] PR-2: unificacao de banco/logs/staging em `ProgramData` (entregue 2026-03-24)
- [x] PR-3: migracao de machine settings e boot (Drift + `AppInitializer`; startup HKLM/scheduler — Fase 4)
- [x] PR-4: startup global e revisao de semantica por modo (Task Scheduler + modo servidor via servico)
- [x] PR-5: secure storage machine-scope + migracao de segredos (lazy read + DPAPI)
- [x] PR-6: diagnostico + `migration_state.json` + R1 + logs + import SQLite em UI + pesquisa UAC + validacao SQLite + `MachineStorageSettingsSection`

## Backlog Tecnico

### Visao geral do backlog

- `PR-1`: fundacao de escopo e contratos de persistencia
- `PR-2`: cutover de paths machine-scope para banco, logs, staging e locks
- `PR-3`: migracao de machine settings e ajuste do boot
- `PR-4`: semantica de startup global por modo
- `PR-5`: secure storage machine-scope e migracao de segredos
- `PR-6`: remocao de legado, diagnostico e endurecimento operacional

### PR-1 - Fundacao de escopo e contratos

Objetivo:

- preparar a arquitetura para a migracao sem ainda mudar o banco principal nem o backend de segredos;
- separar formalmente `machine-scope` de `user-scope`;
- remover acoplamento direto dos providers principais com `SharedPreferences`.

Escopo funcional:

- criar resolveres explicitos de path por escopo;
- introduzir contratos de persistencia para configuracoes da maquina e preferencias do usuario;
- adaptar `SystemSettingsProvider` e `ThemeProvider` para depender desses contratos;
- manter comportamento atual de negocio, exceto pelos defaults ja alterados para `false`.

Fora de escopo do PR-1:

- mover banco para `ProgramData`;
- migrar dados do `%APPDATA%`;
- trocar `FlutterSecureStorage`;
- redefinir `start_with_windows` para todos os usuarios.

#### Entregas tecnicas do PR-1

- [x] Criar API de diretorios por escopo em `core/utils` (inclui `machine_storage_layout.dart`; ver registro de implementacao)
- [x] Criar contrato `IMachineSettingsRepository`
- [x] Criar contrato `IUserPreferencesRepository`
- [x] Implementacao: machine em Drift (`MachineSettingsRepository`); user prefs em `SharedPreferences` (`UserPreferencesRepository`)
- [x] Mover `SystemSettingsProvider` para repositorios (machine + user)
- [x] Mover `ThemeProvider` para `IUserPreferencesRepository` (arquivo em `presentation/providers/theme_provider.dart`)
- [x] Mover `TempDirectoryService` para `IMachineSettingsRepository`
- [x] Atualizar DI (`domain_module` para repos + `TempDirectoryService`; `core_module` sem `TempDirectoryService`)
- [x] Cobrir repositorios Drift com testes unitarios dedicados (`MachineSettingsRepository`; fakes continuam em provider/temp tests)

#### Checklist por arquivo - PR-1

##### 1. Resolver de diretorios

- [x] [app_data_directory_resolver.dart](d:/Developer/Flutter/backup_database/lib/core/utils/app_data_directory_resolver.dart)
  - `resolveMachineDataDirectory()`, `resolveMachineRootDirectory()`, staging e locks implementados
  - `resolveLegacyWindowsUserAppDataDirectory()` para migracao
  - `resolveAppDataDirectory()` -> alias de machine root (compatibilidade)
  - path user-scope para preferencias: continua `SharedPreferences` ate existir `IUserPreferencesRepository`

##### 2. Contratos de repositorio

- [x] [i_machine_settings_repository.dart](d:/Developer/Flutter/backup_database/lib/domain/repositories/i_machine_settings_repository.dart) — escopo machine (sem bandeja; bandeja ficou em user)
- [x] [i_user_preferences_repository.dart](d:/Developer/Flutter/backup_database/lib/domain/repositories/i_user_preferences_repository.dart) — bandeja + `darkMode`

##### 3. Implementacoes iniciais de persistencia

- [x] [machine_settings_repository.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/repositories/machine_settings_repository.dart) — Drift + seed unico a partir de `SharedPreferences` legado
- [x] [user_preferences_repository.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/repositories/user_preferences_repository.dart) — `SharedPreferences`

##### 4. Atualizacao dos providers/services consumidores

- [x] [system_settings_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/system_settings_provider.dart)
- [x] [theme_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/theme_provider.dart)
- [x] [temp_directory_service.dart](d:/Developer/Flutter/backup_database/lib/core/services/temp_directory_service.dart)
- [x] [remote_file_transfer_provider.dart](d:/Developer/Flutter/backup_database/lib/application/providers/remote_file_transfer_provider.dart)

##### 5. Dependency Injection

- [x] [domain_module.dart](d:/Developer/Flutter/backup_database/lib/core/di/domain_module.dart) — `IMachineSettingsRepository`, `IUserPreferencesRepository`, `TempDirectoryService`
- [x] [core_module.dart](d:/Developer/Flutter/backup_database/lib/core/di/core_module.dart) — `TempDirectoryService` removido daqui
- [x] [app_widget.dart](d:/Developer/Flutter/backup_database/lib/presentation/app_widget.dart)
- [x] [app_initializer.dart](d:/Developer/Flutter/backup_database/lib/presentation/boot/app_initializer.dart) — `getLaunchConfig` + `IMachineSettingsRepository`

##### 6. Arquivos que nao devem ser alterados no PR-1 (planejamento original)

- [x] [database.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/datasources/local/database.dart) — **alterado em 2026-03-24** como parte do cutover PR-2 (path machine-scope)
- [x] [service_locator.dart](d:/Developer/Flutter/backup_database/lib/core/di/service_locator.dart) — mantido como entrada `setupDependencies()` sem mudancas especificas deste plano (DI continua a orquestrar modulos; nao era alvo do cutover PR-1)
- [x] [machine_scope_secure_credential_service.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/security/machine_scope_secure_credential_service.dart) — Fase 5

Justificativa (original):

- manter o PR-1 pequeno e focado em contratos;
- evitar misturar fundacao de arquitetura com cutover de dados e segredos.

**Nota 2026-03-24:** PR-2 foi antecipado junto dos resolveres; `database.dart`, `core_module.dart`, `infrastructure_module.dart` e `database_migration_224.dart` ja refletem `ProgramData`.

#### Testes a implementar no PR-1

##### Unitarios novos

- [x] Criar [machine_settings_repository_test.dart](d:/Developer/Flutter/backup_database/test/unit/infrastructure/repositories/machine_settings_repository_test.dart)
  - deve ler defaults esperados
  - deve salvar e reler flags booleanas
  - deve persistir `customTempDownloadsPath`
  - deve persistir `scheduleTransferDestinations`
- [x] Criar [user_preferences_repository_test.dart](d:/Developer/Flutter/backup_database/test/unit/infrastructure/repositories/user_preferences_repository_test.dart)
  - deve ler `darkMode`
  - deve salvar `darkMode`
- [x] Criar [app_data_directory_resolver_test.dart](d:/Developer/Flutter/backup_database/test/unit/core/utils/app_data_directory_resolver_test.dart)
  - deve retornar `ProgramData` para `resolveMachineDataDirectory()`
  - deve cobrir fallback seguro quando variavel de ambiente nao existir

##### Unitarios a atualizar

- [x] Atualizar [system_settings_provider_test.dart](d:/Developer/Flutter/backup_database/test/unit/presentation/providers/system_settings_provider_test.dart)
  - provider sem `SharedPreferences` direto; fakes de machine startup e `IMachineSettingsRepository`; `UserPreferencesRepository` com mock prefs onde aplicavel
- [x] Criar [theme_provider_test.dart](d:/Developer/Flutter/backup_database/test/unit/presentation/providers/theme_provider_test.dart)
  - `darkMode` via fake `IUserPreferencesRepository`; init idempotente; `setDarkMode` / `toggleTheme`
- [x] Atualizar [temp_directory_service_test.dart](d:/Developer/Flutter/backup_database/test/unit/core/services/temp_directory_service_test.dart)
  - path customizado via fake `IMachineSettingsRepository`; caso ficheiro em vez de pasta limpa configuracao; `validateDownloadsDirectory`

##### Regressao obrigatoria

- [x] `flutter analyze`
- [x] `flutter test test/unit/presentation/providers/system_settings_provider_test.dart`
- [x] `flutter test test/unit/presentation/providers/theme_provider_test.dart`
- [x] `flutter test test/unit/core/services/temp_directory_service_test.dart`
- [x] `flutter test test/unit/core/utils/app_data_directory_resolver_test.dart`
- [x] `flutter test test/unit/infrastructure/repositories/machine_settings_repository_test.dart`
- [x] `flutter test test/unit/infrastructure/repositories/user_preferences_repository_test.dart`

#### Criterios de aceite do PR-1

- [x] Nao existe mais acesso direto a `SharedPreferences` em:
  - [x] [system_settings_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/system_settings_provider.dart)
  - [x] [theme_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/theme_provider.dart)
  - [x] [temp_directory_service.dart](d:/Developer/Flutter/backup_database/lib/core/services/temp_directory_service.dart)
- [x] Os contratos `IMachineSettingsRepository` e `IUserPreferencesRepository` estao registrados no DI
- [x] Os defaults atuais continuam corretos (ver testes de providers/repos)
- [x] O PR nao altera o caminho do banco nem a semantica do secure storage (entregue em PRs posteriores do mesmo plano)
- [x] O comportamento da UI nao muda alem da troca interna de persistencia encapsulada

#### Sequencia de implementacao sugerida para PR-1

1. Criar contratos de repositorio no `domain`
2. Criar implementacoes com `SharedPreferences` no `infrastructure`
3. Ajustar DI no `core_module.dart`
4. Migrar `ThemeProvider`
5. Migrar `SystemSettingsProvider`
6. Migrar `TempDirectoryService`
7. Migrar `RemoteFileTransferProvider`, se incluido
8. Criar/ajustar testes
9. Rodar analise e regressao

#### Riscos especificos do PR-1

- risco baixo de regressao funcional;
- risco medio de quebrar testes existentes por mudanca de construtor/injecao;
- risco baixo de comportamento divergente se alguma chave antiga for renomeada sem adaptador.

Mitigacoes:

- manter nomes das chaves atuais neste PR;
- usar fakes simples para os novos repositorios nos testes de provider;
- nao mover banco nem paths reais ainda.

### Backlog resumido dos PRs seguintes

#### PR-2 - Cutover de path machine-scope

- [x] aplicar `resolveMachineDataDirectory()` em banco, logs, staging e locks (ver registro **Entregue** e `core_module` / `infrastructure_module` / `database.dart`)
- [x] unificar UI e servico no mesmo path base (`setupCoreModule` partilhado; paths machine-scope)
- [x] preparar marker de migracao (`legacy_appdata_migration.done`, `migration_state.json`, migracao idempotente SQLite)

#### PR-3 - Migracao de machine settings

- [x] tirar machine settings de `SharedPreferences` (chaves machine-scope removidas no seed do `MachineSettingsRepository`)
- [x] criar persistencia definitiva em banco ou arquivo machine-scope (`machine_settings_table` Drift)
- [x] migrar `AppInitializer` e `RemoteFileTransferProvider` (via `IMachineSettingsRepository`; ver registro **Entregue**)

#### PR-4 - Startup global

- [x] fechar regra de `start_with_windows` por modo
- [x] trocar `HKCU\Run` por estrategia compativel com machine-scope (tarefa agendada + limpeza de legado)

#### PR-5 - Secure storage machine-scope

- [x] substituir backend de segredos (Windows)
- [x] migrar tokens e senhas existentes (lazy no primeiro read)

#### PR-6 - Limpeza e endurecimento

- [x] fluxo principal sem dependencia de `%APPDATA%` para dados operacionais (Windows); legado só como origem de migracao / deteccao
- [x] diagnostico no boot + `config\migration_state.json` + scan R1 e avisos em log
- [x] migracao one-shot de logs do perfil atual para `logs\legacy_appdata\` (marker dedicado)
- [x] aviso assistido R1 no arranque (dialogo + dismiss por assinatura)
- [x] importacao `.db` de pasta escolhida na UI (Definicoes gerais; sem elevacao)
- [x] importacao a partir de **perfil Windows detetado** na UI (`ComboBox` + refresh; sem escolher pasta manualmente para esses caminhos)
- [x] pesquisa de perfis com **UAC** (`legacy_profile_scanner.exe` + `ShellExecuteEx`/`runas`, fallback PowerShell; merge de caminhos; JSON temporario)
- [x] validacao SQLite (cabecalho + quick_check) e mensagens de copia / ficheiro em uso

## Recomendacao Final

A migracao deve ser tratada como mudanca arquitetural, nao apenas como troca de pasta.

Se a equipe tentar apenas:

- trocar `%APPDATA%` por `ProgramData`; e
- mover alguns `SharedPreferences`;

o projeto continuara inconsistente porque:

- segredos ainda ficarao atrelados ao usuario;
- `start_with_windows` ficaria semanticamente por usuario (mitigado na Fase 4 com tarefa de logon + modo servidor);
- parte da UX e parte da operacao continuarao misturadas.

O caminho mais seguro e:

- unificar o storage operacional em machine-scope;
- manter user-scope apenas para UX, se o produto permitir;
- migrar segredos com backend proprio machine-scope;
- fazer a cutover com migracao idempotente e testada.
