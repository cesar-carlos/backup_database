# Plano de Melhorias SQL Server - Performance e Confiabilidade (2026-02-21)

## Objetivo

Evoluir o fluxo de backup SQL Server para:

- aumentar seguranca operacional;
- reduzir risco de backup "falso positivo";
- melhorar throughput e previsibilidade de tempo;
- elevar cobertura de testes e observabilidade.

## Escopo principal

- `lib/infrastructure/external/process/sql_server_backup_service.dart`
- `lib/infrastructure/external/process/process_service.dart`
- `lib/presentation/widgets/sql_server/sql_server_config_dialog.dart`
- `lib/presentation/widgets/schedules/schedule_dialog.dart`
- `lib/domain/entities/schedule.dart`
- `lib/application/services/backup_orchestrator_service.dart`
- `lib/application/services/scheduler_service.dart`

---

## Fase 0 - Baseline e Metricas (prioridade critica)

### Meta

Criar uma linha de base para comparar ganhos de desempenho e estabilidade.

### Entregas

- [ ] Instrumentar metricas por backup:
  - tempo total;
  - tempo de backup bruto;
  - tempo de `VERIFYONLY`;
  - taxa MB/s media;
  - tamanho final;
  - tipo (`full`, `differential`, `log`);
  - flags usadas (`checksum`, `copy_only`, etc.).
- [ ] Registrar motivo de falha normalizado (timeout, erro SQL, arquivo inexistente, arquivo zero bytes, verify fail).
- [ ] Criar relatorio simples em log consolidando p50/p95 por tipo de backup.

### Criterio de aceite

- [ ] Cada execucao de backup gera metricas minimas para comparacao futura.
- [ ] E possivel identificar os 3 principais motivos de falha por periodo.

---

## Fase 1 - Seguranca de credenciais e logs (prioridade critica)

### Meta

Eliminar exposicao de senha e reduzir risco em auditoria/log.

### Entregas

- [ ] Remover `-P <senha>` da linha de comando do `sqlcmd`.
- [ ] Passar senha via variavel de ambiente `SQLCMDPASSWORD`.
- [ ] Implementar redacao de argumentos sensiveis no `ProcessService` ao logar comando.
- [ ] Revisar logs para nao imprimir credenciais em mensagens de erro.

### Criterio de aceite

- [ ] Nenhum log contem senha em texto plano.
- [ ] Fluxo com autenticacao SQL Server continua funcional.
- [ ] Fluxo com autenticacao Windows (`-E`) permanece funcional.

### Risco e mitigacao

- Risco: quebra de autenticacao em ambientes especificos.
  - Mitigacao: teste de regressao com SQL Auth e Windows Auth antes de merge.

---

## Fase 2 - Confiabilidade do resultado (prioridade critica)

### Meta

Reduzir "backup com sucesso" quando a validacao real deveria reprovar.

### Entregas

- [ ] Adicionar politica de verificacao:
  - `best_effort` (comportamento atual);
  - `strict` (falha o job se `VERIFYONLY` falhar);
  - `none` (sem verify).
- [ ] Expor politica no `ScheduleDialog`.
- [ ] Tornar `STOP_ON_ERROR` explicito no SQL para documentar intencao (apesar de default).
- [ ] Adicionar pre-check para backup de log:
  - validar recovery model (full/bulk_logged);
  - validar existencia de full backup base quando aplicavel.
- [ ] Escapar nome de banco para identificador SQL (`]` -> `]]`).

### Criterio de aceite

- [ ] Em modo `strict`, falha de verify marca backup como erro.
- [ ] Backup de log invalido falha com mensagem clara antes de executar `BACKUP LOG`.
- [ ] Nao ha regressao nos modos `full` e `differential`.

---

## Fase 3 - Performance de backup (prioridade alta)

### Meta

Permitir tuning controlado de throughput.

### Entregas

- [ ] Adicionar opcoes avancadas por agendamento:
  - `compression` (on/off);
  - `maxTransferSize` (multiplo de 64KB);
  - `bufferCount` (com validacao para evitar OOM);
  - `blockSize` (opcional, uso avancado);
  - `statsPercent` configuravel.
- [ ] Adicionar validacoes e guard rails:
  - limites min/max seguros;
  - mensagens explicitas quando configuracao for arriscada.
- [ ] Implementar fallback automatico para valores padrao quando tuning for invalido.

### Criterio de aceite

- [ ] Opcoes avancadas sao opcionais e nao quebram config existente.
- [ ] Com tuning habilitado, metricas de Fase 0 mostram ganho em cenarios I/O-bound.

### Risco e mitigacao

- Risco: combinacao ruim de `BUFFERCOUNT` e `MAXTRANSFERSIZE` causar consumo excessivo de memoria.
  - Mitigacao: limite conservador por default + validacao forte na UI.

---

## Fase 4 - Paralelismo de dispositivos e resiliencia de midia (prioridade alta)

### Meta

Aumentar throughput e disponibilidade de midia.

### Entregas

