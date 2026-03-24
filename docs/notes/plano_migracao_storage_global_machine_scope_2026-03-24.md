# Plano: Migracao de Storage por Usuario para Storage Global da Maquina

Data base: 2026-03-24
Status: Planejado
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

### 10. Senhas e tokens dependem de `FlutterSecureStorage`

Evidencias:

- `lib/infrastructure/security/secure_credential_service.dart:10`
- `lib/infrastructure/security/secure_credential_service.dart:12`
- `lib/infrastructure/security/secure_credential_service.dart:18`
- `lib/infrastructure/security/secure_credential_service.dart:37`
- `lib/infrastructure/security/secure_credential_service.dart:80`
- `lib/infrastructure/security/secure_credential_service.dart:100`

Analise:

- SQL Server, Sybase, PostgreSQL, SMTP, Google OAuth e Dropbox OAuth usam esse service;
- no Windows, esse tipo de storage costuma seguir o usuario/perfil e/ou o contexto do processo;
- isso e um bloqueio forte para um modelo realmente global.

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

- `lib/infrastructure/security/secure_credential_service.dart`
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

## Fase 4 - Startup machine-scope real

Objetivo:

- alinhar `Iniciar com o Windows` com a ideia de configuracao global.

Analise:

- hoje o app escreve em `HKCU\...\Run`;
- isso nao e machine-scope.

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

- `lib/infrastructure/security/secure_credential_service.dart`
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

- `lib/infrastructure/security/secure_credential_service.dart`
  - trocar implementacao;
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

- [ ] Banco principal em `ProgramData`
- [ ] Logs gerais em `ProgramData`
- [ ] Staging e locks em `ProgramData`
- [ ] `SystemSettingsProvider` sem `SharedPreferences` direto
- [ ] `TempDirectoryService` sem `SharedPreferences` direto para machine-scope
- [ ] `AppInitializer` lendo startup do store correto
- [ ] `RemoteFileTransferProvider` sem preferencias operacionais em `SharedPreferences`
- [ ] Segredos migrados para backend machine-scope
- [ ] Politica oficial definida para:
  - [ ] `dark_mode`
  - [ ] `minimize_to_tray`
  - [ ] `close_to_tray`
  - [ ] `start_with_windows` em modo cliente
- [ ] Rotina de migracao idempotente
- [ ] Nenhum fluxo operacional depende de `%APPDATA%` no caminho principal

## Sequencia de PRs Recomendada

- [ ] PR-1: fundacao de escopo + resolveres + repositorios de settings
- [ ] PR-2: unificacao de banco/logs/staging em `ProgramData`
- [ ] PR-3: migracao de machine settings e boot
- [ ] PR-4: startup global e revisao de semantica por modo
- [ ] PR-5: secure storage machine-scope + migracao de segredos
- [ ] PR-6: limpeza de legado + telemetria/diagnostico de migracao

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

- [ ] Criar API de diretorios por escopo em `core/utils`
- [ ] Criar contrato `IMachineSettingsRepository`
- [ ] Criar contrato `IUserPreferencesRepository`
- [ ] Criar implementacao inicial baseada em `SharedPreferences` para ambos os contratos
- [ ] Mover `SystemSettingsProvider` para `IMachineSettingsRepository`
- [ ] Mover `ThemeProvider` para `IUserPreferencesRepository`
- [ ] Mover `TempDirectoryService` para `IMachineSettingsRepository`
- [ ] Atualizar DI no `core_module.dart`
- [ ] Cobrir os contratos e providers com testes unitarios

#### Checklist por arquivo - PR-1

##### 1. Resolver de diretorios

- [ ] [app_data_directory_resolver.dart](d:/Developer/Flutter/backup_database/lib/core/utils/app_data_directory_resolver.dart)
  - adicionar funcao explicita `resolveMachineDataDirectory()`
  - adicionar funcao explicita para path user-scope, se necessario
  - manter compatibilidade temporaria de `resolveAppDataDirectory()` apenas como adaptador, ou marcar para remocao posterior
  - evitar ambiguidade entre `%APPDATA%` e `ProgramData`

