# ADR-018: Adaptar temas e validacao desktop ao Flutter 3.50

- Status: accepted
- Data: 2026-11-17
- Contexto relacionado: atualizacao de Flutter e dependencias; complementa
  [ADR-009](009-design-system-themeextension-composition.md) e
  [ADR-011](011-widgetbook-catalog-and-goldens.md).

## Contexto

A atualizacao para Flutter 3.50, Fluent UI 4.17, Window Manager 0.7 e Tray
Manager 0.9 alterou os tipos Material, a extensibilidade do tema Fluent e o
backend dos plugins desktop. Os goldens tambem omitiam componentes genericos
e os exemplos de grade apresentavam restricoes de largura incorretas.

## Decisao

1. Usar `material_ui` nos imports Material, incluindo testes e localizacoes.
2. Preservar `context.colors` / `context.appSemanticColors`. No Fluent, resolver
   light/dark por `brightness`; no Material, manter `ThemeExtension`. Isso
   substitui a parte do ADR-009 que registrava extensions no `FluentThemeData`.
3. Manter as politicas de janela e bandeja usando a ponte oficial `legacy.dart`
   sobre `nativeapi`. Injetar backends nos testes de politica e validar a
   integracao nativa com `tools/desktop_plugin_smoke.dart`.
4. Incluir `DatabaseConfigDataGrid` nos goldens, substituindo a exclusao do
   ADR-011. Normalizar nomes genericos e capturar uma raiz propria, com tema
   light e densidade comfortable. Essa captura nao cobre todas as combinacoes
   dos addons; dark exige verificacao separada.

## Consequencias

- A API semantica dos componentes e as politicas desktop permanecem estaveis.
- A ponte desktop gera avisos de depreciacao conhecidos; uma migracao futura
  deve preservar os testes de fechamento, restauracao e encerramento.
- Tests com backends simulados nao validam DLLs; o smoke nativo complementa-os.
- Goldens precisam de inspecao visual antes de atualizar referencias. Erros
  de layout ou capturas vazias nao sao alteracoes visuais aceitaveis.
- Testes e build Windows devem rodar sequencialmente no mesmo checkout para
  evitar disputa pelo manifesto de assets nativos.

## Alternativas consideradas

Forcar versoes transitivas por `dependency_overrides` ocultaria incompatibilidades
dos consumidores. Mantivemos versoes resolviveis e lockfiles independentes.
Substituir integralmente as APIs desktop nesta atualizacao ampliaria o risco
nos fluxos de restauracao; a ponte permite validar a migracao incrementalmente.

Comandos e restricoes atuais: [Desenvolvimento](../onboarding/development.md) e
[Widgetbook](../../widgetbook/README.md). Os ADRs anteriores permanecem como
registro historico; as substituicoes acima descrevem o comportamento atual.
