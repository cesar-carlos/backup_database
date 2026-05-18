# Design tokens (W3C community format)

JSON nesta pasta segue o [Design Tokens Format](https://designtokens.org/format/)
(grupo comunitario W3C): cada folha expoe `$type` e `$value`.

Fluxo sugerido:

1. Designer exporta ou edita `*.tokens.json` aqui (ou no Figma com plugin
   compativel).
2. Na raiz do repo: `dart run tools/generate_tokens.dart`
3. Revisar diff em `lib/core/theme/tokens/generated/w3c_token_snapshot.g.dart`
   e abrir PR.
4. Os valores canonicos de runtime continuam em `AppSpacing`, `AppRadius`,
   etc.; o snapshot gerado serve de **contrato verificavel** e base para
   futura geracao automatica de Dart, se o time optar por isso.
5. CI: `dart run tools/generate_tokens.dart --check` (apos `flutter pub get`).
6. Teste: `test/unit/core/theme/w3c_design_tokens_sync_test.dart` confirma que
   o snapshot bate com `AppSpacing`, `AppRadius`, `AppDuration`, `AppPalette`.
