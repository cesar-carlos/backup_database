# Análise: estrutura de erros e supressão em try-catch

## Estrutura de erros do projeto

### 1. `result_dart` (Result pattern)

- Uso: operações que podem falhar retornam `Result<T>` (`Success(T)` ou `Failure`).
- Camadas: **Domain** (use cases), **Infrastructure** (repositories, external services) e **Application** (services) retornam `Result` quando a operação pode falhar.
- Import: `import 'package:result_dart/result_dart.dart' as rd;`

### 2. Hierarquia de falhas (`lib/core/errors/`)

- **`Failure`** (abstract, implements `Exception`): `message`, `code?`, `originalError?`.
- Subtipos: `ServerFailure`, `DatabaseFailure`, `NetworkFailure`, `ValidationFailure`, `BackupFailure`, `FileSystemFailure`, `FtpFailure`, `GoogleDriveFailure`, `NotFoundFailure`, `DropboxFailure` (dropbox_failure.dart), `NextcloudFailure` (nextcloud_failure.dart).
- **`Exceptions`** (exceptions.dart): `ServerException`, `DatabaseException`, etc. — usadas onde se lança exceção; podem ser convertidas em `Failure` no catch.

### 3. LoggerService

O projeto possui um serviço de logging centralizado (`lib/core/utils/logger_service.dart`) que fornece métodos para registrar diferentes níveis de log:

- `LoggerService.debug()`: Mensagens de debug (desenvolvimento)
- `LoggerService.info()`: Mensagens informativas
- `LoggerService.warning()`: Alertas que não impedem a execução
- `LoggerService.error()`: Erros com exceção e stack trace

**Uso recomendado em catch blocks:**

```dart
} on Object catch (e, s) {
  LoggerService.error('Descrição do erro', e, s);
  return rd.Failure(AlgumFailure(message: '...', originalError: e));
}
```

### 4. Padrão esperado

- Em métodos que retornam `Future<Result<T>>`: em `catch`, converter a exceção em `Failure` e retornar `rd.Failure(AlgumFailure(message: '...', originalError: e))`.
- Sempre usar `LoggerService.error()` em catch blocks para registrar o erro.
- Nunca usar catch vazio sem pelo menos logar o erro.
- Não engolir exceção: nem catch vazio nem só log sem retornar `Failure` (ou repassar o erro de outra forma).

---

## Pontos que suprimem erro

### A. Catch vazio `} on Object catch (_) {}`

| Arquivo                                                                          | Contexto                                              |
| -------------------------------------------------------------------------------- | ----------------------------------------------------- |
| `lib/infrastructure/external/destinations/ftp_destination_service.dart`          | Após `ftp.deleteFile` (rollback)                      |
| `lib/infrastructure/external/destinations/google_drive_destination_service.dart` | Após `driveApi.files.delete` (rollback)               |
| `lib/presentation/managers/windows_message_box.dart`                             | `calloc.free` em showInfo/showError/show (3x)         |
| `lib/presentation/boot/service_mode_initializer.dart`                            | `SingleInstanceService().releaseLock()` antes de exit |
| `lib/infrastructure/external/destinations/nextcloud_destination_service.dart`    | Após `dio.deleteUri` (rollback)                       |
| `lib/infrastructure/external/destinations/dropbox_destination_service.dart`      | Rollback delete                                       |
| `lib/infrastructure/external/compression/compression_service.dart`               | Vários `encoder.close()` / fluxos (6x)                |
| `lib/application/services/auto_update_service.dart`                              | `AutoUpdater.instance.removeListener`                 |

### B. Catch com comentário "Ignore/Ignorar" (sem retornar Failure nem rethrow)

