# ADR-012: Baseline de acessibilidade alinhado a WCAG 2.1 AA (desktop Fluent)

- Status: accepted
- Data: 2026-05-18
- Decisores: time desktop Flutter (app backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (M12)

## Contexto

O app e distribuido como utilitario Windows desktop (Fluent UI). Sem
uma linha de base explicita, cor, contraste, tamanho de alvo, escala de
texto e semantica tendem a regredir em PRs focados em funcionalidade.
Clientes corporativos frequentemente exigem evidencias de acessibilidade
(WCAG 2.1 AA como referencia comum).

## Decisao

1. **Contraste de texto**: novas superficies de leitura devem passar
   `meetsGuideline(textContrastGuideline)` em testes widget quando a
   superficie for estavel (temas claro e escuro com
   `AppSemanticColors` registrado no tema Fluent).
2. **Alvos de toque/teclado**: acoes primarias repetiveis usam
   `AppTargetSize.comfortable` (48 logical pixels) como minimo onde o
   controle e exclusivamente apontador/teclado; a shell principal
   (`MainLayout`) e coberta por teste de guideline de tap target.
3. **Escala de texto**: layouts de paginas principais devem tolerar
   `TextScaler.linear(1.5)` e `2.0` sem overflow em testes widget com
   viewport desktop representativa (`MediaQueryData` nos testes).
4. **Semantica**: botoes com texto visivel nao duplicam leitura de
   `Icon` decorativo no `leading` (`ExcludeSemantics` ou equivalente);
   acoes somente icone recebem `Semantics(button: true, label: ...)` ou
   `Tooltip` com mensagem equivalente ao rotulo.
5. **Navegacao por teclado**: fluxos criticos devem ser percorriveis com
   `Tab` / `Shift+Tab` e ativacao coerente (`Enter` / `Esc` em
   dialogos Fluent); lacunas sao tratadas como bugs de a11y, nao como
   melhoria opcional.
6. **Evidencia em PR**: o template de pull request inclui checklist
   minima de a11y; mudancas em UI sem atualizar testes/guidelines
   exigem justificativa no corpo do PR.

## Consequencias

### Positivas

- Criterios objetivos (guidelines Flutter + testes) reduzem discussao
  subjetiva em revisao.
- Regressoes de layout sob escala de texto sao detectadas cedo.

### Negativas

- Manutencao de harness de teste (mocks/providers) para paginas
  complexas pode crescer; priorizar shell + paginas de alto trafego.
- WCAG 2.1 AA nao e verificacao automatica completa; checklists e
  revisao manual continuam necessarias para cobertura total.

### Neutras

- O app permanece Fluent-first; guidelines Material de tap target sao
  usadas como **aproximacao** util no ecossistema Flutter, nao como
  substituto de auditoria legal formal.

## Alternativas consideradas

### Opcao A: Conformidade declarada sem testes automatizados

- Descricao: documentar intencao WCAG apenas em texto.
- Por que nao foi escolhida: regressoes passariam despercebidas; custo
  marginal de testes widget seletivos e aceitavel.

### Opcao B: Migrar UI critica para Material 3 so para a11y

- Descricao: usar M3 onde o pacote oferece semantica pronta.
- Por que nao foi escolhida: conflita com decisao Fluent-first e com
  regras de consistencia visual do projeto.

## Notas de implementacao

- Testes de referencia:
  `test/widget/presentation/pages/main_pages_accessibility_test.dart`,
  `test/widget/presentation/pages/database_config_page_empty_sections_test.dart`,
  `test/widget/presentation/pages/main_layout_accessibility_test.dart`,
  `test/widget/presentation/widgets/common/design_system_accessibility_test.dart`.
- Tokens: `AppTargetSize`, `AppSpacing`, `AppSemanticColors` (ADR-009).
