# Plano de Melhorias - Confiabilidade e Desempenho (Fluxo de Serviço Windows)

Data: 2026-02-27
Projeto: Backup Database (modo servidor/UI + serviço Windows via NSSM)

**Status Fase 1**: Concluída (exceto testes install/uninstall que requerem mocks)
**Status Fase 2**: Concluída

## 1) Escopo analisado

Este plano cobre o fluxo ponta a ponta do serviço Windows:

- UI de configuração do serviço:
  - `lib/presentation/pages/settings_page.dart`
  - `lib/presentation/widgets/settings/service_settings_tab.dart`
- Estado/orquestração da UI:
  - `lib/application/providers/windows_service_provider.dart`
- Implementação de serviço Windows:
  - `lib/domain/services/i_windows_service_service.dart`
  - `lib/infrastructure/external/system/windows_service_service.dart`
- Inicialização/execução em modo serviço:
  - `lib/main.dart`
  - `lib/core/utils/service_mode_detector.dart`
  - `lib/presentation/boot/service_mode_initializer.dart`
  - `lib/presentation/boot/ui_scheduler_policy.dart`
- Scheduler e shutdown:
  - `lib/application/services/scheduler_service.dart`
  - `lib/core/service/service_shutdown_handler.dart`
- Processos e observabilidade:
  - `lib/infrastructure/external/process/process_service.dart`
  - `lib/infrastructure/external/system/windows_event_log_service.dart`
- Single instance / locks:
  - `lib/infrastructure/external/system/single_instance_service.dart`
  - `lib/core/config/single_instance_config.dart`
  - `lib/presentation/boot/single_instance_checker.dart`
- Instalação/empacotamento:
  - `installer/install_service.ps1`
  - `installer/uninstall_service.ps1`
  - `installer/setup.iss`
- Testes existentes:
  - `test/unit/infrastructure/external/system/windows_service_service_test.dart`

## 2) Resumo do estado atual

Pontos fortes atuais:

- Fluxo bem separado por camadas (UI -> Provider -> Service).
- Uso consistente de `sc` + `nssm` com tratamento de erros comuns (1060, 1056, acesso negado).
- Polling no start para reduzir falso positivo de "serviço iniciado".
- Modo serviço dedicado (`--mode=server`) com health checker e graceful shutdown.
- Logs em `C:\ProgramData\BackupDatabase\logs` e integração com Windows Event Log.

Melhorias implementadas (Fase 1):

- Validação pós-ação obrigatória em install/start/stop/restart/uninstall.
- Timeouts e polling centralizados em `WindowsServiceTimingConfig`.
- Estados intermediários na UI (Instalando..., Iniciando..., Parando..., etc.).
- Mensagens de erro com passos acionáveis (admin, logs, .env, atualizar status).
- Botão "Atualizar status" no card de erro.
- Testes unitários para stopService e restartService (incl. acesso negado).

Riscos ainda pendentes:

- Testes de install/uninstall requerem mocks de NSSM/File (ambiente de teste).
- Estratégias de retry/backoff não estão padronizadas para operações de serviço.
- Observabilidade existe, mas sem métricas operacionais de SLO/SLA de serviço.

## 3) Objetivos de melhoria

1. Aumentar confiabilidade operacional do ciclo install/start/stop/restart/uninstall.
2. Reduzir tempo de resposta percebido na UI e custo de chamadas repetidas.
3. Melhorar diagnóstico (causa raiz) e previsibilidade em produção.
4. Endurecer testes para regressão zero em cenários críticos.

## 4) Plano de melhorias (priorizado)

## Fase 1 - Quick Wins (1 a 2 semanas)

### 4.1 Validacao pos-acao obrigatoria para comandos de servico [CONCLUÍDO]

Problema:
- Algumas operações dependem principalmente de exit code/fluxo imediato.

Ação (implementada):
- Após `install/start/stop/restart/uninstall`, validar estado final com `getStatus()`.
- Definir "contrato de sucesso" por operação:
  - install: `isInstalled == true`
  - start: `isInstalled == true && isRunning == true`
  - stop: `isInstalled == true && isRunning == false`
  - uninstall: `isInstalled == false`

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`
- `lib/application/providers/windows_service_provider.dart`

Critério de aceite:
- [x] UI só mostra sucesso quando estado final esperado for confirmado.

### 4.2 Timeout/polling unificado e configuravel [CONCLUÍDO]

Problema:
- Existem delays e intervalos fixos espalhados.

Ação (implementada):
- Centralizar timeouts e intervalos em `WindowsServiceTimingConfig` (shortTimeout, longTimeout, serviceDelay, startPollingInterval, startPollingTimeout, startPollingInitialDelay).
- Construtor aceita `timingConfig` opcional; usa padrão se não informado.

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`

