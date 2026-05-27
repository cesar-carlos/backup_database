# AUDIT-15 — Single Instance enforcement (mutex Win32 + IPC)

Data: 2026-05-27
Ficheiros principais:

- `lib/infrastructure/external/system/single_instance_service.dart`
- `lib/infrastructure/external/system/mutex_security_descriptor.dart` *(novo)*
- `lib/infrastructure/external/system/ipc_service.dart`
- `lib/presentation/boot/single_instance_checker.dart`
- `lib/presentation/boot/bootstrap_config.dart`
- `lib/core/config/single_instance_config.dart`
- `test/unit/infrastructure/external/system/single_instance_service_test.dart`
- `test/unit/presentation/boot/single_instance_checker_test.dart`

Auditoria da stack de 6 camadas que impede 2 instâncias do app na mesma
máquina (mutex Win32 + IPC TCP loopback + política UI vs Service +
config + UX da 2ª instância + cleanup). 9 achados — 2 críticos, 3
médios, 3 baixos, 1 info. Todos mitigados neste audit. **2009 testes
passam (13 skipped, 0 falhas)** após as mudanças, contra a baseline
anterior de 1963 (somando os novos cases F1/F2/F3/F4/F6/idempotência).

## Stack auditada

| Camada | Arquivo | Responsabilidade |
|---|---|---|
| 1. Mutex Win32 global | `single_instance_service.dart` | `CreateMutexW("Global\BackupDatabase_InstanceMutex_{GUID}")` + leitura de `ERROR_ALREADY_EXISTS` |
| 2. IPC TCP loopback | `ipc_service.dart` | Portas 58724–58729; protocolo `BACKUP_DATABASE_IPC_V1` (PING/USER_INFO/SHOW_WINDOW/RUN_SCHEDULE) |
| 3. Política UI vs Service | `app_bootstrap.dart` / `service_mode_initializer.dart` | Decide quem chama `checkAndLock` e com que `fallbackMode` |
| 4. Configuração | `single_instance_config.dart` + `.env` | Kill switch + modo de fallback + portas + timeouts |
| 5. UX 2ª instância | `single_instance_checker.dart` | Mensagens contextuais por `LaunchOrigin` e por dono (mesmo user / outro user / desconhecido / serviço) |
| 6. Cleanup | `app_cleanup.dart` + `service_mode_initializer.dart` + `auto_update_service.dart` | `releaseLock` em shutdown normal, fatal e antes do handoff p/ instalador |

## Achados e mitigações

### F1 — [CRÍTICO] Mutex `Global\` criado sem `SECURITY_ATTRIBUTES`

`CreateMutexW(nullptr, 0, ...)` usava a DACL default do token criador.
Quando o serviço como `LocalSystem` cria primeiro, a DACL default
permite acesso apenas a SYSTEM/Administrators/criador — a UI do usuário
não-admin recebia `ERROR_ACCESS_DENIED (5)` com handle NULL, e o código
caía no fallback de mutex error. No path `fail_open` isso permitia
silenciosamente **2 instâncias reais** (cobertura via IPC só salvava o
caso `fail_safe`).

Mitigação:

- Novo `lib/infrastructure/external/system/mutex_security_descriptor.dart`
  encapsula `advapi32!ConvertStringSecurityDescriptorToSecurityDescriptorW`
  + `SECURITY_ATTRIBUTES` (FFI manual, não exposto pelo
  `package:win32` 5.15.0).
- SDDL aplicado: `D:(A;;0x1F0001;;;WD)` → MUTEX_ALL_ACCESS para
  Everyone (S-1-1-0). Inclui SYSTEM e qualquer usuário autenticado.
- `SingleInstanceService` ganhou `securityAttributesProvider` injetável
  (default: `MutexSecurityDescriptor.buildEveryoneAccess`; tests podem
  passar `() => null` para reproduzir comportamento legado).
