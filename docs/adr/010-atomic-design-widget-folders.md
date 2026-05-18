# ADR-010: Hierarquia Atomic Design em `presentation/widgets`

- Status: accepted
- Data: 2026-05-18
- Decisores: time do produto (app desktop backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (M8)

## Contexto

Componentes reutilizaveis viviam em `lib/presentation/widgets/common/`
sem separacao fisica entre atomos, moleculas e organismos, apesar dos
doc-comments (`**Atom**`, `**Molecule**`, `**Organism**`) ja existirem
desde o PR-C.

A pasta `common/` cresceu (botoes, grids, skeletons, modais) e dificulta
navegacao e onboarding.

## Decisao

Organizar o design system em tres pastas irmaas sob
`lib/presentation/widgets/`:

| Pasta | Conteudo |
| --- | --- |
| `atoms/` | `AppButton`, `AppTextField`, `AppCard`, `AppShimmer`, `EmptyState`, textos compartilhados (`widget_texts`), etc. |
| `molecules/` | `PasswordField`, `SaveButton`, `DatabaseConfigListItem`, skeletons de linha/card, `TestConnectionRunner`, etc. |
| `organisms/` | `MessageModal`, `AppDataGrid`, `DatabaseConfigDataGrid`, shells de dialogo, skeletons de pagina |

Manter `widgets/common/common.dart` como **barrel de compatibilidade**
que reexporta `atoms.dart`, `molecules.dart` e `organisms.dart`.

Widgets especificos de feature permanecem em pastas por dominio
(`widgets/sql_server/`, `widgets/firebird/`, …).

## Consequencias

### Positivas

- Estrutura alinhada a Atomic Design e aos doc-comments existentes.
- Imports novos podem apontar para `atoms/` / `molecules/` / `organisms/`
  de forma explicita.
- `import .../common/common.dart` continua funcionando (sem big-bang nos
  call sites).

### Negativas

- Duplicidade temporaria de caminhos de import (`common/` vs `atoms/`).
- Testes e widgetbook ainda podem viver em pastas `test/.../common/` ate
  renomeacao opcional.

### Neutras

- Nenhuma mudanca de comportamento de UI; apenas movimentacao de arquivos
  e barrels.

## Alternativas consideradas

### Manter apenas `common/`

- Zero churn, mas nao atende M8.
- Rejeitada.

### Migrar todos os imports para `atoms/` sem barrel `common/`

- Diff enorme em dezenas de arquivos.
- Rejeitada em favor do barrel de compatibilidade.

## Notas de implementacao

- Barrels: `atoms/atoms.dart`, `molecules/molecules.dart`,
  `organisms/organisms.dart`.
- Atualizar imports diretos (`.../common/foo.dart`) para o novo caminho
  quando o arquivo for tocado em PRs futuros.