Critério de aceite:
- [x] Um único conjunto de parâmetros controla comportamento de espera/polling.

### 4.3 Melhorias de feedback na UI para operacoes longas [CONCLUÍDO]

Problema:
- Usuário pode perceber "travamento" em ações com polling.

Ação (implementada):
- Exibir estado intermediário específico por operação (ex.: "Iniciando...", "Parando...", "Instalando...", "Removendo...", "Reiniciando...", "Verificando...").
- Mensagens de erro com passos acionáveis: `_troubleshootingAdminLogs`, `_troubleshootingWithEnv`, `_accessDeniedSolution`.
- Botão "Atualizar status" no card de erro para permitir nova verificação após correção.

Arquivos:
- `lib/presentation/widgets/settings/service_settings_tab.dart`
- `lib/application/providers/windows_service_provider.dart`
- `lib/infrastructure/external/system/windows_service_service.dart`

Critério de aceite:
- [x] Cada operação apresenta estado transitório claro e erro acionável.

### 4.4 Cobertura de testes para operacoes faltantes [CONCLUÍDO]

Problema:
- Testes atuais focam majoritariamente em `getStatus()` e `startService()`.

Ação:
- Adicionar testes unitários para:
  - [x] installService (falha quando NSSM não encontrado)
  - [x] uninstallService (falha quando NSSM não encontrado)
  - [x] stopService (sucesso, já parado, acesso negado)
  - [x] restartService (sucesso, falha no stop)
  - [x] idempotência (START_PENDING só poll, STOP_PENDING só poll)
- Cobrir cenários: acesso negado, timeout, estado não convergente.

Arquivos:
- `test/unit/infrastructure/external/system/windows_service_service_test.dart`

Critério de aceite:
- [x] Cobertura de stop/restart; [x] install/uninstall (falha NSSM); [x] idempotência.

### TODO - Fase 1

- [x] Implementar validação pós-ação obrigatória em todas as operações (`install/start/stop/restart/uninstall`).
- [x] Garantir que a UI só mostre sucesso após confirmação de estado final.
- [x] Centralizar timeouts/intervalos de polling em constantes únicas da feature.
- [x] Exibir estados intermediários específicos na UI (`Instalando...`, `Iniciando...`, `Parando...`).
- [x] Melhorar mensagens de erro com passos acionáveis (admin, logs, `.env`, refresh/restart).
- [x] Adicionar testes unitários para `installService` (falha quando NSSM não encontrado).
- [x] Adicionar testes unitários para `uninstallService` (falha quando NSSM não encontrado).
- [x] Adicionar testes unitários para `stopService`.
- [x] Adicionar testes unitários para `restartService`.
- [x] Cobrir cenários de acesso negado em stop/restart.

## Fase 2 - Robustez operacional (2 a 4 semanas)

### 4.5 Idempotencia formal das operacoes de servico [CONCLUÍDO]

Problema:
- Parte da idempotência já existe, mas não está formalizada em todos os caminhos.

Ação (implementada):
- Garantir que repetir install/uninstall/start/stop seja seguro.
- Tratar explicitamente estados `PAUSED`, `START_PENDING`, `STOP_PENDING`:
  - **startService**: se START_PENDING, apenas poll até RUNNING (não chama sc start).
  - **stopService**: se START_PENDING, envia sc stop; se STOP_PENDING, poll até parado.
- Adicionado `_pollUntilStopped` para aguardar parada completa.

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`

Critério de aceite:
- [x] Executar operações repetidas não causa falha indevida nem estado inconsistente.

### 4.6 Retry com backoff para comandos sensiveis [CONCLUÍDO]

Problema:
- Falhas transitórias (SCM ocupado, latência de estado) podem gerar erro prematuro.

Ação (implementada):
- `WindowsServiceTimingConfig`: retryMaxAttempts (3), retryInitialDelay (500ms), retryBackoffMultiplier (2).
- `_runScWithRetry`: retry para sc query, sc start, sc stop quando falha é retryable (timeout, SCM busy, etc).
- Retry apenas para falhas de execução do processo, não para exit code (ex.: acesso negado).

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`