##### 2. Contratos de repositorio

- [ ] Criar [i_machine_settings_repository.dart](d:/Developer/Flutter/backup_database/lib/domain/repositories/i_machine_settings_repository.dart)
  - expor leitura/escrita de:
    - `startWithWindows`
    - `startMinimized`
    - `minimizeToTray`
    - `closeToTray`
    - `customTempDownloadsPath`
    - `receivedBackupsDefaultPath`
    - `scheduleTransferDestinations`
- [ ] Criar [i_user_preferences_repository.dart](d:/Developer/Flutter/backup_database/lib/domain/repositories/i_user_preferences_repository.dart)
  - expor leitura/escrita de:
    - `darkMode`

##### 3. Implementacoes iniciais de persistencia

- [ ] Criar [machine_settings_repository.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/repositories/machine_settings_repository.dart)
  - implementacao inicial com `SharedPreferences`
  - manter nomes de chave atuais para reduzir risco neste PR
  - encapsular parsing de mapa/lista para `scheduleTransferDestinations`
- [ ] Criar [user_preferences_repository.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/repositories/user_preferences_repository.dart)
  - implementacao inicial com `SharedPreferences`
  - centralizar `dark_mode`

##### 4. Atualizacao dos providers/services consumidores

- [ ] [system_settings_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/system_settings_provider.dart)
  - remover acesso direto a `SharedPreferences`
  - passar a depender de `IMachineSettingsRepository`
  - manter logica de `_updateStartWithWindows()`
  - manter defaults `false`
- [ ] [theme_provider.dart](d:/Developer/Flutter/backup_database/lib/core/theme/theme_provider.dart)
  - remover acesso direto a `SharedPreferences`
  - passar a depender de `IUserPreferencesRepository`
- [ ] [temp_directory_service.dart](d:/Developer/Flutter/backup_database/lib/core/services/temp_directory_service.dart)
  - remover acesso direto a `SharedPreferences`
  - passar a depender de `IMachineSettingsRepository`
- [ ] [remote_file_transfer_provider.dart](d:/Developer/Flutter/backup_database/lib/application/providers/remote_file_transfer_provider.dart)
  - opcao A: manter fora do PR-1
  - opcao B recomendada: trocar `SharedPreferences` por `IMachineSettingsRepository` ja neste PR para evitar duplicacao de caminho

##### 5. Dependency Injection

- [ ] [core_module.dart](d:/Developer/Flutter/backup_database/lib/core/di/core_module.dart)
  - registrar `IMachineSettingsRepository`
  - registrar `IUserPreferencesRepository`
  - ajustar construcao de `TempDirectoryService`
- [ ] [app_widget.dart](d:/Developer/Flutter/backup_database/lib/presentation/app_widget.dart)
  - ajustar criacao de `ThemeProvider`
  - ajustar criacao de `SystemSettingsProvider`

##### 6. Arquivos que nao devem ser alterados no PR-1

- [ ] [database.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/datasources/local/database.dart)
- [ ] [service_locator.dart](d:/Developer/Flutter/backup_database/lib/core/di/service_locator.dart)
- [ ] [secure_credential_service.dart](d:/Developer/Flutter/backup_database/lib/infrastructure/security/secure_credential_service.dart)

Justificativa:

- manter o PR-1 pequeno e focado em contratos;
- evitar misturar fundacao de arquitetura com cutover de dados e segredos.

#### Testes a implementar no PR-1

##### Unitarios novos

- [ ] Criar [machine_settings_repository_test.dart](d:/Developer/Flutter/backup_database/test/unit/infrastructure/repositories/machine_settings_repository_test.dart)
  - deve ler defaults esperados
  - deve salvar e reler flags booleanas
  - deve persistir `customTempDownloadsPath`
  - deve persistir `scheduleTransferDestinations`
- [ ] Criar [user_preferences_repository_test.dart](d:/Developer/Flutter/backup_database/test/unit/infrastructure/repositories/user_preferences_repository_test.dart)
  - deve ler `darkMode`
  - deve salvar `darkMode`
