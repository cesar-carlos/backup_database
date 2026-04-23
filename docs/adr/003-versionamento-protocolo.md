# ADR-003: Versionamento formal do protocolo socket (`protocolVersion`)

- Status: accepted
- Data: 2026-04-19
- Decisores: time backend (servidor + cliente Flutter desktop)
- Contexto relacionado: `docs/notes/plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md` (M1.3, M4.1, M4.2, PR-1)

## Contexto

O `MessageHeader` (em `lib/infrastructure/protocol/message.dart`) ja
inclui um campo `version` que e populado com `_protocolVersion = 0x01`.
Esse byte existe na wire mas:

- nao e validado em runtime (parser le mas nao rejeita versoes
  desconhecidas);
- nao tem semantica documentada (o que muda entre `v1` e `v2`?);
- nao e exposto em nenhum endpoint para negociacao;
- nao tem politica formal de quebra/compat.

O plano (PR-1, PR-2, PR-3, PR-4) introduz mudancas significativas no
contrato remoto:

- envelope `statusCode/success/data/error`,
- `runId` em eventos de backup (ja entregue em M2.3 — backward compat
  por campo opcional),
- novos endpoints (`getServerHealth`, `getServerCapabilities`,
  `executeBackup` nao-bloqueante, `getExecutionStatus`),
- novos eventos (`backupQueued`, `backupDequeued`, `backupStarted`,
  `backupCancelled`),
- staging por `runId`, `getArtifactMetadata`, `cleanupStaging` remoto.

Sem politica de versao formal, instalacoes mistas (cliente novo +
servidor antigo, ou vice-versa) podem falhar de forma silenciosa ou com
mensagens crypticas. A matriz de compat M4.2 do plano define o
**desejo** de comportamento; ADR-003 define o **mecanismo** que
viabiliza esse desejo.

## Decisao

Formalizar versionamento do protocolo em **dois niveis** complementares:

1. **Versao de wire (`MessageHeader.version`)**:
   - Numero inteiro pequeno (`uint8`).
   - Bumpado **somente** quando o formato binario do header ou do
     envelope basico mudar (ex.: troca de tamanho do header, mudanca
     de checksum, novo formato de payload base).
   - Mudancas em payloads de mensagens individuais (campos novos,
     eventos novos) **nao** bumpam wire version — sao tratadas via
     `capabilities`.
   - Inicialmente `1`. Bump para `2` so apos ADR especifico justificando.

2. **Versao logica (`capabilities.protocolVersion`)**:
   - Inteiro sequencial que reflete o conjunto de features suportado.
   - Cliente le via `getServerCapabilities` no handshake.
   - Bumpado em cada PR principal:
     - `1`: estado atual em producao (envelope antigo, sem `runId`).
     - `2`: PR-1 mergeado (envelope REST-like, `capabilities`,
       `health`, `session`, guard pre-auth explicito).
     - `3`: PR-2 mergeado (CRUD de DB config, `executeBackup`
       nao-bloqueante, `runId` formal, `getExecutionStatus`).
     - `4`: PR-3 mergeado (mutex/fila, eventos de fila, staging por
       `runId`).
     - `5`: PR-4 mergeado (artefato com TTL, `cleanupStaging` remoto,
       lease de lock).

### Politica de compat (oficial)

- Servidor `v(N+1)` aceita cliente `vN` traduzindo envelope quando
  necessario. **Suporte minimo de 2 ciclos de release**: servidor `v4`
  ainda aceita cliente `v2`.
- Cliente `v(N+1)` em servidor `vN` **deve detectar via
  `getServerCapabilities`** e degradar para fluxo legado equivalente
  (sem erro ao usuario quando feature desejada nao existe).
- Mudanca em `MessageHeader` (wire) requer bump de wire version + ADR
  - nao tem traducao automatica.
- Mudanca de payload em `MessageType` existente requer **campo
  opcional adicional** (jamais quebra o existente em mesmo wire
  version). Variantes precisam de fixture golden separada (`*_v1` x
  `*_v2`) para validar backward compat.
- Remocao de `MessageType` requer aviso em `capabilities` por **1
  release inteiro** antes da remocao efetiva.
- Mudanca semantica em `errorCode` existente e **proibida**; criar
  novo `errorCode`.

### Uso de `capabilities` como gate de feature (M4.1)

Cliente deve consultar `getServerCapabilities` no handshake e:

- habilitar `runId`-aware code path apenas se
  `capabilities.supportsRunId == true`;
- habilitar fila apenas se
  `capabilities.supportsExecutionQueue == true`;
- habilitar resume com hash apenas se
  `capabilities.supportsArtifactRetention == true`;
- caso flag esteja `false`, usar fluxo legado equivalente sem erro.

`capabilities` payload minimo em PR-1:

```json
{
  "protocolVersion": 2,
  "wireVersion": 1,
  "supportsRunId": true,
  "supportsResume": true,
  "supportsArtifactRetention": false,
  "supportsChunkAck": false,
  "supportsExecutionQueue": false,
  "chunkSize": 65536,
  "compression": "gzip",
  "serverTimeUtc": "2026-04-19T12:00:00Z"
}
```