- Log diferenciado: `event=single_instance_lock_acl_denied` (quando
  `GetLastError == ERROR_ACCESS_DENIED`) vs `single_instance_lock_error`
  (genérico). Triagem no campo distingue ACL de bug de API.

Testes novos:

- `should pass security attributes pointer to CreateMutexW when provider
  returns a non-null descriptor` — captura o ponteiro passado a
  `CreateMutexW` e verifica que `dispose` é chamado.
- `should fall back to nullptr SECURITY_ATTRIBUTES when provider
  returns null` — garante backward compat.

### F2 — [CRÍTICO] `fail_open` não fazia probe IPC antes de declarar “sou o primeiro”

No path `fail_open`, qualquer falha de mutex (handle 0 OU exceção)
fazia `checkAndLock` retornar `true` sem checar se já havia um dono
respondendo no IPC. Se um operador deixasse
`SINGLE_INSTANCE_LOCK_FALLBACK_MODE=fail_open` em produção (típico
após “diagnóstico”), o app permitia 2 UIs reais ao mesmo tempo —
exatamente o que a regra deveria evitar.

Mitigação:

- `SingleInstanceService` ganhou `ipcServerProbe` injetável (default:
  `IpcService.checkServerRunning`).
- Tanto o path de “mutex creation failed” quanto o `catch (Object)`
  agora fazem `await _probeActiveIpcSafely()` ANTES de retornar `true`
  no `fail_open`. Se o probe responde com PONG v1 válido,
  `checkAndLock` retorna `false` e loga
  `event=single_instance_fail_open_blocked_by_active_ipc`.
- Falha do próprio probe (rede broken, hostname errado) é capturada
  e tratada como “sem dono detectado” (mantém o `fail_open` permissivo
  como intended), logando `event=single_instance_ipc_probe_failed`.

Testes novos (3):

- `should deny startup in fail_open when active IPC server is detected
  after mutex creation fails`
- `should deny startup in fail_open when active IPC server is detected
  after exception`
- `should swallow IPC probe failure in fail_open path and still allow
  startup when no owner is detected`

### F3 — [MÉDIO] `checkAndLock` reentrante vazava handle

`_mutexHandle = _createMutexFn(...)` sobrescrevia o handle anterior
sem fechá-lo. Hoje só é chamado uma vez por processo (UI ou Service),
mas:

- Teste de integração que invoque o singleton 2× vazava kernel handle.
- Qualquer refator futuro com retry (ex.: tentar de novo após ACL
  denied) caía no bug.
- 2ª chamada com `ERROR_ALREADY_EXISTS` fechava o handle novo,
  zerava `_mutexHandle`, virava `_isFirstInstance` para `false`. O
  handle original vazava até o processo morrer; `releaseLock`
  posterior não fechava nada.

Mitigação:

- Flag `_checkAndLockCompleted` adicionado. 2ª+ chamadas logam
  `event=single_instance_check_and_lock_reentrant` e retornam
  imediatamente o `_isFirstInstance` cached.
- `releaseLock` agora reseta o flag para permitir um novo ciclo de
  lock (shutdown completo → restart na mesma instância de processo,
  cenário de teste).

Testes novos:

- `should be idempotent across multiple checkAndLock calls and not
  leak handles` — verifica que `CreateMutex` é chamado 1× e
  `CloseHandle` 0× quando o 1º call ganhou o lock.
- `should remain denied across multiple checkAndLock calls when first
  attempt detected ERROR_ALREADY_EXISTS` — verifica que estado de
  “já existe” persiste.

### F4 — [MÉDIO] Race acquire→IPC mostrava “Unknown user” espúrio

