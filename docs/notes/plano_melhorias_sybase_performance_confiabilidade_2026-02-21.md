# Plano de Melhorias Sybase - Performance e Confiabilidade (2026-02-21)

## Objetivo

Evoluir o fluxo de backup Sybase SQL Anywhere para:

- reduzir risco de falso positivo de backup com sucesso;
- aumentar previsibilidade de restore;
- melhorar desempenho em cenarios de alta escrita;
- remover inconsistencias entre documentacao, UI e backend.

## Escopo principal

- `docs/analise_implementacao_sybase.md`
- `lib/infrastructure/external/process/sybase_backup_service.dart`
- `lib/infrastructure/external/process/process_service.dart`
- `lib/infrastructure/external/process/tool_verification_service.dart`
- `lib/presentation/widgets/schedules/schedule_dialog.dart`
- `lib/application/services/backup_orchestrator_service.dart`
- `lib/application/services/scheduler_service.dart`

---

## Diagnostico atual (doc x codigo)

- [ ] Documento diz que Differential nao aparece na UI para Sybase, mas a UI atualmente exibe Differential.
- [ ] Documento cita verificacao apenas com `dbverify`, mas o codigo ja tenta `dbvalid` (arquivo `.db`) e faz fallback para `dbverify`.
- [ ] Documento descreve backup de log como arquivo direto no output; codigo usa pasta por execucao e resolve arquivo gerado internamente.
- [ ] Documento atribui envio a destinos ao Orchestrator; no fluxo atual, upload e controlado no Scheduler.
- [ ] Documento esta com data antiga (Dez/2024) e nao cobre mudancas recentes.

---

## Fase 0 - Baseline operacional e aderencia documental (prioridade critica)

### Meta

Ter linha de base de comportamento atual e alinhar a documentacao ao codigo real.

### Entregas

- [ ] Atualizar `docs/analise_implementacao_sybase.md` com:
  - suporte real da UI;
  - fluxo real de verificacao (`dbvalid` + fallback `dbverify`);
  - estrutura real de artefatos de log backup;
  - responsabilidades corretas entre Orchestrator e Scheduler.
- [ ] Registrar metricas minimas por execucao:
  - tempo total;
  - metodo efetivo (`dbisql` ou `dbbackup`);
  - estrategia de conexao vencedora;
  - tipo efetivo de backup;
  - tamanho final.

### Criterio de aceite

- [ ] Documentacao bate com implementacao atual.
- [ ] Logs permitem identificar degradacao por tipo de backup e por estrategia.

---

## Fase 1 - Seguranca de credenciais e higiene de logs (prioridade critica)

### Meta

Eliminar exposicao de senha em logs e mensagens de erro.

### Entregas

- [ ] Aplicar redacao de argumentos sensiveis no `ProcessService` (`PWD=`, tokens e afins).
- [ ] Evitar log de connection string completa em `SybaseBackupService`.
- [ ] Revisar mensagens de falha para manter contexto sem vazar segredo.

### Criterio de aceite

- [ ] Nenhum log contem senha em texto plano.
- [ ] Fluxos de backup e teste de conexao continuam operacionais.

---

## Fase 2 - Correcao funcional de tipo de backup (prioridade critica)

### Meta

Remover ambiguidade sobre Differential em Sybase e evitar codigo morto.

### Entregas

- [ ] Definir regra unica para Sybase:
  - opcao A: esconder Differential na UI;
  - opcao B: manter visivel, mas renomear como "Incremental log" com semantica explicita.
- [ ] Ajustar `schedule_dialog.dart` para refletir a regra escolhida.
- [ ] Simplificar `SybaseBackupService` removendo branches inalcancaveis de Differential apos normalizacao de tipo.
- [ ] Atualizar descricoes de tipo de backup para Sybase no formulario.

### Criterio de aceite

- [ ] Usuario nao recebe promessa de Differential "real" quando nao existe.
- [ ] Codigo nao possui caminho contraditorio para Differential.

---

## Fase 3 - Confiabilidade de verificacao e restauracao (prioridade critica)

### Meta

Aumentar confiabilidade do resultado final (backup restauravel, nao apenas "arquivo criado").

### Entregas

- [ ] Introduzir politica de verificacao por agendamento:
  - `none`;
  - `best_effort` (atual);
  - `strict` (falha job quando validacao falhar).
- [ ] Manter preferencia por validacao offline com `dbvalid` em copia `.db`.
- [ ] Adicionar preflight para backup de log:
  - base full conhecida;
  - ultimo full nao expirado;
  - alerta quando cadeia de logs estiver quebrada.
- [ ] Adicionar job automatizado de "restore drill":
  - restaurar full + logs em ambiente de teste;
  - validar com `dbvalid`;
  - publicar resultado.
- [ ] Persistir metadados de cadeia (full base + logs aplicaveis).

### Criterio de aceite

- [ ] Em modo `strict`, falha de validacao marca backup como erro.
- [ ] Existe evidencia automatizada de restore fim-a-fim periodico.

---

## Fase 4 - Hardening de ferramentas e preflight (prioridade alta)

### Meta

Evitar falhas por ferramentas incompletas ou descoberta incorreta de executaveis.

### Entregas

