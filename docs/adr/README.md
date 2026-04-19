# Architecture Decision Records (ADRs)

Registro de decisoes arquiteturais relevantes para o projeto, no formato
Michael Nygard. Cada ADR captura uma decisao significativa: o contexto,
a opcao escolhida, as alternativas avaliadas e as consequencias
(positivas, negativas e neutras).

## Por que ADRs

- Decisoes arquiteturais perdem o "porque" rapidamente quando ficam apenas
  em chat/issue/PR. ADRs preservam o raciocinio para o futuro.
- Sao referenciaveis em planos, codigo e PRs (`ADR-001`, `ADR-002`, ...).
- Permitem reverter decisoes de forma explicita (`Status: superseded by
  ADR-XXX`) em vez de mudar codigo sem rastro.

## Quando criar um ADR

Sempre que a decisao:

- afetar mais de 1 modulo,
- envolver trade-off significativo entre opcoes,
- mudar contrato publico (API, protocolo, schema),
- ou for dificil de reverter depois.

Para mudancas locais e reversiveis, basta o PR.

## Formato

```
# ADR-NNN: Titulo curto e imperativo

- Status: proposed | accepted | superseded by ADR-XXX | deprecated
- Data: YYYY-MM-DD
- Decisores: <nomes ou times>
- Contexto relacionado: <plano/issue/PR>

## Contexto

O que esta acontecendo e por que precisamos decidir agora.

## Decisao

A escolha feita. Imperativa: "Vamos fazer X".

## Consequencias

### Positivas

- ...

### Negativas

- ...

### Neutras

- ...

## Alternativas consideradas

### Opcao A: <nome>

- Descricao
- Por que nao foi escolhida

### Opcao B: <nome>

- ...

## Notas de implementacao (opcional)

Apontamentos pragmaticos para quem for implementar.
```

## Indice

| ID | Titulo | Status | Data |
|---|---|---|---|
| [ADR-001](001-modelo-hibrido-scheduler.md) | Modelo hibrido para origem de execucao do scheduler | accepted | 2026-04-19 |
| [ADR-002](002-transferencia-v1-streaming-sem-fileack.md) | Transferencia de arquivos `v1` sem `fileAck` (streaming puro) | accepted | 2026-04-19 |
| [ADR-003](003-versionamento-protocolo.md) | Versionamento formal do protocolo socket (`protocolVersion`) | accepted | 2026-04-19 |

## Convencoes

- **Numeracao**: sequencial, 3 digitos, `001`, `002`, ...
- **Slug**: kebab-case curto (`001-runid-no-contrato`).
- **Nao editar** ADRs aceitos. Em vez disso, criar novo ADR com status
  `superseded by ADR-XXX`.
- **Status `proposed`** pode ser editado livremente ate decisao final.