- [ ] Suportar backup striping (`TO DISK = ..., DISK = ...`) com 2-4 arquivos.
- [ ] Definir estrategia de nomenclatura para stripes (`_part01`, `_part02`, ...).
- [ ] Suportar restore verify em conjuntos multi-arquivo.
- [ ] (Opcional enterprise) Planejar suporte futuro a mirrored media sets.

### Criterio de aceite

- [ ] Backup em multiplos arquivos funciona em full/differential/log.
- [ ] Verificacao e validacao de arquivos consideram todos os stripes.

---

## Fase 5 - UX e autenticacao (prioridade media)

### Meta

Alinhar UI com capacidades reais do backend.

### Entregas

- [ ] Adicionar seletor de autenticacao no dialog:
  - SQL Server Auth;
  - Windows Auth.
- [ ] Em Windows Auth, remover obrigatoriedade de usuario/senha.
- [ ] Ajustar fluxo de teste de conexao/listagem de bancos para ambos os modos.

### Criterio de aceite

- [ ] Usuario consegue salvar e testar conexao com `-E` sem hacks.
- [ ] Mensagens de validacao ficam coerentes com o modo escolhido.

---

## Fase 6 - Controle operacional (prioridade media)

### Meta

Melhorar governanca de execucao e previsibilidade.

### Entregas

- [ ] Tornar timeout de backup/verify configuravel por agendamento ou perfil.
- [ ] Implementar cancelamento efetivo do processo em execucao (nao apenas cooperativo).
- [ ] Adicionar preflight de armazenamento:
  - teste de permissao de escrita;
  - validacao de espaco livre minimo.

### Criterio de aceite

- [ ] Cancelar backup interrompe processo de fato.
- [ ] Timeouts podem ser ajustados sem alterar codigo.

---

## Fase 7 - Criptografia de backup (prioridade media)

### Meta

Elevar protecao de dados em repouso no arquivo de backup.

### Entregas

- [ ] Adicionar suporte opcional a `WITH ENCRYPTION`.
- [ ] Definir modelo de chave/certificado suportado.
- [ ] Criar validacao e mensagem de erro quando certificado/chave nao estiver disponivel.
- [ ] Documentar runbook de backup/restore de certificados.

### Criterio de aceite

- [ ] Backup criptografado e restauravel em ambiente que possua o certificado/chave.
- [ ] Falhas de configuracao retornam erro acionavel (sem erro generico).

---

## Fase 8 - Testes e gate de qualidade (prioridade critica)

### Meta

Fechar riscos de regressao com cobertura automatizada.

### Entregas

- [ ] Testes unitarios `SqlServerBackupService`:
  - parsing de erro (`Msg/Level`, `sqlcmd: error`);
  - modo verify `best_effort` vs `strict`;
  - `truncateLog` com e sem `COPY_ONLY`;
  - geracao de SQL com opcoes avancadas;
  - validacao de arquivo nao criado / zero bytes.
- [ ] Testes de seguranca:
  - assert de redacao de senha em logs;
  - assert de uso de `SQLCMDPASSWORD`.
- [ ] Testes de UI:
  - alternancia SQL Auth / Windows Auth;
  - validacoes coerentes por modo.

### Criterio de aceite

- [ ] Cobertura minima definida para modulo SQL Server.
- [ ] Sem regressao de comportamento atual nos cenarios legados.

---

## Ordem recomendada de execucao

1. Fase 0
2. Fase 1
3. Fase 2
4. Fase 8 (parcial, junto com Fases 1 e 2)
5. Fase 3
6. Fase 4
7. Fase 5
8. Fase 6
9. Fase 7
10. Fase 8 (gate final completo)

---

## Roadmap sugerido (sprints)

### Sprint 1 (seguranca + confiabilidade minima)

- Fase 0
- Fase 1
- Fase 2 (sem UI avancada)
- Fase 8 parcial

### Sprint 2 (performance)

- Fase 3
- Fase 4 (striping baseline)
- Fase 8 parcial

### Sprint 3 (operacao + UX + criptografia)

- Fase 5
- Fase 6
- Fase 7
- Fase 8 final

---

## Dependencias externas e observacoes

- Alguns recursos (ex: mirrored media sets) dependem de edicao/licenciamento do SQL Server.
- Opcoes de tuning (`BUFFERCOUNT`, `MAXTRANSFERSIZE`) exigem validacao conservadora para evitar OOM.
- Criptografia requer governanca de certificados/chaves fora do aplicativo.

---

## Referencias oficiais usadas para este plano

- BACKUP (T-SQL): https://learn.microsoft.com/en-us/sql/t-sql/statements/backup-transact-sql?view=sql-server-ver17
- sqlcmd utility: https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-utility?view=sql-server-ver17
- RESTORE VERIFYONLY: https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-verifyonly-transact-sql?view=sql-server-ver17
- Backup compression: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-compression-sql-server?view=sql-server-ver17
- Copy-only backups: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/copy-only-backups-sql-server?view=sql-server-ver17
- Backup encryption: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-encryption?view=sql-server-ver17
- Backup devices: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/backup-devices-sql-server?view=sql-server-ver17
- Possiveis erros de midia/checksum: https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/possible-media-errors-during-backup-and-restore-sql-server?view=sql-server-ver17

