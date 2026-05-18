# Adicionar um novo SGBD (cookbook)

Guia operacional para incluir um quarto motor (ex.: Firebird) com o
**stack generico PR-E**. Contexto e trade-offs: **ADR-004**
(`docs/adr/004-generic-hexagonal-ports-sgbds.md`). Padroes obrigatorios:
secao **9** de `.cursor/rules/architectural_patterns.mdc`.

## Visao em 5 passos

| # | Camada | O que fazer |
| --- | --- | --- |
| 1 | **Domain** | `XxxConfig` com `@freezed` + `implements DatabaseConnectionConfig`; `IXxxConfigRepository extends IDatabaseConfigRepository<XxxConfig>`; `IXxxBackupService extends IDatabaseBackupPort<XxxConfig>`; estender `DatabaseType` e metadados de UI se precisar. |
| 2 | **Infrastructure** | Tabela Drift + DAO + bump de `schemaVersion`; `XxxConfigRepository` preferindo `BaseDatabaseConfigRepository<...>` + `RepositoryGuard` (secao 1 do mesmo `.mdc`); `XxxBackupService` implementando o port. |
| 3 | **Application** | `XxxConfigProvider extends DatabaseConfigProviderBase<XxxConfig>` com `AsyncStateMixin` (secao 2); factory de estrategia + `BackupValidationRule` / `BackupResultEnricher` quando fizer sentido (secao 9.2). |
| 4 | **DI** | Uma chamada `getIt.registerSgbd<...>(...)` em `registerBackupDatabaseDefaultSgbds` ou equivalente em `lib/core/di/infrastructure_module.dart` **depois** de `AppDatabase`, `ProcessService`, credenciais e demais deps do builder estarem no `GetIt`. Ver `lib/core/di/sgbd_registration.dart`. |
| 5 | **Presentation** | Pagina/dialog de config; schedules e destinos; reutilizar `DatabaseConfigDialogShell` / tokens (PR-C + `docs/onboarding/design_system.md`). |

## Checklist antes do PR

- [ ] Nenhum import de `presentation` ou `application` em `infrastructure/`.
- [ ] Nenhum import de `infrastructure` em `domain/`.
- [ ] Repositorio novo usa `RepositoryGuard` (sem try/catch manual).
- [ ] Provider novo com loading/erro usa `AsyncStateMixin` (sem duplicar `_isLoading`).
- [ ] Tamanhos e logs: `ByteFormat`; escrita em disco: `DirectoryPermissionCheck`.
- [ ] Registro DI segue o mesmo padrao que SQL Server / Sybase / Postgres em `registerBackupDatabaseDefaultSgbds`.

## Referencias rapidas

| Assunto | Onde |
| --- | --- |
| Extension `registerSgbd` | `lib/core/di/sgbd_registration.dart` |
| Registro dos tres SGBDs atuais | `registerBackupDatabaseDefaultSgbds` no mesmo arquivo |
| Limite de camadas | `.cursor/rules/clean_architecture.mdc` |
| Anti-patterns da auditoria | `.cursor/rules/architectural_patterns.mdc` (secao 5 e 7) |
