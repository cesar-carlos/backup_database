# Widgetbook

Catalogo visual do aplicativo `backup_database`, dependente da raiz por
`path: ../`. Use o mesmo SDK do app; consulte o
[ambiente de desenvolvimento](../docs/onboarding/development.md).

## Executar e gerar o catalogo

A partir da raiz do repositorio:

```powershell
cd widgetbook
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d windows
```

Gere novamente `lib/main.directories.g.dart` ao alterar anotacoes `@UseCase`
ou `@App`. Nao edite o arquivo gerado manualmente. O lockfile deste pacote
e independente do aplicativo; preserve ambos nas atualizacoes.

## Testes visuais

Dentro de `widgetbook/`:

```powershell
flutter analyze --no-fatal-infos
flutter test test/widgetbook_use_cases_golden_test.dart
```

O teste cobre 47 use cases na revisao de 17/11/2026, incluindo os quatro de
`DatabaseConfigDataGrid`. Os filtros `_includeComponent` e `_skipUseCase`
definem a cobertura; `AppTextField/Knobs` e `AppButton/Loading` ficam excluidos.
Componentes genericos usam o nome sem parametros de tipo para selecao e caminhos.

A captura usa uma raiz propria para evitar selecionar widgets do shell do
renderizador. O tema capturado e Fluent light, com densidade comfortable.
Os addons nao representam uma matriz automatica de todos os temas e densidades;
o golden atual nao comprova a aparencia em dark. Grades com linhas recebem
largura limitada no scroll; estados vazios nao usam scroll horizontal sem limites.

Quando uma mudanca visual intencional exigir novas referencias:

1. Execute a comparacao e inspecione as diferencas e imagens em `test/failures/`.
2. Corrija erros de layout, recortes e capturas vazias antes de atualizar.
3. Atualize e execute novamente sem a flag de atualizacao:

```powershell
flutter test test/widgetbook_use_cases_golden_test.dart --update-goldens
flutter test test/widgetbook_use_cases_golden_test.dart
```

Revise os PNGs alterados em `test/goldens/widgetbook/` e versione-os junto
com o codigo. Execute comparacoes no mesmo ambiente/SDK usado para gerar
as referencias, pois fontes e renderizacao podem variar entre plataformas.

`flutter test` na raiz nao executa esta suite. O workflow `Test` e o preflight
`Full` analisam o Widgetbook, mas nao rodam estes goldens: a verificacao visual
precisa ser executada explicitamente.

## Windows

O executavel do Widgetbook usa `widgetbook/windows/runner/resources/app_icon.ico`.
Esse arquivo e sincronizado automaticamente quando voce roda `python installer/build_installer.py` na raiz do monorepo.

Gerar apenas os icones do aplicativo principal com `dart run flutter_launcher_icons`
nao substitui essa sincronizacao.
