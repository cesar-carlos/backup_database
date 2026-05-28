# ADR-017: Adiar sliding window (`fileAck`) — manter envio passivo de chunks

- Status: deferred
- Data: 2026-05-28
- Decisores: time backup_database
- Contexto relacionado: auditoria do modo cliente — wave 2 (avaliação
  do protocolo) e wave 3 (correção de timeout)

## Contexto

A capability `chunkAck` está **declarada** no protocolo do servidor e
exposta via `ConnectionManager.isChunkAckSupported`, mas o cliente
**não implementa o lado de janela deslizante**. Hoje:

- O servidor envia chunks passivamente, sem aguardar `fileAck` por
  janela.
- O cliente consome `fileChunk` na ordem em que chegam, sem mandar
  `fileAck` de volta.
- O throughput é limitado pelo `TCP receive window` do socket do
  cliente — em redes com RTT alto (~150 ms entre regiões geográficas
  diferentes ou em VPNs corporativas), isso reduz consideravelmente o
  throughput médio comparado ao máximo do link.

A wave 2 identificou isso como **P2** com a recomendação:
> *Otimização de throughput em links com RTT alto — exige design (window
> size, retransmit, backpressure). Esforço: L (1-2 sprints).*

## Decisão

**Adiar** a implementação de sliding window neste ciclo. Manter:

1. **`chunkAck` na capability** (servidor já declara) — para o cliente
   não acidentalmente reivindicar suporte que não tem.
2. **Envio passivo** de chunks como caminho default.
3. **`fileTransferIdleTimeout`** (wave 3, P1) como watchdog de
   transferências travadas — cobre o caso operacional crítico
   (transferência muda por 2 min = aborta) sem precisar de janela
   negociada.

A capability continua exposta para que **server-side housekeeping** e
**telemetria** possam medir se vale a pena entregar a feature.

## Por que adiar (e não rejeitar)

- O ganho real depende do perfil de uso. Em LAN (RTT < 1 ms) o ganho
  é marginal; em backups intercontinentais (RTT > 100 ms) chega a
  3-5× em throughput. Hoje a base de clientes é **majoritariamente
  LAN** — engenharia para o cenário minoritário não compensa neste
  ciclo.
- Implementar bem exige decisões coordenadas com o servidor:
  - tamanho da janela (chunks ou bytes?),
  - estratégia de retransmissão (NACK explícito? timeout?),
  - backpressure (suspender envio se cliente atrasa o ack?),
  - migração compatível (o servidor antigo continua sem `chunkAck`
    quando o cliente novo não pede).
- Sem cobertura de teste E2E em rede simulada (`packet loss`, `delay`),
  qualquer implementação corre risco alto de regressão silenciosa
  (transferências completam mais devagar em vez de quebrar — fica
  invisível na CI).
- O **P1 da wave 3** (timeout por inatividade) já resolve a dor
  operacional principal: backup grande não aborta por deadline total
  e backup travado não fica pendurado indefinidamente.

## Consequências

### Positivas

- Sem código novo no caminho crítico de transferência → sem regressão
  potencial.
- `chunkAck` continua reservado no protocolo — quando entregarmos,
  não precisa bump de wire version.
- Hard ceiling de 6 h + idle watchdog de 2 min cobrem todos os perfis
  operacionais conhecidos.

### Negativas

- Throughput sub-baseline em links de RTT alto. Workaround documentado:
  rodar cliente próximo ao servidor (LAN ou região cloud comum).
- A capability "vazia" pode confundir desenvolvedores futuros — esta
  ADR é a referência canônica do "por que não implementamos ainda".

## Gates para reabrir

Reabrir a implementação quando **qualquer** destes for verdadeiro:

1. Pelo menos **3 clientes pagos** ou **um cliente enterprise** com
   backup remoto regular sobre link de RTT > 50 ms.
2. Métricas em produção mostrarem `throughput_mbps_p95 < link_mbps / 3`
   em mais de 10 % das transferências.
3. Necessidade externa (compliance, SLA) de retomada granular em
   transferência muito grande (atualmente o resume é por arquivo
   inteiro, com `.part` no client).

Cada gate alimenta um **issue de design** primeiro (incluindo testes
E2E em rede simulada e documentação do trade-off com a versão atual)
antes de qualquer commit de implementação.

## Referências

- `lib/infrastructure/socket/client/connection_manager.dart`
  (`isChunkAckSupported`, `_handleFileTransferMessage`)
- `lib/core/constants/socket_config.dart`
  (`fileTransferIdleTimeout`, `fileTransferHardTimeout` — mitigação wave 3)
- `lib/infrastructure/protocol/capabilities_messages.dart`
  (capability declaration)
- `docs/adr/002-file-transfer-resume-strategy.md` (resume por `.part`)