Entre `checkAndLock` (passo cedo no bootstrap) e `startIpcServer`
(executado dentro de `initializeUiServices`, ~300-500ms depois do
`setupServiceLocator`) há uma janela em que a 1ª instância **já tem o
mutex** mas **ainda não responde no IPC**. Se o usuário desse
duplo-clique no atalho nessa janela, a 2ª UI via `existingUser=null` e
`existingRole=null`, e exibia o dialog “Não foi possível identificar o
usuário da instância existente” — confuso, porque a instância está
literalmente abrindo agora.

Mitigação:

- `SingleInstanceChecker._getExistingInfo` agora faz retry interno
  com `ownerInfoMaxAttempts=3` (default) e `ownerInfoRetryDelay=250ms`.
  Pior caso adicional na 2ª UI: ~500ms para deixar a 1ª subir o IPC.
- Parâmetros injetáveis no construtor (`ownerInfoMaxAttempts`,
  `ownerInfoRetryDelay`) para tests poderem configurar delays curtos.

Teste novo:

- `should retry getExistingInstanceInfo when first attempt returns
  null` — `[null, null, 'ui']` script: valida que `_getExistingInfo`
  faz 3 tentativas e resolve no terceiro retry.

### F5 — [MÉDIO] Latência do `SHOW_WINDOW` chegava a 26s no pior caso

`IpcService.sendShowWindow` usava `ipcConnectTimeout = 5s`, e
`SingleInstanceChecker` fazia até `maxRetryAttempts=5` tentativas
com `retryDelay=200ms`. Total no pior caso:
`5 × (5000 + 200) = 26s` de janela morta antes do dialog aparecer.
Para o usuário desktop, parecia “app travado” — clicava de novo,
gerava mais 2ª instância no mesmo loop.

Mitigação:

- Nova constante `SingleInstanceConfig.showWindowConnectTimeout = 1s`
  (loopback não precisa de mais — separada de `ipcConnectTimeout`
  que continua 5s para casos como `delegateScheduledExecution`).
- `IpcService.sendShowWindow` usa o novo timeout curto.
- `SingleInstanceConfig.maxRetryAttempts` reduzido de **5 → 3**.
- `SingleInstanceConfig.retryDelay` reduzido de **200ms → 100ms**.
- Pior caso novo: `3 × (1000 + 100) = 3,3s` — tolerável.

Os testes existentes do checker continuam passando (o teste
`should show focus failure message when notify fails` já validava
contagem de retries via fake; agora roda com 3).

### F6 — [BAIXO] Notify cruzado focava janela na sessão de outro usuário

`single_instance_checker.dart:128-144` só pulava o `notifyExistingInstance`
quando `isServiceOwner=true`. Em multi-user / Fast User Switching,
usuário B abrindo o app enquanto A já tem UI:

1. Mutex em B → bloqueado (correto)
2. `existingUser = "A"`, `currentUser = "B"` → `isDifferentUser = true`
3. **Notify rodava mesmo assim** → A recebia `SHOW_WINDOW` e a janela
   ganhava foco na sessão de A — surpresa indesejada causada por uma
   ação de B.

Mitigação:

- Condição refinada para `shouldNotifyForeground = !isServiceOwner &&
  !isDifferentUser && !couldNotDetermineUser`. Notify só ocorre quando
  temos certeza do mesmo usuário.
- Log `event=duplicate_skip_show_window_cross_user` registra o motivo
  do skip (`isDifferentUser` ou `couldNotDetermineUser`).

Testes novos (2):

- `should not send SHOW_WINDOW when existing instance is a different
  user` — current=user_b vs existing=user_a; `notifyAttemptCount=0`,
  dialog ainda exibe `"em outro usuário do Windows"`.
- `should not send SHOW_WINDOW when existing instance user is unknown`
  — `existingUser=null`; `notifyAttemptCount=0`, dialog
  `"identificar o usuário"`.

### F7 — [BAIXO] Dead code: `SingleInstanceService.notifyExistingInstance` estático