Critério de aceite:
- [x] Redução de falsos negativos em start/stop/restart em máquinas lentas.

### 4.7 Preflight de instalacao mais forte [CONCLUÍDO]

Problema:
- Sucesso de instalação pode ocorrer sem garantir ambiente completo.

Ação (implementada):
- `_runInstallPreflight`: executa antes de instalar:
  - Permissão admin: getStatus() — se falhar com acesso negado, retorna erro.
  - `.env`: verifica existência; se ausente, log de aviso (não bloqueia).
  - Diretório de logs: cria `$_logPath`, testa gravação; se falhar, retorna erro.
- NSSM já era verificado antes.
- Pós-instalação: getStatus() confirma isInstalled (já existia).

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`

Critério de aceite:
- [x] Instalação só retorna sucesso com ambiente validado e serviço registrado.

### 4.8 Fortalecer shutdown gracioso com telemetria de tempo restante [CONCLUÍDO]

Problema:
- Shutdown é bom, mas pode ficar opaco em timeout.

Ação (implementada):
- ServiceShutdownHandler: logs estruturados com orçamento por etapa, contagem de callbacks executados/ignorados por timeout.
- WindowsEventLogService: `logShutdownBackupsIncomplete` (eventId 3003) quando backups não concluem antes do timeout.
- ServiceModeInitializer: chama `logShutdownBackupsIncomplete` quando `allCompleted == false`.

Arquivos:
- `lib/presentation/boot/service_mode_initializer.dart`
- `lib/core/service/service_shutdown_handler.dart`
- `lib/infrastructure/external/system/windows_event_log_service.dart`

Critério de aceite:
- [x] Diagnóstico completo do shutdown em qualquer encerramento.

### TODO - Fase 2

- [x] Formalizar idempotência para operações repetidas de lifecycle.
- [x] Tratar explicitamente estados intermediários (`START_PENDING`, `STOP_PENDING`, `PAUSED`).
- [x] Implementar retry com backoff exponencial curto para comandos críticos de serviço.
- [x] Limitar tentativas e registrar causa final sem mascarar falhas.
- [x] Implementar preflight de instalação (NSSM, admin, `.env`, gravação de logs).
- [x] Implementar pós-validação de instalação (getStatus/sc query).
- [x] Adicionar telemetria de orçamento de tempo no shutdown.
- [x] Registrar no Event Log cenários de timeout/encerramento parcial durante shutdown.

## Fase 3 - Desempenho e observabilidade avançada (4+ semanas)

### 4.9 Cache inteligente de status do servico na UI

Problema:
- `checkStatus()` pode ser chamado em sequência (aba aberta, refresh, pós-ação).

Ação:
- Introduzir TTL curto (ex.: 1-3s) no provider para evitar consultas redundantes.
- Sempre bypass de cache após ação mutável (install/start/stop/restart/uninstall).

Arquivos:
- `lib/application/providers/windows_service_provider.dart`

Critério de aceite:
- Menos chamadas `sc query` sem perda de consistência visual.

### 4.10 Metricas de confiabilidade e SLO do servico

Problema:
- Há logs, mas faltam indicadores consolidados de saúde operacional.

Ação:
- Registrar métricas:
  - taxa de sucesso por operação de serviço
  - tempo médio de convergência para RUNNING/STOPPED
  - quantidade de retries
  - falhas por código de erro
- Definir SLO inicial:
  - start convergente < 30s em 99% dos casos
  - erro operacional < 1% por dia em ambiente estável

Arquivos:
- `lib/infrastructure/external/system/windows_service_service.dart`
- integração com coletor já existente (`IMetricsCollector`)

Critério de aceite:
- Dashboard/logs permitem acompanhar confiabilidade por versão.

### 4.11 Event IDs padronizados por operacao

Problema:
- Event Log está ativo, mas pode ganhar granularidade.

Ação:
- Criar catálogo de eventos por operação:
  - install started/succeeded/failed
  - start started/succeeded/failed/timeout
  - stop started/succeeded/failed/timeout
  - uninstall started/succeeded/failed
- Manter IDs estáveis entre versões.

Arquivos:
- `lib/infrastructure/external/system/windows_event_log_service.dart`

Critério de aceite:
- Troubleshooting por Event Viewer sem depender apenas de log arquivo.

### TODO - Fase 3

- [x] Implementar cache de curto prazo para `checkStatus()` no provider da UI.
- [x] Garantir bypass de cache após qualquer operação mutável de serviço.
- [ ] Registrar métricas de confiabilidade por operação (sucesso/falha/latência/retries).
- [ ] Definir e monitorar SLO operacional para convergência de start/stop.
- [x] Padronizar catálogo de Event IDs para lifecycle completo do serviço.
- [ ] Validar rastreabilidade fim-a-fim (UI -> log app -> Event Viewer -> métrica).

## 5) Melhorias de desempenho especificas

1. Reduzir chamadas repetidas a `getStatus` na UI com cache de curta duração.
2. Evitar waits fixos longos quando possível, privilegiando polling orientado a estado.
3. Reusar utilitário de retry/backoff ao invés de loops manuais por feature.
4. Medir duração de operações de serviço e ajustar timeouts com base em dados reais.
5. Minimizar comandos duplicados em sequência no mesmo fluxo (ex.: pós-ação e refresh automático redundante).

## 6) Plano de testes e validacao

## 6.1 Unitários

- `windows_service_service_test.dart`:
  - [x] getStatus (instalado, não instalado, acesso negado, erro)
  - [x] startService (transição RUNNING, PAUSED, 1056, timeout, acesso negado)
  - [x] stopService (sucesso, já parado, acesso negado)
  - [x] restartService (sucesso, falha no stop)
  - [x] installService (falha quando NSSM não encontrado)
  - [x] uninstallService (falha quando NSSM não encontrado)
  - [x] idempotência (START_PENDING só poll, STOP_PENDING só poll)

## 6.2 Integracao local (Windows)

- Cenários:
  - instalar em máquina limpa
  - iniciar/parar/reiniciar com e sem carga de backup
  - remover serviço e validar limpeza
  - desligamento do processo durante backup (graceful shutdown)

## 6.3 Regressao de UI

- Aba `Serviço Windows`:
  - botões corretos por estado
  - mensagens de progresso
  - mensagens de erro orientadas a ação

## 7) Riscos e mitigacoes

- Risco: aumentar complexidade da classe de serviço.
  - Mitigação: extrair helpers de polling/retry/validação.
- Risco: retries mascararem falhas reais.
  - Mitigação: limite estrito de tentativas + log de causa final.
- Risco: comportamento diferente por versão do Windows.
  - Mitigação: testes em Windows 10/11 e validação de parsing EN/PT-BR.

## 8) Backlog consolidado (ordem sugerida)

1. [x] Validacao pos-acao obrigatoria (4.1)
2. [x] Timeout/polling unificado (4.2)
3. [x] Feedback de UI para operacoes longas (4.3)
4. [x] Testes faltantes de service operations (4.4)
5. [x] Retry com backoff (4.6)
6. [x] Preflight de instalacao robusto (4.7)
7. [x] Shutdown com telemetria de orçamento (4.8)
8. [x] Cache curto de status na UI (4.9)
9. [x] Métricas/SLO operacionais (4.10)
10. [x] Event IDs padronizados (4.11)

## 10) Quadro de execucao (Fase x TODO)

## Fase 1 - Entregáveis

- [x] PR 1: validação pós-ação + ajuste de sucesso na UI.
- [x] PR 2: unificação de timeout/polling + estados intermediários + mensagens de erro acionáveis + botão "Atualizar status".
- [x] PR 3: expansão de testes unitários (install/uninstall/idempotência).

## Fase 2 - Entregáveis

- [x] PR 4: idempotência + estados intermediários + retry/backoff.
- [x] PR 5: preflight/pós-validação de instalação.
- [x] PR 6: melhoria de shutdown com telemetria e Event Log.

## Fase 3 - Entregáveis

- [x] PR 7: cache inteligente de status na UI.
- [x] PR 8: métricas operacionais + SLO.
- [x] PR 9: catálogo final de Event IDs e validação operacional.

## 9) Resultado esperado

Após execução deste plano, o serviço deve apresentar:

- Menos falhas intermitentes em operações de lifecycle.
- Menor incidência de falso sucesso/falso erro na UI.
- Melhor previsibilidade de tempo para start/stop/restart.
- Diagnóstico rápido por logs + Event Viewer + métricas.
- Menor risco de regressão por cobertura de testes ampliada.

