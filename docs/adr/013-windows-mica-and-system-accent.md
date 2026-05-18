# ADR-013: Mica nativo no Windows e accent color do sistema (Fluent)

- Status: accepted
- Data: 2026-05-18
- Decisores: time desktop Flutter (app backup_database)
- Contexto relacionado:
  `docs/notes/plano_refatoracao_e_melhorias_2026-04-19.md` (M14)

## Contexto

O app e distribuido como utilitario Windows desktop (Fluent UI + `window_manager`).
Sem integracao com APIs visuais do SO, a janela parece um retangulo opaco
generico. O Windows 10/11 oferece materiais de janela (Mica) e o utilizador
pode personalizar a cor de destaque do sistema; alinhar-se a isso melhora a
percecao de "app nativo" e coerencia com outras aplicacoes.

## Decisao

1. Usar o pacote **`flutter_acrylic`** para inicializar o canal nativo e
   aplicar **`WindowEffect.mica`** quando a preferencia `use_windows_mica_backdrop`
   estiver ativa (default `true` quando a chave nao existe). Quando desativada,
   aplicar **`WindowEffect.disabled`** para regressar ao fundo padrao do SO.
2. Aplicar o efeito **apos** `window_manager` estar pronto e **antes** de
   `runApp`, lendo tema escuro e a flag Mica a partir de
   `IUserPreferencesRepository`. Falhas nativas sao capturadas e registadas com
   `LoggerService.warning` sem abortar o arranque.
3. Usar o pacote **`system_theme`** para obter o accent do Windows e mapear
   para `AccentColor` do Fluent quando a preferencia `use_system_accent_color`
   estiver ativa (default `false`). Quando desativada, manter
   `AppTheme.brandFluentAccent` (cor de marca).
4. Subscrever `SystemTheme.onChange` apenas enquanto a preferencia de accent do
   sistema estiver ativa; cancelar a subscricao ao desativar ou no `dispose` do
   `ThemeProvider`.
5. Ao alternar tema escuro, chamar `Window.setEffect` novamente com o mesmo
   `WindowEffect.mica` e o novo valor de `dark`, para o material acompanhar o
   brilho escolhido.

## Consequencias

### Positivas

- Janela principal alinha-se ao visual Windows 11 sem fork de `window_manager`.
- Utilizadores podem espelhar o accent do SO sem alterar tokens semanticos de
  superficie (`AppSemanticColors`).

### Negativas

- Dependencia de plugins nativos (`flutter_acrylic`, `system_theme`); em
   versoes antigas do Windows o Mica pode ser ignorado ou falhar de forma
   opaca — mitigado com try/catch e documentacao na UI de definicoes.
- O accent do sistema altera sobretudo `accentColor` do Fluent; componentes
   que usam `AppPalette.primary` diretamente continuam com a cor de marca.

### Neutras

- `main_layout.dart` nao foi tornado transparente; o Mica atua sobretudo na
   cromagem da janela e fundos que ja respeitam `scaffoldBackgroundColor`.

## Alternativas consideradas

### Opcao A: apenas `window_manager` com cor de fundo fixa

- Descricao: nao integrar `flutter_acrylic`.
- Por que nao: nao expoe Mica nem materiais DWM modernos de forma suportada.

### Opcao B: escrever FFI proprio para DWMWA\_USE\_IMMERSIVE\_DARK\_MODE / Mica

- Descricao: evitar dependencia de terceiros.
- Por que nao: custo de manutencao e duplicacao do que `flutter_acrylic` ja
  empacota.

## Notas de implementacao

- Smoke manual (Win10/Win11): `docs/notes/smoke_windows_mica_m14.md`.
- Teste CI (no-op fora do Windows):
  `test/unit/presentation/boot/windows_native_chrome_bootstrap_test.dart`.
- Bootstrap: `lib/presentation/boot/windows_native_chrome_bootstrap.dart`.
- Preferencias: chaves `use_windows_mica_backdrop` e `use_system_accent_color`
  em `UserPreferencesRepository`.
- UI: separador Geral em Windows — toggles com texto explicativo (Win10 vs
  Win11).
