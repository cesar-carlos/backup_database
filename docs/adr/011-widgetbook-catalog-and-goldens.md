# ADR-011: Catálogo Widgetbook irmão e goldens por use case

- Status: accepted
- Data: 2026-05-18
- Decisores: time desktop Flutter (app backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (M10)

## Contexto

O plano de refatoração pedia catálogo interativo (Widgetbook) e testes
visuais automáticos. O pacote oficial `widgetbook_test` no pub.dev é
apenas um placeholder; era preciso escolher uma stack concreta para
gerar imagens de regressão a partir dos mesmos use cases do catálogo,
sem duplicar manualmente dezenas de `matchesGoldenFile` no pacote
principal.

## Decisao

1. **App irmão** `widgetbook/` com pacote `widgetbook_workspace`,
   dependência `path: ../` sobre `backup_database`, `widgetbook`,
   `widgetbook_annotation`, `widgetbook_generator` e `fluent_ui`.
2. **Goldens** via pacote **`widgetbook_golden_test`** (não
   `widgetbook_test`): `runWidgetbookGoldenTests` em
   `widgetbook/test/widgetbook_use_cases_golden_test.dart`, importando
   `main.directories.g.dart` gerado pelo `widgetbook_generator`.
3. **Ambiente visual dos goldens**: `LocalizationAddon` + dois
   `ThemeAddon` (`FluentThemeData` light/dark sem Google Fonts, só
   `AppSemanticColors`; e `AppDensity` com `InheritedAppDensity`), para
   alinhar ao padrão já usado em
   `test/golden/widgets/common/design_system_atoms_golden_test.dart`.
4. **Subconjunto e exclusões**: não gerar golden para
   `DatabaseConfigDataGrid` (largura e scroll); excluir por filtro
   `AppTextField` / **Knobs** (depende de estado interno do Widgetbook)
   e `AppButton` / **Loading** (`ProgressRing` não estabiliza em
   `pumpAndSettle`).

## Consequencias

### Positivas

- Use cases adicionados ao catálogo passam a poder ter golden com um
  `flutter test` no subprojeto (após `dart run build_runner build` quando
  mudar anotações).
- Tema e densidade reproduzíveis via addons, próximo do app real.

### Negativas

- `flutter test` na raiz do monorepo **não** executa estes testes; CI ou
  devs precisam rodar explicitamente
  `cd widgetbook && flutter test test/widgetbook_use_cases_golden_test.dart`
  (e `--update-goldens` ao alterar UI dos use cases incluídos).
- Coexistência com `design_system_atoms_golden_test.dart`: dois canais
  de regressão visual até eventual consolidação.

### Neutras

- PNGs versionados em `widgetbook/test/goldens/widgetbook/...`.

## Alternativas consideradas

### Opcao A: Apenas goldens manuais no pacote `backup_database`

- Descricao: expandir só `test/golden/widgets/common/`.
- Por que nao: não reutiliza a árvore de use cases do Widgetbook.

### Opcao B: `widgetbook_test` (pub oficial)

- Descricao: usar o pacote homónimo do plano original.
- Por que nao: pacote vazio no pub.dev; sem API de golden.

## Notas de implementacao

- Após alterar `@UseCase` / `@App`: `dart run build_runner build` dentro
  de `widgetbook/`.
- Atualizar imagens:  
  `flutter test test/widgetbook_use_cases_golden_test.dart --update-goldens`
  a partir de `widgetbook/`.
- Para incluir novos componentes nos goldens, ajustar
  `_includeComponent` / `_skipUseCase` no ficheiro de teste.
