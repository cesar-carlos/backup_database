# ADR-019: Usar as APIs nativas de janela e bandeja

- Status: accepted
- Data: 2026-11-17
- Complementa e substitui a decisao 3 do [ADR-018](018-flutter-350-desktop-and-goldens.md).

## Contexto

A revisao de lint identificou o uso de APIs obsoletas na ponte `legacy.dart`.
A migracao deve preservar fechamento controlado, restauracao, ordenacao das
operacoes e testes com falhas assincronas.

## Decisao

Usar as APIs publicas atuais de `window_manager` e `tray_manager` por adaptadores
do aplicativo: `desktop_window_backend.dart` e `desktop_tray_backend.dart`.
Os servicos mantem suas politicas e testes com backends injetaveis. A interceptacao
do X permanece ativa durante o encerramento; o cancelamento do evento ocorre
antes de aguardar a limpeza. Menus substituidos sao liberados no proximo turno
do event loop para nao destruir recursos usados por callbacks nativos.

## Consequencias

Nao ha dependencia da ponte obsoleta nem supressao de seus avisos. O aplicativo
passa a manter a traducao entre eventos nativos e suas politicas. Os testes dos
servicos devem ser complementados pelo smoke nativo Windows, especialmente ao
atualizar os plugins. Ausencia de janela nativa gera falha explicita.

Uma supressao de lint preservaria os avisos como divida tecnica e dependeria de
uma API prevista para remocao. A migracao agora permite validar a API atual antes
da publicacao.
