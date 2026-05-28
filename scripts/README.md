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
| `update_appcast_manual.py` | Python | **DEPRECATED** — manutencao emergencial; o fluxo oficial usa `update-appcast`. Exige `--sha256` para nao gerar feed silenciosamente invalido. |
| `verify_windows_icons.py` | Python | Valida `app_icon.ico`, `app_tray.ico` e hash da fonte PNG (CI / pre-release) |
| `windows_icon_utils.py` | Python | Modulo compartilhado: hashing, sidecar e checagem do PNG embutido no `.exe` |
| `install_git_hooks.py` | Python | Instala hooks opt-in de `scripts/hooks/` em `.git/hooks/` |
| `hooks/pre-commit` | Bash | Hook opt-in: roda `verify_windows_icons.py` quando assets de icone sao staged |

## Icones Windows

### `verify_windows_icons.py`

Confere artefatos de icone antes de merge ou release:

```bash
python scripts/verify_windows_icons.py
```

Falha se `app_tray.ico` divergir de `app_icon.ico` (sem `.tray_icon_custom`) ou se o hash em `windows/runner/resources/.app_icon_source_sha256` nao bater com `database_512px.png`.

Flags opcionais:

- `--require-exe`: alem das checagens padrao, falha se `build/windows/x64/runner/Release/backup_database.exe` nao existir ou nao embutir o PNG do `app_icon.ico` atual. Usado por `installer/build_installer.py` apos `flutter build windows --release` para detectar o caso em que o `.exe` foi compilado com o icone antigo.
- `--skip-exe`: pula explicitamente a checagem do `.exe` mesmo quando o binario esta presente (uso raro; default ja pula em CI Linux).

### `windows_icon_utils.py`

Modulo Python compartilhado entre `verify_windows_icons.py` e `installer/build_installer.py`. Concentra:

- `sha256_file(path)` — hash de arquivo
- `png_source_hash_mismatch(root)` — sidecar `.app_icon_source_sha256` vs PNG
- `extract_largest_png_from_ico(ico_bytes)` — extrai payload PNG do ICO gerado por `flutter_launcher_icons`
- `exe_embeds_icon_png(exe_path, png_bytes)` — confere se o PNG aparece dentro do `.exe`

Testes unitarios sem artefatos reais: `python test/scripts/test_windows_icon_utils.py`.

### Git hooks opt-in

Para ativar o hook local que valida automaticamente os artefatos de icone
em cada `git commit`:

```bash
python scripts/install_git_hooks.py
```

Use `--force` para sobrescrever hooks existentes ou `--uninstall` para
remover. O hook so dispara quando o commit toca `database_512px.png`,
`app_icon.ico`, `app_tray.ico` ou o sidecar de hash; commits que nao
afetam icones passam sem custo.

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

Reconstrui `appcast.xml` do zero a partir de todos os releases publicados
do GitHub, deduplicando versoes, aplicando `scripts/appcast_policy.json`
(incluindo `blocked_versions`, `min_supported_app_version`,
`rollout_percentages`, `min_publication_age_minutes`) e exigindo o
sidecar `.sha256` em cada release elegivel.

Para o schema completo da policy, veja
`docs/install/release_guide.md#schema-de-scriptsappcast_policyjson`.

### `update_appcast_manual.py` (DEPRECATED)

Utilitario legado para manutencao emergencial. O fluxo oficial continua sendo
publicar a release com sidecar `.sha256` e deixar o workflow `update-appcast`
reconstruir o feed.

Diferenca importante vs. versao antiga: o `--sha256` e obrigatorio. Sem
ele, o runtime descartaria o item silenciosamente (ver `parseAppcast` em
`auto_update_service.dart`).

Uso:

```bash
python scripts/update_appcast_manual.py <versao> <asset_url> <asset_size_bytes> --sha256 <hex64>
```

## Limpeza de Scripts

- `migrate_database_standalone.dart` foi removido por obsolescencia.
- Use apenas `migrate_database.dart` como fluxo oficial de migracao.