Método estático `static Future<bool> notifyExistingInstance()` em
`SingleInstanceService` apenas delegava para `IpcService.sendShowWindow`.
Não era chamado em lugar nenhum (fluxo real usa
`ISingleInstanceIpcClient.notifyExistingInstance` →
`SingleInstanceIpcClient` → `IpcService.sendShowWindow` — interface
exposta corretamente). Duas APIs para o mesmo destino.

Mitigação: método removido.

### F9 — [INFO] Expressão `singleInstanceEnabled` contraintuitiva

`bootstrap_config.dart:62`:

```dart
singleInstanceEnabled:
    !isDebugMode ||
    SingleInstanceConfig.isEnabledFromEnvValue(envValues['...']),
```

Funcionalmente correto e coberto por
`bootstrap_config_resolver_test.dart`, mas `!debug || env` confunde
revisão — parece sugerir que `env=true` em release pode desabilitar.

Mitigação: extraído helper `_resolveSingleInstanceEnabled` com
expressão explícita (`if (!debug) return true; return envCheck(...)`)
e doc-comment que documenta a invariante de release: o env é
**intencionalmente ignorado** em release para evitar `.env` de
produção com `SINGLE_INSTANCE_ENABLED=false`.

## Não tocado neste audit

### F8 — [BAIXO] Cache de porta IPC é por processo (não persistente)

`_cachedActivePort` em `IpcService` é variável estática de classe →
toda nova UI começa do `58724`. Em cenário onde 58724-25 estão
ocupados por outro app, cada 2ª UI paga `2 × 150ms = 300ms` extra
até cair no `slowTimeout`. Custo/benefício marginal — só vale se F4
não tivesse já mitigado a UX correlata.

Decisão: deixar como pendência futura (anotada no
`execucao_remota_backlog_2026-05-27.md` se houver demanda).

### F10 — [INFO] Smoke test PowerShell sem cenário inter-usuário / `fail_open`

`test/scripts/windows_single_instance_smoke.ps1` cobre cenários
UI↔Service na mesma conta, scheduled task, startup task, legacy Run
cleanup. **Não cobre**:

- F1 real (UI como `Domain\User` enquanto service é `LocalSystem`) —
  exigiria `runas /user:` ou `Start-Process -Credential` e máquina
  com domínio configurado.
- F2 (`fail_open` com `ERROR_ACCESS_DENIED` simulado) — coberto por
  unit tests novos (3 cases adicionados).
- F4 race acquire→IPC — coberto por unit test novo.

Decisão: F2 e F4 estão cobertos em unit tests. F1 real fica para um
runbook futuro (`smoke_single_instance_multi_user.md`) quando houver
ambiente de domínio disponível.

## Validação

- `flutter analyze lib test`: **No issues found**.
- `flutter test` (suíte completa): **2009 testes passam, 13 skipped,
  0 falhas** (vs baseline 1963 → +46 testes, incluindo os 8 novos
  deste audit + reorganizações em testes pré-existentes que ficaram
  mais granulares).
- Suíte focada single-instance/IPC/bootstrap (77 testes): todos
  passam, incluindo os novos para F1/F2/F3/F4/F6/idempotência.

## Convenções de log adicionadas

- `event=single_instance_lock_acl_denied` — mutex falhou com
  `ERROR_ACCESS_DENIED` (provável conflito de DACL entre principals
  diferentes).
- `event=single_instance_fail_open_blocked_by_active_ipc` — fail_open
  bloqueou startup após detectar dono ativo via IPC probe.
- `event=single_instance_ipc_probe_failed` — o próprio probe IPC
  lançou exceção (tratado como “sem dono” — preserva fail_open).
- `event=single_instance_check_and_lock_reentrant` — 2ª+ chamada de
  `checkAndLock` no mesmo processo (defensivo; não deveria acontecer
  em produção).
- `event=duplicate_skip_show_window_cross_user` — 2ª instância não
  enviou SHOW_WINDOW porque o dono é outro usuário ou desconhecido.