- [ ] Criar [app_data_directory_resolver_test.dart](d:/Developer/Flutter/backup_database/test/unit/core/utils/app_data_directory_resolver_test.dart)
  - deve retornar `ProgramData` para `resolveMachineDataDirectory()`
  - deve cobrir fallback seguro quando variavel de ambiente nao existir

##### Unitarios a atualizar

- [ ] Atualizar [system_settings_provider_test.dart](d:/Developer/Flutter/backup_database/test/unit/presentation/providers/system_settings_provider_test.dart)
  - remover dependencia implita de `SharedPreferences` direto no provider
  - validar defaults `false`
  - validar escrita de startup usando repositorio mock/fake
- [ ] Criar ou atualizar teste do `ThemeProvider`
  - validar que `darkMode` carrega via `IUserPreferencesRepository`
- [ ] Criar ou atualizar teste do `TempDirectoryService`
  - validar leitura/escrita do path customizado via `IMachineSettingsRepository`

##### Regressao obrigatoria

- [ ] `flutter analyze`
- [ ] `flutter test test/unit/presentation/providers/system_settings_provider_test.dart`
- [ ] `flutter test test/unit/core/utils/app_data_directory_resolver_test.dart`
- [ ] `flutter test test/unit/infrastructure/repositories/machine_settings_repository_test.dart`
- [ ] `flutter test test/unit/infrastructure/repositories/user_preferences_repository_test.dart`

#### Criterios de aceite do PR-1

- [ ] Nao existe mais acesso direto a `SharedPreferences` em:
  - [ ] [system_settings_provider.dart](d:/Developer/Flutter/backup_database/lib/presentation/providers/system_settings_provider.dart)
  - [ ] [theme_provider.dart](d:/Developer/Flutter/backup_database/lib/core/theme/theme_provider.dart)
  - [ ] [temp_directory_service.dart](d:/Developer/Flutter/backup_database/lib/core/services/temp_directory_service.dart)
- [ ] Os contratos `IMachineSettingsRepository` e `IUserPreferencesRepository` estao registrados no DI
- [ ] Os defaults atuais continuam corretos
- [ ] O PR nao altera o caminho do banco nem a semantica do secure storage
- [ ] O comportamento da UI nao muda alem da troca interna de persistencia encapsulada

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

- [ ] aplicar `resolveMachineDataDirectory()` em banco, logs, staging e locks
- [ ] unificar UI e servico no mesmo path base
- [ ] preparar marker de migracao

#### PR-3 - Migracao de machine settings

- [ ] tirar machine settings de `SharedPreferences`
- [ ] criar persistencia definitiva em banco ou arquivo machine-scope
- [ ] migrar `AppInitializer` e `RemoteFileTransferProvider`

#### PR-4 - Startup global

- [ ] fechar regra de `start_with_windows` por modo
- [ ] trocar `HKCU\Run` por estrategia compativel com machine-scope

#### PR-5 - Secure storage machine-scope

- [ ] substituir backend de segredos
- [ ] migrar tokens e senhas existentes

#### PR-6 - Limpeza e endurecimento

- [ ] remover legado `%APPDATA%`
- [ ] adicionar diagnostico e marcadores de migracao
- [ ] fechar checklist final de pronto

## Recomendacao Final

A migracao deve ser tratada como mudanca arquitetural, nao apenas como troca de pasta.

Se a equipe tentar apenas:

- trocar `%APPDATA%` por `ProgramData`; e
- mover alguns `SharedPreferences`;

o projeto continuara inconsistente porque:

- segredos ainda ficarao atrelados ao usuario;
- `start_with_windows` continuara semanticamente por usuario;
- parte da UX e parte da operacao continuarao misturadas.

O caminho mais seguro e:

- unificar o storage operacional em machine-scope;
- manter user-scope apenas para UX, se o produto permitir;
- migrar segredos com backend proprio machine-scope;
- fazer a cutover com migracao idempotente e testada.