## Consequencias

### Positivas

- Mudancas de protocolo deixam de ser silenciosas: cliente sempre
  sabe o que o servidor suporta antes de chamar.
- Rollout gradual viavel: servidor pode subir antes do cliente (e
  vice-versa) sem big-bang.
- `capabilities` vira referencia unica para "esta feature esta
  disponivel?", eliminando heuristicas frageis.
- Permite politica explicita de descontinuacao (deprecation por 1
  release, remocao no seguinte).
- Cliente legado (`v1`) continua suportado por 2 ciclos sem mudanca.

### Negativas

- Cada novo PR principal precisa bumpar `protocolVersion` e atualizar
  `capabilities` consistentemente.
- Servidor passa a manter caminhos de traducao para clientes antigos.
  Custo de manutencao cresce com a janela de compat.
- Cliente passa a ter mais branches "se feature X disponivel ... senao
  ...". Risco de codigo defensivo demais se nao for disciplinado.
- Forca disciplina no PR review: toda mudanca de payload tem que
  declarar se afeta wire ou apenas semantico.

### Neutras

- Wire version continua `1` por enquanto. Nao ha plano de bump
  imediato.
- O campo ja existe no header — sem custo de wire format adicional.
- `protocolVersion` em `capabilities` e payload pequeno (<200 bytes),
  custa o equivalente a 1 mensagem de heartbeat.

## Alternativas consideradas

### Opcao A: Sem versionamento explicito (status quo)

- Continuar como hoje: servidor e cliente assumem o mesmo conjunto de
  features.
- **Rejeitada**: ja gera ambiguidade hoje (`fileAck` no enum sem
  implementacao). Vai piorar exponencialmente com PR-2 / PR-3.

### Opcao B: Apenas wire version (sem `capabilities`)

- Bumpar `MessageHeader.version` a cada mudanca relevante.
- **Rejeitada**: forca quebra de wire para mudancas que sao semanticas
  (novo campo opcional). Cliente velho nao consegue conectar em
  servidor novo nem para operacoes basicas.

### Opcao C: Apenas `capabilities` (sem wire version)

- Eliminar `MessageHeader.version` e usar so `capabilities`.
- **Rejeitada**: precisamos de mecanismo para detectar quebras
  binarias antes de tentar deserializar. Wire version e a primeira
  linha de defesa do parser.

### Opcao D: SemVer no `protocolVersion`

- `protocolVersion: "2.3.1"` com major.minor.patch.
- **Rejeitada**: complexidade extra sem ganho. Em protocolo de socket
  fechado entre nossos componentes, o sequencial inteiro acoplado a
  PRs e mais simples e tao expressivo quanto.

## Notas de implementacao

- Em PR-1:
  - [x] Adicionar validacao em `BinaryProtocol.deserializeMessage`:
        rejeitar header com wire version desconhecida (retornar `error`
        com `errorCode = UNSUPPORTED_PROTOCOL_VERSION`). _(implementado em
        2026-04-19; ver `binary_protocol.dart`,
        `UnsupportedProtocolVersionException` + `client_handler.dart` que
        responde com errorCode dedicado e desconecta apos o flush)._
  - [x] Documentar em `lib/infrastructure/protocol/protocol_versions.dart`
        as constantes `kCurrentWireVersion = 1` e `kCurrentProtocolVersion = 1`,
        com helper `isWireVersionSupported(int)`. _(implementado em 2026-04-19)_
  - [x] Implementar `getServerCapabilities` retornando o payload minimo
        acima. _(implementado em 2026-04-19 — `capabilities_messages.dart`,
        `CapabilitiesMessageHandler`, `ConnectionManager.getServerCapabilities()`,
        `ServerCapabilities` snapshot tipado com `legacyDefault` para
        fallback graceful em servidor antigo)._
  - [ ] Bumpar `kCurrentProtocolVersion` para `2` quando PR-1 for
        mergeado.
- Em cada PR subsequente:
  - Bumpar `kCurrentProtocolVersion`.
  - Atualizar fixtures golden de `capabilities`.
  - Adicionar entrada na matriz de compat M4.2 do plano.
- Cliente:
  - `ConnectionManager.connect` chama `getServerCapabilities`
    automaticamente apos auth e armazena resultado.
  - Expor getters como `isRunIdSupported`, `isExecutionQueueSupported`
    para os providers.
- Testes obrigatorios em PR-1:
  - Conexao com servidor `v1` continua funcionando (sem
    `getServerCapabilities`); cliente assume `protocolVersion: 1`
    como default.
  - Conexao com servidor `v2` retorna `capabilities` corretas.
  - Wire version invalida e rejeitada com `errorCode` claro.
- Quando bump de wire for inevitavel (futuro `v2` binario), criar ADR
  especifico que supersede este parcialmente, listando o caminho de
  migracao.
