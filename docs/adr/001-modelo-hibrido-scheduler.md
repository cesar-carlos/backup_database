# ADR-001: Modelo hibrido para origem de execucao do scheduler

- Status: accepted
- Data: 2026-04-19
- Decisores: time backend (servidor + cliente Flutter desktop)
- Contexto relacionado: `docs/notes/plano_cliente_recursos_servidor_execucao_remota_2026-02-21.md` (M1.1, F2.0, F2.8, P0.3a)

## Contexto

Hoje o servidor desktop expoe duas formas de iniciar um backup:

1. **Local (timer-driven)**. `SchedulerService.start` agenda um
   `Timer.periodic(Duration(minutes: 1), _checkSchedules)`. Quando uma
   schedule esta vencida, o servidor executa o pipeline completo:
   dump -> compactacao -> upload para destinos finais configurados
   localmente no proprio servidor (ex.: FTP, Drive, pasta de rede).
2. **Remoto (comando do cliente)**. `ScheduleMessageHandler` recebe
   `executeSchedule` do cliente Flutter, dispara o mesmo pipeline e
   adicionalmente publica o artefato em staging para o cliente baixar.
   Hoje o servidor **tambem** executa o upload para destinos locais do
   servidor neste fluxo.

O plano "cliente consome recursos do servidor" (PR-3 em diante) exige
que execucoes originadas remotamente sejam **server-first**: o servidor
prepara o artefato, o cliente baixa, o cliente distribui para destinos
finais. Caso contrario o backup e enviado duas vezes (uma pelo servidor,
outra pelo cliente) e a politica de "destino final controlado pelo
cliente" e violada.

Por outro lado, eliminar completamente o scheduler local quebra
implantacoes existentes que dependem do servidor distribuir aos seus
proprios destinos (ex.: maquinas legadas onde o cliente nao esta
instalado, ou onde a regulamentacao exige que o servidor de origem faca
a copia diretamente para o storage corporativo).

Precisamos decidir antes do PR-3 qual modelo a arquitetura suportara.

## Decisao

Adotar **modelo hibrido controlado por origem da execucao**:

- Toda execucao recebe um campo explicito `executionOrigin`:
  - `executionOrigin = local`: dispar ada pelo `_checkTimer` ou por
    "Run now" da UI do servidor. Comportamento legado preservado:
    upload para destinos finais configurados no proprio servidor.
  - `executionOrigin = remoteCommand`: disparada por comando
    `executeSchedule`/`startBackup` do cliente. **Server-first**: o
    servidor NAO executa upload para destinos finais; apenas publica em
    staging para o cliente baixar.
- O scheduler local continua existindo. Seu comportamento e
  identico ao atual quando produz origem `local`.
- O staging remoto fica restrito a execucoes com origem `remoteCommand`.

A decisao **rejeita** o modelo "cliente-driven puro" (matar o scheduler
local) e o modelo "server-only puro" (manter upload no servidor sempre)
porque ambos quebrariam casos de uso reais ja em producao.

## Consequencias

### Positivas

- Zero quebra de implantacoes legadas que dependem do scheduler local
  - destinos do servidor.
- Cliente moderno controla 100% do destino final em execucoes
  `remoteCommand`, eliminando o problema de "upload duplicado" descrito
  no plano.
- Decisao explicita facilita teste: cada `executionOrigin` tem suite
  propria.
- Permite migracao gradual: instalacoes podem desligar o scheduler
  local via configuracao quando o cliente assumir 100% das execucoes.
- O metadado `executionOrigin` ja entra no `runId`/historico, abrindo
  espaco para metricas e diagnostico segmentados (ex.: latencia de
  backup local vs remote-first).

### Negativas

- Dois caminhos de execucao precisam ser mantidos. Risco de divergencia
  comportamental se nao houver testes que cobrem ambos.
- Requer disciplina nos handlers/servicos para sempre propagar
  `executionOrigin` ate o ponto de decisao (`destinationOrchestrator`).
- Cada novo destino/feature tem que considerar os dois modos.
- Configuracao de destinos no servidor passa a ter semantica
  contextual: "destinos sao usados em origem `local`, ignorados em
  origem `remoteCommand`". Documentar bem.

### Neutras

- Codigo do `SchedulerService` permanece igual no caminho de execucao;
  a diferenca fica no `destinationOrchestrator` que recebe a origem
  como parametro e decide se pula ou nao a etapa de upload final.
- Plano de versionamento (ADR-003) cobre como cliente/servidor
  negociam suporte a `executionOrigin = remoteCommand` via
  `capabilities`.

## Alternativas consideradas

### Opcao A: Cliente-driven puro (matar scheduler local)

- O servidor nao agenda nada. Toda execucao vem de comando do cliente.
- **Rejeitada**: quebra implantacoes onde o cliente nao esta instalado
  ou onde regulamentacao exige upload servidor-direto. Implantacoes
  legadas teriam que migrar todas de uma vez.

### Opcao B: Server-only puro (manter upload no servidor sempre)

- Servidor sempre faz upload para destinos finais; cliente apenas
  espelha o artefato.
- **Rejeitada**: viola a politica explicita "cliente controla destino
  final" e mantem o problema de "upload duplicado" em destinos comuns
  ao servidor e ao cliente.

### Opcao C: Feature flag global (`useServerFirst = true|false`)

- Uma flag por servidor escolhe entre os dois modos.
- **Rejeitada**: forca a escolha por servidor. Nao permite, no mesmo
  servidor, ter alguns schedules executando legado (porque o cliente
  ainda nao foi rolado para alguns usuarios) e outros server-first.
  O modelo hibrido por execucao e mais flexivel.

### Opcao D: Hibrido por schedule (`schedule.serverFirst = true`)

- Cada schedule armazena se deve ser server-first ou nao.
- **Rejeitada parcialmente**: nao e o disparo (`local` vs
  `remoteCommand`) que define server-first. E a origem da chamada. Um
  mesmo schedule pode rodar via timer (origem `local`) e via comando
  manual (origem `remoteCommand`) e cada execucao tera comportamento
  apropriado. Forcar a decisao no schedule reduz flexibilidade sem
  ganho.

## Notas de implementacao

- Adicionar `enum ExecutionOrigin { local, remoteCommand }` em
  `lib/domain/entities/` ou `lib/application/services/`.
- `SchedulerService.executeNow(scheduleId, {ExecutionOrigin origin =
ExecutionOrigin.local})`.
- `_checkSchedules` chama com `origin: ExecutionOrigin.local`.
- `ScheduleMessageHandler._handleExecuteSchedule` chama com
  `origin: ExecutionOrigin.remoteCommand`.
- `IDestinationOrchestrator` recebe `origin` e:
  - `local`: comportamento atual (upload para destinos finais).
  - `remoteCommand`: pula upload, apenas registra que artefato esta em
    staging.
- `BackupHistory` armazena `origin` para auditoria/metricas.
- `runId` continua no formato `<scheduleId>_<uuid>` (ja gerado pelo
  `RemoteExecutionRegistry` em M2.1); origem fica em campo separado, nao
  embutida no `runId`.
- Migracao gradual: introduzir o enum com default `local` em PR
  preparatorio, sem mudar comportamento. Em PR-3a o handler remoto
  passa a usar `remoteCommand` e o orchestrator passa a respeitar.
