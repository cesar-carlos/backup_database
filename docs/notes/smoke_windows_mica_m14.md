# Smoke manual — M14 (Mica e accent do sistema)

Referência: **ADR-013**, plano de refatoração (M14).

**Objetivo:** confirmar que a janela principal e as definições se comportam bem em
Windows 10 (sem Mica visível ou degradado) e Windows 11 (Mica ativo), sem crash no arranque.

**Pré-requisitos:** build `flutter run -d windows` ou instalador de release; conta com
permissão para alterar definições da app.

## Matriz

| Cenário | SO | Mica (definições) | Tema app | Verificar |
|---------|-----|-------------------|----------|-----------|
| A | Win10 | Ligado | Claro | App abre; fundo legível; sem crash ao alternar tema |
| B | Win10 | Desligado | Escuro | Fundo opaco/padrão; texto legível |
| C | Win11 | Ligado | Claro | Material Mica visível na cromagem da janela |
| D | Win11 | Ligado | Escuro | Mica escuro após toggle de tema |
| E | Win11 | Desligado | Claro | Efeito desativado (`WindowEffect.disabled`) |
| F | Qualquer | — | — | Accent do sistema ligado: botões Fluent seguem cor do Windows |
| G | Qualquer | — | — | Accent do sistema desligado: cor de marca (`AppTheme.brandFluentAccent`) |

## Passos (por cenário)

1. Abrir **Definições → Geral** (secção Windows).
2. Ajustar **Efeito Mica na janela** e **Usar cor de destaque do sistema** conforme a tabela.
3. Alternar tema claro/escuro na app (menu ou atalho existente).
4. Redimensionar a janela e minimizar/restaurar.
5. Fechar e reabrir a app — preferências persistidas.

## Critérios de aceite

- Nenhum crash ou tela branca no arranque.
- Logs sem erros repetidos de `flutter_acrylic` (avisos isolados aceitáveis em Win10).
- Contraste de texto principal legível em todos os cenários (WCAG smoke visual).
- Com Mica desligado, UI permanece utilizável (sem dependência de transparência).

## Evidência (marcar no plano)

- Data, máquina (build SO), versão da app.
- Capturas opcionais: Win11 Mica on/off, accent sistema on/off.
- Marcar `[x]` em `plano_refatoracao_e_melhorias_2026-04-19.md` (M14) após A–G.

## Automatizado no CI

- `test/unit/presentation/boot/windows_native_chrome_bootstrap_test.dart` — bootstrap
  não lança fora do Windows (Linux no GitHub Actions).
- `test/unit/infrastructure/repositories/user_preferences_repository_test.dart` —
  persistência `use_windows_mica_backdrop` / `use_system_accent_color`.

## Script interativo (Windows)

```powershell
.\tools\smoke_m14_windows.ps1
```

Regista cenários A–G e falha se algum operador marcar `n`.
