# AUDIT-10 — Stub Firebird perigoso

Data: 2026-05-22  
Ficheiro: `lib/infrastructure/external/process/firebird_backup_service_stub.dart`

## Risco

`listDatabases` devolve `Success(<String>[])` enquanto `executeBackup`, `testConnection` e `probeGstatHeaderConnection` falham com `ValidationFailure`.

Se o stub for registado no `GetIt` por engano (build parcial, teste mal isolado, fork de DI), o fluxo **Testar conexão** em `firebird_config_dialog.dart` trata lista vazia como sucesso (`names != null`) e **não** emite `listWarning` — o utilizador vê conexão OK sem bases listadas.

## DI actual

Produção: `sgbd_registration.dart` → `FirebirdBackupService` (implementação real). Stub só referenciado em testes (`real_database_connection_prober_test.dart` usa constantes de mensagem).

## Mitigação sugerida (não aplicada neste audit)

Alinhar `listDatabases` ao resto do stub: `Failure(ValidationFailure(message: probePendingMessage))`, ou `Failure` com mensagem explícita “lista de bases indisponível nesta build”.
