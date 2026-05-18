# Design system (onboarding)

Guia curto para quem cria ou altera UI no **backup_database**. Detalhes
de arquitetura: `docs/adr/009-design-system-themeextension-composition.md`
e secao **8** de `.cursor/rules/architectural_patterns.mdc`.

## Onde esta o codigo

| Area | Caminho |
| --- | --- |
| Tokens (spacing, radius, motion, breakpoints, …) | `lib/core/theme/tokens/` |
| Barrel dos tokens | `lib/core/theme/tokens/tokens.dart` |
| Export agregado do tema | `lib/core/theme/theme.dart` |
| Cores semanticas (tema) | `lib/core/theme/extensions/app_semantic_colors.dart` |
| Paleta de marca / identidade | `lib/core/theme/tokens/app_palette.dart` |
| Atomos de referencia | `lib/presentation/widgets/atoms/` (`AppCard`, `AppButton`, …) |
| Moléculas / organismos | `lib/presentation/widgets/molecules/`, `…/organisms/` |
| Barrel legado (reexport) | `lib/presentation/widgets/common/common.dart` |

## Catalogo de tokens (referencia)

Valores exatos estao no codigo-fonte; aqui a intencao de uso.

| Token | Papel |
| --- | --- |
| `AppSpacing` | Escala `xs`–`xxl`, `paddingXs`–`paddingLg`, `gapXs`–`gapLg` |
| `AppRadius` | Raios `sm`–`pill` e `BorderRadius` `circularSm` / `Md` / `Lg` |
| `AppElevation` | Profundidade numerica para sombras (ex. blur/offset) |
| `AppDuration` | `fast`, `normal`, `slow` para transicoes |
| `AppCurves` | Curvas padrao de animacao |
| `AppBreakpoints` | Larguras `compact` / `medium` / `wide` + getters no `BuildContext` |
| `AppDensity` | Enum com `spacingMultiplier` e `targetSize` por densidade |
| `AppTargetSize` | `minimum` (44) e `comfortable` (48) para alvos |
| `AppZIndex` | Inteiros nomeados para empilhar overlays |

## Criar um widget novo

1. Importar `package:backup_database/core/theme/theme.dart` (ou
   `tokens/tokens.dart` + extension de semanticas, conforme a camada).
2. Substituir `SizedBox(height: 16)` por gaps/padding de `AppSpacing`;
   evitar `BorderRadius.circular(8)` solto — usar `AppRadius`.
3. Estado de UI (erro, sucesso): `context.colors.danger`,
   `context.colors.success`, etc.
4. Cor de marca ou cor fixa de identidade (tipo de banco): `AppPalette`.
5. Para janela estreita: `context.isCompactWindow` (e afins) em vez de
   `MediaQuery.sizeOf(context).width < 720` espalhado.
6. No primeiro doc-comment do widget publico em `widgets/atoms/`,
   `widgets/molecules/` ou `widgets/organisms/`, indicar nivel **Atom** /
   **Molecule** / **Organism** quando fizer sentido.

## CI guard (atoms / molecules / organisms)

```bash
dart run tools/design_system_guard.dart --fail-on-findings --enforce-target-size
```

## Slot pattern (exemplo mental)

Em vez de `bool comIcone`, `bool carregando` multiplicados:

- Parametros `Widget? leading`, `Widget? trailing`.
- Factories ou construtores nomeados para casos frequentes
  (`AppButton.icon`, `AppButton.loading`).

Ver implementacao em `app_button.dart`.

## Checklist de acessibilidade (novo componente)

- [ ] Alvo clicavel custom com area minima proxima de
      `AppTargetSize.minimum` quando aplicavel.
- [ ] Botao ou acao so-icone: `Semantics(label: …)` (ou controle Fluent
      equivalente).
- [ ] Texto de erro ou critico: cor semantica (`context.colors`) e
      contraste aceitavel em light e dark.
- [ ] Foco/teclado: fluxo desktop nao quebrado (tab order, ` autofocus`
      apenas quando fizer sentido).

## Testes

- Regressao visual: `test/golden/widgets/common/design_system_atoms_golden_test.dart`
  e imagens em `test/golden/widgets/common/goldens/`.
- Acessibilidade: `test/widget/presentation/widgets/common/design_system_accessibility_test.dart`
  (`ensureSemantics`, `meetsGuideline` para alvos e contraste).
