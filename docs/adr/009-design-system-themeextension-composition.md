# ADR-009: Design system com ThemeExtension e composition over inheritance

- Status: accepted
- Data: 2026-05-15
- Decisores: time desktop Flutter (app backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (PR-C,
  Etapas 1–4)

## Contexto

A camada de apresentação misturava literais de espaçamento, raio,
duração e cores (`AppColors` estático, `SizedBox(height: N)`,
`BorderRadius.circular(N)`), dificultando light/dark consistente,
redimensionamento de janela e evolução de componentes. Havia risco de
explosão combinatória em widgets pequenos (vários `bool` + ramos no
`build()`).

## Decisao

1. **Tokens primitivos** centralizados em `lib/core/theme/tokens/`
   (`AppSpacing`, `AppRadius`, `AppElevation`, `AppDuration`,
   `AppCurves`, `AppBreakpoints`, `AppDensity`, `AppTargetSize`,
   `AppZIndex`), exportados pelo barrel `tokens.dart` e por
   `lib/core/theme/theme.dart`.
2. **Cores semanticas** via `ThemeExtension<AppSemanticColors>` com
   acesso por `BuildContext` (`context.appSemanticColors` e alias
   `context.colors`). Cores de **marca/identidade** permanecem em
   `AppPalette` quando o contrato e intencionalmente fixo entre temas.
3. **Atomos de UI** (`AppCard`, `AppButton`, `AppTextField`,
   `MessageModal`, `EmptyState`) consomem tokens e, onde aplicavel,
   **composition** (slots `leading`/`trailing`, factories
   `.primary` / `.icon` / `.loading`) em vez de flags multiplas.
4. **Regras de projeto** consolidadas em
   `.cursor/rules/architectural_patterns.mdc` secao 8 (Design system e
   componentizacao).

## Consequencias

### Positivas

- Menos literais magicos; diffs de tema/localizacao mais previsiveis.
- Novos widgets alinham-se a um catalogo unico de tokens.
- `AppSemanticColors` acompanha automaticamente light/dark quando
  registrado no `FluentThemeData` / `ThemeData`.

### Negativas

- Curva inicial: contribuidores precisam consultar tokens e a secao 8
  das regras.
- Pacotes externos de design (ex. kits prontos M3) nao foram adotados;
  manutencao dos tokens e interna.

### Neutras

- `AppColors` permanece como fachada legada ate migracao gradual; novo
  codigo prefere `AppPalette` + `context.colors`.

## Alternativas consideradas

### Opcao A: Pacote third-party de design system (ex. templates M3)

- Descricao: adotar pacote que ja expoe spacing, tipo, componentes.
- Por que nao foi escolhida: app e **Fluent-first** no Windows; mistura
  pesada Material + Fluent na mesma superficie e desaconselhada nas
  regras do projeto; custo de adaptacao e dependencia maior que tokens
  enxutos proprios.

### Opcao B: Apenas `ThemeData` Material sem ThemeExtension custom

- Descricao: mapear tudo em `ColorScheme` padrao.
- Por que nao foi escolhida: nomes semanticos do dominio (perigo, info
  para notificacoes) e paleta de identidade (SGBD, destinos) nao cabem
  bem no modelo unico do ColorScheme sem extensions paralelas.

## Notas de implementacao

- Dialogos Fluent: usar `showDialog` de `fluent_ui` (nao o de
  `material.dart`) ao passar `transitionDuration: AppDuration.normal`.
- Revisao de PR: checklist na secao 8.5 de `architectural_patterns.mdc`.
