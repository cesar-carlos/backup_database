# Smoke manual Firebird (operacional)

Referência: `plano_suporte_firebird_2026-04-19.md` **§8** e **§8.1**.

O repositório já cobre MVP com testes unitários e de widget (sem motor real).
Este runbook é para evidência em VM/máquina com Firebird 2.5, 3.0 e 4.0.

## Pré-requisitos

- `gbak`, `nbackup`, `gstat`, `isql` no PATH (ou pasta configurada na UI).
- Bases de teste descartáveis; credenciais com permissão de backup.
- App build release ou `flutter run -d windows`.

## Matriz mínima (§8)

| Versão | Auth / wire | Ferramentas | Cenários |
|--------|-------------|-------------|----------|
| 2.5 | Legacy, sem WireCrypt | gbak full, nbackup 0 e incremental -B 1 | Backup + restore smoke |
| 3.0 | SRP, WireCrypt opcional | gbak, nbackup -B 0/1, service_mgr se remoto | Full single + nbackup |
| 4.0 | SRP256, WireCrypt Enabled | gbak (-KEYNAME se DB criptografada), nbackup -B 0/1 | Idem 3.0 |

## Cliente remoto (PR-G)

1. Servidor **sem** `supportsFirebird`: UI sem secção Firebird (já coberto em widget tests).
2. Servidor **com** `supportsFirebird`: agendar/executar backup remoto; confirmar logs `tool=gbak|nbackup` e `firebirdVersion` em métricas.
3. Servidor legado (protocolo antigo): cliente não oferece Firebird.

## Evidência

- Data, versão FB, versão app, tipo de backup (gbak/nbackup).
- Caminho do artefato `.fbk` / `.nbk` e tamanho.
- Trecho de log sem password (`ProcessService` redact).

Marcar checkboxes em `plano_suporte_firebird_2026-04-19.md` §8 após execução.
