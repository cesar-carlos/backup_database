# Plano de Melhorias SQL Server - Performance e Confiabilidade (2026-02-21)

## Objetivo

Evoluir o fluxo de backup SQL Server para:

- aumentar seguranca operacional;
- reduzir risco de backup "falso positivo";
- melhorar throughput e previsibilidade de tempo;
- elevar cobertura de testes e observabilidade.

## Escopo principal

### Fase 0 - Baseline e Métricas (prioridade crítica) ✅ CONCLUÍDA

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
- [x] SybaseBackupService atualizado para registrar métricas (backup/verify/total duration, BackupMetrics, BackupFlags).
- [x] PostgresBackupService atualizado para registrar métricas (backupDuration, verifyDuration, totalDuration, BackupMetrics e BackupFlags no BackupExecutionResult).
- [x] Relatórios p50/p95 implementados no MetricsAnalysisService (BackupMetricsPercentiles e percentilesByType no BackupMetricsReport; p50/p95 de duração, tamanho e velocidade por tipo).

### Observações

O SqlServerBackupService foi atualizado para:
- Medir duração de backup e verificação separadamente
- Criar BackupMetrics entity com todas as métricas relevantes (totalDuration, backupDuration, verifyDuration, backupSizeBytes, backupSpeedMbPerSec, backupType, flags)
- Incluir BackupMetrics no BackupExecutionResult retornado

O SybaseBackupService já registra BackupMetrics (backupDuration, verifyDuration, totalDuration, flags). Opcional: conferir se verifyDuration usa o mesmo stopwatch da verificação (evitar Stopwatch() novo).

O PostgresBackupService foi atualizado para: medir backupDuration (stopwatch do execute) e verifyDuration (stopwatch na verificação); construir BackupMetrics com _buildPostgresMetrics e incluir em todos os BackupExecutionResult (incl. backup log vazio).

O MetricsAnalysisService gera relatórios com métricas por tipo e percentis p50/p95 (duração, tamanho, velocidade) em BackupMetricsReport.percentilesByType (BackupMetricsPercentiles por BackupType).

### Próximos passos

1. ~~(Opcional) Consumir percentilesByType na UI~~ Feito: Dashboard exibe card "Métricas de performance (p50/p95)" com tabela por tipo de backup (P50/P95 duração, tamanho, velocidade); dados dos últimos 30 dias.
2. Fase 7 (criptografia) e Fase 8 (testes) conforme prioridade.

## Status Atual (revalidado no código em 2026-02-26; Fase 0 concluída)

### Concluidas

- Fase 0 (Métricas e baseline) - BackupMetrics em SqlServer, Sybase e Postgres; MetricsAnalysisService com generateReport e percentilesByType (p50/p95 por tipo).
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

- Nenhum (Fase 0 concluída).

### Pendentes

- Fase 7 - Criptografia de backup (não iniciada).
- Fase 8 - Testes unitários pendentes (parcial).
