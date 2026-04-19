# Golden tests do envelope JSON do protocolo (M6.1)

Estes testes travam o **contrato JSON** de cada `MessageType` critico
contra uma fixture commitada. Servem como rede de seguranca para
mudancas no protocolo socket.

## Por que existem (M6.1 do plano)

- Detectar mudanca acidental de campo (`scheduleId` -> `schedule_id`).
- Detectar mudanca acidental de estrutura (nesting diferente, wrap em
  `data`/`error`).
- Documentar o contrato exato como artefato versionado.
- Garantir backward compat em deploys mistos cliente/servidor (servidor
  `v1` sem `runId` e servidor `v2+` com `runId` tem fixtures separadas).

## Como rodar

```bash
flutter test test/golden/protocol/envelope_golden_test.dart
```

## Como atualizar fixtures intencionalmente

Quando uma mudanca de contrato e proposital (ex.: novo campo opcional,
versionamento `v2 -> v3`):

```bash
# Linux / macOS
UPDATE_GOLDEN=1 flutter test test/golden/protocol/envelope_golden_test.dart

# PowerShell (Windows)
$env:UPDATE_GOLDEN='1'; flutter test test/golden/protocol/envelope_golden_test.dart; Remove-Item Env:UPDATE_GOLDEN
```

O modo update:

1. Reescreve cada `*.golden.json` com o output atual do factory.
2. **Falha o teste de proposito** para forcar voce a revisar o diff e
   re-rodar sem `UPDATE_GOLDEN`.
3. Espera-se que voce faca `git diff test/golden/protocol/fixtures/` e
   confirme que a mudanca e a desejada.

## Convencao das fixtures

```json
{
  "type": "<MessageType.name>",
  "payload": { ... }
}
```

Nao incluir:

- `requestId` - varia por chamada, validado em outros testes.
- `length`, `checksum`, `magic`, `version` - derivados, cobertos em
  `binary_protocol_test.dart`.

## Quando adicionar nova fixture

Adicionar fixture sempre que:

- Novo `MessageType` for criado.
- Novo campo opcional for adicionado a payload existente (criar fixture
  separada para variantes com/sem o campo, igual ao padrao
  `*_v1_legacy.golden.json` x `*_v2_with_run_id.golden.json`).
- Mudanca de wire format que precisa de matriz de compat (ex.: novo
  envelope REST-like com `statusCode`, ver M4.1/M4.2 do plano).

## Quando NAO adicionar fixture

- Variantes apenas de valor (mesmo schema, valores diferentes) - cobertas
  em testes unitarios convencionais.
- Mensagens com timestamps dinamicos sem injecao de tempo
  (`createAuthRequest` tem `ts` baseado em `DateTime.now()` - golden
  exigiria refatoracao para injetar relogio).

## Relacao com o plano

- **M6.1**: este arquivo e a entrega inicial.
- **M6.4**: golden tests para envelope completo (entrega futura, junto
  com PR-1 quando o envelope `statusCode/success/data/error` for
  introduzido).
- **M2.3**: variantes `*_v1_legacy` x `*_v2_with_run_id` validam
  backward compat ja entregue.
- **M1.3**: quando `protocolVersion` for formalizado, fixtures separadas
  por versao serao adicionadas aqui.
