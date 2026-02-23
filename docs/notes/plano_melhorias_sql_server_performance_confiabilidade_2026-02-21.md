# Plano de Melhorias SQL Server - Performance e Confiabilidade (2026-02-21)

## Objetivo

Evoluir o fluxo de backup SQL Server para:

- aumentar seguranca operacional;
- reduzir risco de backup "falso positivo";
- melhorar throughput e previsibilidade de tempo;
- elevar cobertura de testes e observabilidade.

## Escopo principal

### Fase 0 - Baseline e Métricas (prioridade crítica) 🔄 EM ANDAMENTO

### Entregas

- [x] Cada execução de backup gera métricas mínimas para comparação futura (histórico com duração/tamanho/tipo e flags).
- [x] BackupMetrics entity criada.
- [x] BackupFlags entity criada.
- [x] BackupHistory entity atualizada com campo metrics opcional.
- [x] BackupHistoryTable atualizada com coluna metrics.
- [x] IMetricsAnalysisService interface criada.
- [x] MetricsAnalysisService implementado e registrado no DI.
- [x] Lint zerado para os novos componentes de métricas.
- [x] BackupExecutionResult atualizada com campo metrics opcional.
- [x] SqlServerBackupService atualizado para registrar métricas (backup/verify durations separados, BackupMetrics criado).
- [ ] SybaseBackupService atualizado para registrar métricas.
- [ ] PostgresBackupService atualizado para registrar métricas.
- [ ] Relatórios p50/p95 implementados no MetricsAnalysisService.

### Observações

O SqlServerBackupService foi atualizado para:
- Medir duração de backup e verificação separadamente
- Criar BackupMetrics entity com todas as métricas relevantes (totalDuration, backupDuration, verifyDuration, backupSizeBytes, backupSpeedMbPerSec, backupType, flags)
- Incluir BackupMetrics no BackupExecutionResult retornado

O MetricsAnalysisService foi criado e está funcional. Ele gera relatórios de métricas por tipo de backup, permitindo análise de performance p50/p95.

### Próximos passos

1. Integrar coleta de métricas no SybaseBackupService (track backup/verify durations, criar BackupMetrics).
2. Integrar coleta de métricas no PostgresBackupService (track backup/verify durations, criar BackupMetrics).
3. Implementar relatórios p50/p95 no MetricsAnalysisService.

## Status Atual (revalidado no código em 2026-02-21)

### Concluidas

- Fase 1 (Seguranca de credenciais e logs).
- Fase 2 (Confiabilidade do resultado - STOP_ON_ERROR explicito no SQL).
- Fase 3 (Performance de backup com opcoes avancadas).
- Fase 4 (Paralelismo de dispositivos - striping com SQL multi-disk, naming `_partNN`, verify multi-arquivo).
- Fase 5 (UX e autenticacao) no fluxo principal SQL Server.
- Fase 6 - Cancelamento efetivo de processos (ProcessService.cancelByTag implementado).
- Fase 6 (Controle operacional parcial):
  - Validação de armazenamento (espaço livre e permissão de escrita).
  - Fase 8 - Lint zerado, ProcessService com suporte a tag/cancelByTag.

### Em andamento

- Fase 0 (Métricas e baseline) - Infraestrutura de métricas criada, integração com serviços de backup pendente.

### Pendentes

- Fase 0 (Métricas e baseline) - integração de serviços de backup:
  - Modificar SqlServerBackupService para registrar métricas de forma consistente.
  - Modificar SybaseBackupService para registrar métricas.
  - Modificar PostgresBackupService para registrar métricas.
  - Criar relatórios p50/p95 por tipo de backup no MetricsAnalysisService.
- Fase 7 - Criptografia de backup (não iniciada).
- Fase 8 - Testes unitários pendentes (parcial).
