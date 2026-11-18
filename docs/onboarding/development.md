# Ambiente de desenvolvimento e validacao

Referencia da atualizacao validada em 17/11/2026. Para instalar o produto,
consulte os [requisitos operacionais](../requirements.md).

## SDK e dependencias

- Flutter stable **3.50.0**, com Dart **3.14.0** fornecido pelo SDK.
  Use a versao fixada nos workflows; nao substitua o Dart interno separadamente.
- Para compilar no Windows: Visual Studio com ferramentas C++ para desktop e
  Windows SDK. Verifique a instalacao com `flutter doctor -v`.
- Python 3 e PowerShell sao usados nas verificacoes; o instalador tambem
  exige Inno Setup. Consulte o [guia de release](../install/release_guide.md).
- Versione os lockfiles da raiz, de `widgetbook/` e de `packages/ftpconnect/`.
  O aplicativo e o Widgetbook resolvem dependencias separadamente.
- `ftpconnect` deve continuar como `path: packages/ftpconnect`: o fork local
  contem correcoes de retomada, cancelamento e timeouts. Uma troca pelo pacote
  publicado pode perder essas correcoes.

Na raiz do repositorio:

```powershell
flutter --version
flutter doctor -v
flutter pub get
# Somente se ainda nao existir .env; preserve configuracoes locais existentes:
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

O aplicativo real pode iniciar agendamentos configurados. Para testar apenas
janela e bandeja, use o smoke isolado descrito abaixo.

## Compatibilidade dos pacotes

As versoes resolvidas estao nos lockfiles. Na atualizacao de 17/11/2026,
as seguintes restricoes impediram adotar todas as ultimas versoes publicadas:

| Dependencia | Versao resolvida | Motivo |
| --- | --- | --- |
| `desktop_webview_window` | 0.3.2 | `oauth2_client` 4.3.3, via `flutter_web_auth_2`, exige a linha 0.3.x |
| `coverage` | 1.15.1 | A linha 1.16 exige `cli_util` 0.6, incompativel com `flutter_launcher_icons` 0.14.4 |
| `build_runner` no Widgetbook | 2.16.1 | `widgetbook_generator` 3.24 limita `analyzer` a <14 e `build` a 4.x |

Nao foram adicionados `dependency_overrides`. O gerador do Widgetbook funciona,
mas avisa que seu analisador antecede a linguagem Dart 3.14. Reavalie essas
restricoes ao atualizar dependencias, executando `flutter pub outdated` na raiz
e em `widgetbook/`; versao mais nova publicada nem sempre e resolvivel.

Material usa `material_ui`; Fluent UI 4.17 resolve cores semanticas pelo
`brightness`. Veja [design system](design_system.md). Window Manager 0.7 e
Tray Manager 0.9 usam as APIs nativas atuais por adaptadores em
`lib/presentation/managers/desktop_window_backend.dart` e
`desktop_tray_backend.dart`, sem importar a ponte obsoleta `legacy.dart`.
Os testes de politica injetam backends, e o smoke abaixo valida a integracao nativa.

## Validacao local

Execute sequencialmente no mesmo checkout: testes e build Windows escrevem
o manifesto de assets nativos e podem interferir entre si se rodarem juntos.

```powershell
dart format --output=none --set-exit-if-changed lib test tools
flutter analyze
dart run tools/generate_tokens.dart --check
dart run tools/design_system_guard.dart --fail-on-findings --enforce-target-size
py -3 scripts/scan_encoding.py
flutter test test/unit test/widget --reporter compact
flutter build windows --release
```

O lint deve terminar sem erros, warnings ou diagnosticos informativos,
como exigido pelo CI. Os testes do Widgetbook precisam ser executados
separadamente: [comandos e revisao de goldens](../../widgetbook/README.md).

Para FTP local, sem depender de credenciais de um servidor externo:

```powershell
$env:RUN_FTP_INTEGRATION = '1'
$env:RUN_FTP_REAL_INTEGRATION = '0'
flutter test test/integration/ftp_integration_test.dart
Remove-Item Env:RUN_FTP_INTEGRATION, Env:RUN_FTP_REAL_INTEGRATION
```

Os cenarios externos ficam ignorados nesse modo. O script
`test/scripts/run_ftp_integration_tests.py` habilita a integracao real quando
`FTP_IT_*` estiver completo no `.env`; sem essas variaveis, ele nao substitui
a execucao local explicita acima.

## Janela e bandeja nativas

Em uma sessao desktop interativa do Windows, a partir da raiz:

```powershell
flutter run -d windows -t tools/desktop_plugin_smoke.dart
```

O smoke nao abre o banco do aplicativo nem inicia agendamentos. Verifica
abertura, fechamento/minimizacao para bandeja, restauracao e recriacao do icone.
O resultado esperado e `DESKTOP_SMOKE_OK`, seguido de encerramento automatico.

## Preflight de release

Ao alterar logs, credenciais ou licenciamento, execute tambem as
[regressoes de seguranca](../security/logging-and-secrets.md#validacao).
Os testes de preparacao de chaves usam pares descartaveis em pastas temporarias;
nao substituem a rotacao de producao.

`scripts/release_preflight.ps1` oferece `Quick`, `Full` e `Installer`.
O modo `Full` executa suites unitarias e de widgets e analisa o Widgetbook;
nao executa seus goldens nem o smoke nativo. Rode esses dois separadamente
quando houver alteracoes visuais ou nos plugins desktop. Publicacao e
validacao do artefato estao no [guia de release](../install/release_guide.md).