| Arquivo                                                                          | Linha aprox. | Comentário                                                                                  |
| -------------------------------------------------------------------------------- | ------------ | ------------------------------------------------------------------------------------------- |
| `lib/infrastructure/external/destinations/ftp_destination_service.dart`          | ~201         | Ignorar erro se não conseguir mudar de diretório                                            |
| `lib/infrastructure/external/destinations/ftp_destination_service.dart`          | ~210         | Ignorar erro (changeDirectory '/')                                                          |
| `lib/infrastructure/external/destinations/ftp_destination_service.dart`          | ~218         | Diretório pode já existir, ignorar erro                                                     |
| `lib/infrastructure/external/destinations/ftp_destination_service.dart`          | ~271         | Diretório não existe, sem backups para limpar → retorna `Success(0)` (tratamento explícito) |
| `lib/application/providers/dropbox_auth_provider.dart`                           | ~134, ~160   | Ignore window manager errors                                                                |
| `lib/application/providers/dropbox_auth_provider.dart`                           | ~222         | Ignore load errors (\_loadOAuthConfig)                                                      |
| `lib/infrastructure/external/destinations/google_drive_destination_service.dart` | ~351         | Nome não é uma data válida, ignorar (skip file)                                             |
| `lib/infrastructure/external/destinations/google_drive_destination_service.dart` | ~459         | Ignorar erros na verificação (401)                                                          |
| `lib/presentation/widgets/schedules/schedule_dialog.dart`                        | ~143         | Use defaults (\_parseScheduleConfig)                                                        |
| `lib/infrastructure/external/destinations/nextcloud_destination_service.dart`    | ~243         | Nome não é uma data válida, ignorar                                                         |
| `lib/infrastructure/external/destinations/dropbox_destination_service.dart`      | ~518         | Ignore errors when checking if file exists                                                  |
| `lib/infrastructure/external/destinations/dropbox_destination_service.dart`      | ~570         | Nome não é uma data válida, ignorar                                                         |
| `lib/infrastructure/external/dropbox/dropbox_auth_service.dart`                  | ~450, ~488   | Ignore save/clear errors (prefs)                                                            |
| `lib/application/services/scheduler_service.dart`                                | Várias       | Ignorar se não estiver disponível (progressProvider)                                        |
| `lib/application/services/backup_orchestrator_service.dart`                      | Várias       | Ignorar se não estiver disponível (progressProvider)                                        |

### C. Catch que só loga (sem Result nem rethrow)

- Vários em **providers** (license_provider, system_settings_provider, etc.): setam `_error` e `notifyListeners()` — isso é tratamento para UI, não supressão pura.
- **single_instance_service**, **ipc_service**, **window_manager_service**, **tray_manager_service**: em vários pontos só fazem log e continuam; em fluxos críticos o ideal é propagar ou retornar Failure quando a API permitir.

### D. Outros

- `lib/presentation/widgets/destinations/destination_list_item.dart`: `catch (e) { return ''; }` — helper de formatação de path; em erro retorna string vazia (supressão para exibição).

---

## Recomendações

1. **Infrastructure / Services que retornam `Result`**:
   - Em todo `catch`, retornar `rd.Failure(AlgumFailure(message: ..., originalError: e))`
   - Sempre usar `LoggerService.error()` antes de retornar o Failure
   - Nunca ignorar erros ou usar catch vazio

2. **Catch vazio em rollback** (ex.: delete após falha de upload):
   - Avaliar se faz sentido logar em nível debug e continuar
   - Usar `LoggerService.warning()` para rollback que falha
   - Não usar catch vazio: pelo menos `LoggerService.debug()` ou `LoggerService.warning()`

3. **"Diretório pode já existir" / "Nome não é data válida"**:
   - São casos de "não é erro" ou "pular item"
   - Manter comentário explicativo
   - Usar `LoggerService.debug()` para registrar esses casos

4. **Providers (UI)**:
   - Manter `_error` + `notifyListeners()` em catch
   - Usar `LoggerService.error()` para registrar o erro
   - Evitar catch que não altera estado nem notifica usuário

5. **window_manager / tray / single instance**:
   - Preferir tratar erros de configuração (desabilitar recurso)
   - Propagar até uma camada que possa retornar Result ou mostrar erro
   - Sempre usar `LoggerService.error()` para registrar erros

---

## Correções já aplicadas

- **LoggerService implementado**: Serviço centralizado de logging com métodos para debug, info, warning e error
- **ftp_destination_service**: `_createRemoteDirectories` / `_createRemoteDirectory` — erros de `changeDirectory` e `makeDirectory` passam a propagar; apenas "diretório já existe" continua ignorado com log em debug. Rollback (delete arquivo corrompido) usa `LoggerService.warning()`.
- **dropbox_auth_provider**: `setPreventClose` e `_loadOAuthConfig` — catch usa `LoggerService.debug()`.
- **google_drive_destination_service**: rollback (delete arquivo corrompido) usa `LoggerService.warning()`.
- **windows_message_box**: catch em `showWarning`/`showInfo`/`showError` usa `LoggerService.debug()`.
- **service_mode_initializer**: Todos os catch blocks usam `LoggerService.error()`.
- **service_health_checker**: Usa `LoggerService` para registrar health status com diferentes níveis de severidade.

## Próximos passos

- Substituir supressões restantes em métodos que retornam `Result` por `rd.Failure(...)` + `LoggerService.error()`
- Reduzir catch vazios restantes: onde for rollback/cleanup, usar `LoggerService.debug()` ou `LoggerService.warning()`
- Onde for operação principal, retornar Failure com LoggerService.error()
- Revisar providers e presentation: garantir que todo catch que representa "erro para o usuário" sete `_error`, use `LoggerService.error()` e notifique