- [ ] Incluir `dbvalid` no `ToolVerificationService` (opcional/recomendado) e no resolver de caminhos do `ProcessService`.
- [ ] Expor estado das ferramentas na UI (ok, warning, faltando).
- [ ] Validar permissao de escrita no destino antes do backup.
- [ ] Validar espaco livre minimo com margem configuravel.

### Criterio de aceite

- [ ] Preflight barra execucao quando ambiente nao atende requisitos minimos.
- [ ] `dbvalid` e localizado mesmo quando SQL Anywhere nao esta no PATH mas esta nos caminhos comuns.

---

## Fase 5 - Otimizacoes de desempenho do backup (prioridade alta)

### Meta

Permitir tuning controlado de desempenho conforme perfil de I/O.

### Entregas

- [ ] Expor opcoes avancadas de backup (com defaults seguros):
  - `WITH CHECKPOINT LOG {AUTO|COPY|NO COPY|RECOVER}` para backup por SQL;
  - modo server-side (`dbbackup -s`) quando aplicavel;
  - `AUTO TUNE WRITERS ON/OFF` (SQL image backup);
  - `dbbackup -b` (block-size) quando usar utilitario.
- [ ] Definir guard rails de configuracao com validacoes fortes.
- [ ] Persistir no historico as opcoes de tuning usadas em cada execucao.

### Criterio de aceite

- [ ] Configuracao padrao permanece retrocompativel.
- [ ] Em ambiente I/O-bound, metricas mostram ganho de throughput.

---

## Fase 6 - Cadeia de logs e retencao segura (prioridade alta)

### Meta

Diminuir risco de conflito/perda de logs e melhorar recuperacao.

### Entregas

- [ ] Revisar estrategia de log backup para suportar `RENAME` quando necessario (evitar colisao e sobrescrita).
- [ ] Implementar regras explicitas para `truncateLog` em cenarios com replicacao/mirroring.
- [ ] Bloquear operacoes perigosas em ambientes espelhados (ex.: evitar semantica equivalente a `-x/-xo` quando nao permitido).
- [ ] Definir politica de retencao orientada por restauracao (full + janela de logs consistente).

### Criterio de aceite

- [ ] Cadeia de logs fica auditavel e aplicavel em restore.
- [ ] Sem conflitos de nome/ordem de logs no repositorio de backup.

---

## Fase 7 - UX operacional e observabilidade (prioridade media)

### Meta

Melhorar clareza para operacao e suporte.

### Entregas

- [ ] Mostrar no historico:
  - tipo solicitado vs tipo efetivo;
  - ferramenta usada (`dbisql`/`dbbackup`);
  - modo de verificacao e resultado.
- [ ] Mensagens de erro com acao recomendada (PATH, permissao, conexao, cadeia de log).
- [ ] Painel de saude Sybase:
  - ultimo backup full/log;
  - estado de cadeia;
  - ultimo resultado de restore drill.

### Criterio de aceite

- [ ] Operador identifica rapidamente causa raiz sem inspecionar logs brutos.

---

## Fase 8 - Testes automatizados e gate de qualidade (prioridade critica)

### Meta

Fechar regressao em pontos criticos de confiabilidade.

### Entregas

- [ ] Testes unitarios para `SybaseBackupService`:
  - selecao de estrategia de conexao;
  - fallback `dbisql` -> `dbbackup`;
  - resolucao de arquivo de log;
  - validacao `dbvalid` e fallback `dbverify`;
  - modo `strict` vs `best_effort`.
- [ ] Testes unitarios para redacao de segredo em `ProcessService`.
- [ ] Testes de UI para tipos de backup Sybase no `ScheduleDialog`.
- [ ] Smoke test de restore drill em pipeline (ambiente controlado).

### Criterio de aceite

- [ ] Mudancas em backup Sybase exigem testes verdes no gate.

---

## Ordem recomendada de execucao

1. Fase 0
2. Fase 1
3. Fase 2
4. Fase 4
5. Fase 3
6. Fase 8 (parcial, junto de Fases 1-4)
7. Fase 5
8. Fase 6
9. Fase 7
10. Fase 8 (gate final completo)

---

## Referencias tecnicas (SQL Anywhere)

- SAP Help - Backup, Validation, and Recovery (SQL Anywhere 16): `https://help.sap.com/docs/SUPPORT_CONTENT/sqlany/3362971521.html`
- SQL Anywhere - Backup utility (dbbackup): `https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbadmin/dbbackup.html`
- SQL Anywhere - BACKUP statement: `https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbreference/backup-statement.html`
- SQL Anywhere - Validation utility (dbvalid): `https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbadmin/dbvalid.html`
- SQL Anywhere 16 - Scheduling Automatic Incremental Backups: `https://infocenter.sybase.com/help/topic/com.sybase.infocenter.dc01931.0233/doc/html/apr1369264142699.html`
- SQL Anywhere 16 - Scheduling Automatic Full Backups: `https://infocenter.sybase.com/help/topic/com.sybase.infocenter.dc01931.0233/doc/html/apr1369264563470.html`
- SQL Anywhere - Live backup: `https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbadmin/da-backup-dbs-4978684.html`
- SQL Anywhere - VSS integration: `https://infocenter.sybase.com/help/topic/com.sybase.help.sqlanywhere.12.0.1/dbadmin/da-backup-dbs-5615940.html`
