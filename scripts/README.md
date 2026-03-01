# Scripts Operacionais

Este diretorio reune scripts de suporte para manutencao, metricas e release.

## Inventario Atual

| Script | Tipo | Finalidade |
|---|---|---|
| `check_database.dart` | Dart | Diagnostico do banco local (somente leitura) |
| `recreate_database.dart` | Dart | Recria banco local do zero (destrutivo) |
| `migrate_database.dart` | Dart | Migra banco preservando dados com backup/export |
| `parse_ftp_metrics.dart` | Dart | Extrai metricas de FTP a partir de logs |
| `run_parse_ftp_metrics.py` | Python | Wrapper para `parse_ftp_metrics.dart` |
| `coverage.py` | Python | Executa testes com cobertura e filtro de lcov |
| `sync_appcast_from_releases.py` | Python | Versao Python do sincronizador de appcast |
| `update_appcast_manual.py` | Python | Atualiza `appcast.xml` manualmente para uma versao |

## Banco de Dados

### `check_database.dart`

Verifica existencia, tamanho, tabelas e versao de schema.

```bash
dart run scripts/check_database.dart
```

### `migrate_database.dart`

Migracao completa com preservacao de dados:

1. Cria backup (`backup_database_backup.db`)
2. Exporta dados (`backup_export.json`)
3. Recria estrutura
4. Reimporta e valida dados

```bash
dart run scripts/migrate_database.dart
```

### `recreate_database.dart`

Recria banco do zero. Use apenas quando for aceitavel perder dados atuais.

```bash
dart run scripts/recreate_database.dart
```

## Metricas FTP

### `parse_ftp_metrics.dart`

Le logs de FTP e gera resumo com:

- sucessos e erros
- retomadas (`REST + STOR`)
- fallbacks para upload completo
- erros de integridade

```bash
dart run scripts/parse_ftp_metrics.dart logs/app.log
dart run scripts/parse_ftp_metrics.dart --export csv logs/*.log
```

### `run_parse_ftp_metrics.py`

Facilita o uso do parser no Windows.

```bash
python scripts/run_parse_ftp_metrics.py --log-path logs --export csv
```

## Cobertura de Testes

### `coverage.py`

Executa testes com cobertura, filtra arquivos gerados/testes e calcula percentual.

```bash
python scripts/coverage.py
python scripts/coverage.py --fail-under 70
python scripts/coverage.py --test-targets "test/unit/application/services/scheduler_service_test.dart,test/unit/infrastructure/external/scheduler/schedule_calculator_test.dart"
python scripts/coverage.py --dart-mode --fail-under 70
```

## Appcast / Releases

### `sync_appcast_from_releases.py`

Sincronizam `appcast.xml` com todos os releases publicos do GitHub.

### `update_appcast_manual.py`

Atualizacao manual para um release especifico:

```bash
python scripts/update_appcast_manual.py <versao> <asset_url> <asset_size_bytes>
```

## Limpeza de Scripts

- `migrate_database_standalone.dart` foi removido por obsolescencia.
- Use apenas `migrate_database.dart` como fluxo oficial de migracao.
