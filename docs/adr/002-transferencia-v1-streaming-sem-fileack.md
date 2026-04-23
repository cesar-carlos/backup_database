# ADR-002: Transferencia de arquivos `v1` sem `fileAck` (streaming puro)

- Status: accepted
- Data: 2026-04-19
- Decisores: time backend (servidor + cliente Flutter desktop)
- Contexto relacionado: `docs/notes/plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md` (M1.2, PR-4)

## Contexto

O protocolo `v1` ja inclui o `MessageType.fileAck` (definido em
`message_types.dart`) com a intencao de viabilizar
**ACK/backpressure por janela** durante a transferencia chunked de
arquivos. Na pratica:

- O servidor envia chunks em ordem (`fileChunk`).
- A intencao original era o cliente enviar `fileAck` periodicamente para
  indicar quantos chunks ja recebeu, e o servidor pausar o envio se o
  cliente nao acusasse (controle de janela estilo TCP-aware).
- Hoje, **nem o servidor nem o cliente implementam essa logica**.
  `fileAck` esta no enum mas nao ha factory, parser nem handler.
- A transferencia funciona em produc ao porque o socket TCP subjacente
  ja faz controle de fluxo a nivel de transporte: o `Socket.add` do
  servidor pressiona contra o `flush`, e o cliente consome
  sequencialmente.

O plano de PR-4 lista como item bloqueante: **decidir explicitamente** a
estrategia de transferencia para `v1`. Sem decisao, o `fileAck` fica
como debito tecnico ambiguo: pode ser interpretado como "feature
incompleta" ou como "feature obsoleta".

Implementar `ACK/backpressure` real para `v1` exige:

- janela deslizante negociada em `fileTransferStart` (ex.:
  `windowSize: 8 chunks`),
- mecanismo de pause/resume do envio no servidor,
- timeouts de `fileAck` ausente,
- testes de regressao de fluxo congestionado.

E uma feature complexa, sem demanda atual, e adicionada a um momento em
que o foco e estabilizar o contrato base (PR-1) e introduzir
`runId`/staging por execucao (PR-3).

Por outro lado, manter o tipo `fileAck` no protocolo sem implementacao
introduz ambiguidade: clientes terceiros podem assumir que o servidor
faz controle de janela e implementar comportamento incompativel.

## Decisao

Em `v1`, **remover `fileAck` do contrato negociavel** e adotar
**streaming puro com controle de fluxo delegado ao TCP**.

- O enum `MessageType.fileAck` continua existindo no codigo para
  compatibilidade nominal de deserializacao (peers `v0` que enviem
  `fileAck` nao quebram o parser; o servidor apenas ignora).
- Nenhum factory novo de `fileAck` e exportado para uso.
- A negociacao de transferencia em `capabilities` (M4.1) declara
  explicitamente `supportsChunkAck: false` em `v1`.
- ACK/backpressure real fica reservado para `v2`, condicionado a
  evidencia operacional concreta (ex.: regressao de memoria observada,
  perfil de cliente lento).

## Consequencias

### Positivas

- Reduz drasticamente o escopo do PR-4 (download resiliente). Sem
  janela/ACK para implementar, foco fica em **resume por chunk
  perdido**, **validacao de hash** e **TTL de artefato**.
- Elimina ambiguidade do `fileAck` "fantasma" no protocolo.
- Cliente atual continua funcionando sem mudanca (ja nao usa).
- Servidor atual continua funcionando sem mudanca (ja nao envia).
- Estrategia de transferencia fica **explicita** e coberta por teste
  (parte de M6.1 / golden test futuro).

### Negativas

- Em cenarios de cliente muito lento ou rede congestionada, a memoria
  do servidor pode crescer enquanto o `Socket.flush` segura o envio.
  Hoje isso ja acontece e e mitigado pelo limite de chunk size; sem
  ACK explicito, nao temos visibilidade de "cliente esta lento".
- Reverter a decisao em `v2` exige bump de protocolVersion (ver
  ADR-003) e cliente/servidor novos para negociar o novo modelo.
- Clientes terceiros que ja interpretavam `fileAck` como contrato real
  precisam atualizar sua implementacao (impacto provavelmente zero
  porque nao ha cliente terceiro conhecido).

### Neutras

- O wire format de `fileChunk` nao muda; apenas o ciclo de vida de
  `fileAck` muda (deixa de ser esperado).
- A telemetria de `socket_request_duration` por tipo de mensagem
  (M7.1) nao registra `fileAck` em `v1`.

## Alternativas consideradas

### Opcao A: Implementar `ACK/backpressure` real em `v1`

- Cliente envia `fileAck(windowSize=8, lastChunkReceived=N)`.
- Servidor pausa quando lastSent - lastAcked >= windowSize.
- Janela negociada em `fileTransferStart`.
- **Rejeitada para `v1`**: complexidade alta, sem demanda operacional.
  Risco de introduzir bugs sutis de deadlock se janela nao for bem
  dimensionada. PR-4 ja e grande sem isso.

### Opcao B: Manter `fileAck` no protocolo como "reservado" (futuro)

- Nao remover do enum, declarar em documentacao como "reservado".
- Cliente/servidor ignoram em `v1`.
- **Rejeitada parcialmente**: e basicamente o que esta sendo decidido,
  mas sem deixar explicito em `capabilities`. A diferenca e que
  ADR-002 obriga `supportsChunkAck: false` em `v1`, impedindo
  ambiguidade.

### Opcao C: Implementar ACK simples (apos cada chunk)

- Cliente envia ACK depois de cada `fileChunk`.
- Sem janela — apenas garantia de recebimento.
- **Rejeitada**: dobra o numero de mensagens trocadas, alto overhead
  (~50% do throughput em redes locais), sem ganho real porque TCP ja
  faz isso a nivel de transporte.

### Opcao D: Pull-based (cliente requisita cada chunk)

- Cliente envia `requestChunk(N)`, servidor responde com `fileChunk(N)`.
- Backpressure natural: servidor so envia quando pedido.
- **Rejeitada**: muda totalmente o modelo, exige reescrita do
  `FileTransferMessageHandler` e do `requestFile` no cliente.
  Latencia extra por chunk em redes lentas.

## Notas de implementacao

- `capabilities` payload em PR-1 deve incluir:
  ```json
  {
    "protocolVersion": 1,
    "supportsChunkAck": false,
    "supportsResume": true,
    "supportsArtifactRetention": false,
    ...
  }
  ```
- Adicionar comentario em `MessageType.fileAck` no enum:
  > `fileAck`: reservado para `v2`. Em `v1` nao e enviado nem
  > processado. Ver ADR-002.
- Em PR-1 (capabilities), incluir teste que valida
  `supportsChunkAck == false`.
- Em PR-4, golden test do envelope de `fileTransferStart` nao deve
  incluir nenhum campo `windowSize` ou `ackInterval`.
- Quando/se `v2` introduzir ACK real, criar ADR-XXX que supersede este
  e detalhe o protocolo.

## Estado da implementacao (2026-04-23)

- `CapabilitiesMessageHandler` anuncia `supportsChunkAck: false` de forma
  estavel; nao ha factory ativa de `fileAck` no caminho de envio.
- `FileTransferMessageHandler` confia no backpressure do `Socket` ao
  enviar chunks (comportamento descrito em **Consequencias** acima).
- Nenhuma janela deslizante ou `fileAck` e negociada em
  `fileTransferStart` no `v1` atual — alinhado a esta ADR.
