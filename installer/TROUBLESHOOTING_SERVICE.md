# Troubleshooting - Windows Service

## Flags usadas pelo serviço

| Flag | Propósito |
|------|-----------|
| `--mode=server` | Modo funcional do app (servidor de backups). Usado por atalhos de UI e NSSM. |
| `--mode=client` | Modo funcional do app (cliente remoto). Usado por atalhos de UI. |
| `--run-as-service` | Sinaliza execução headless como serviço Windows. Injetado pelo NSSM via `AppParameters`. |
| `--minimized` | Inicia a janela minimizada (modo UI). Não afeta modo headless. |

> **Importante**: `--run-as-service` e `--mode=server` são flags **diferentes** e **independentes**.
> Um atalho de desktop com `--mode=server` abre a UI no modo servidor **sem** headless.
> Somente processos iniciados via NSSM (com `--run-as-service`) entram em modo headless.

---

## Como o modo serviço é detectado

O `ServiceModeDetector` verifica em três camadas (em ordem de prioridade):

1. **Session 0** — Serviços Windows sempre rodam em Session 0. Log: `[ServiceModeDetector] MATCH layer-1: Session 0`
2. **Argumento `--run-as-service`** — Injetado pelo NSSM via `AppParameters`. Log: `[ServiceModeDetector] MATCH layer-2`
3. **Variável de ambiente `SERVICE_MODE`** — Injetada pelo NSSM via `AppEnvironmentExtra`. Valores aceitos: `server`, `1`, `true`. Log: `[ServiceModeDetector] MATCH layer-3`

Se nenhuma camada bater: `[ServiceModeDetector] NO MATCH → UI mode`

---

## 1. Verificar logs do serviço

```
C:\ProgramData\BackupDatabase\logs\service_stdout.log
C:\ProgramData\BackupDatabase\logs\service_stderr.log
```

---

## 2. Inicialização bem-sucedida — o que procurar

```
[main] args=[--minimized, --mode=server, --run-as-service]
[main] env: SERVICE_MODE=server, ...
[ServiceModeDetector] Session ID: 0
[ServiceModeDetector] MATCH layer-1: Session 0 → service mode
==> Modo Servico detectado - inicializando sem UI
>>> [1/8] Iniciando ServiceModeInitializer
>>> [2/8] Variáveis de ambiente carregadas
>>> [3/8] Modo do aplicativo (servico): server
>>> [4/8] Single instance check realizado para modo serviço
>>> [5/8] Dependências configuradas com sucesso
>>> [6/8] Serviços obtidos com sucesso
>>> [7/8] Event Log inicializado
>>> [8/8] ✅ Serviço de agendamento iniciado
🎉 ✅ Aplicativo rodando como serviço do Windows - INICIALIZAÇÃO COMPLETA
```

---

## 3. Problema: Não detectou modo serviço (GPU/EGL no stderr)

**Sintoma** em `service_stderr.log`:
```
[ERROR:flutter/shell/platform/windows/direct_manipulation.cc(202)] manager_->Activate(...)
ERR: SwapChain11.cpp:636 ... Could not create additional swap chains
```

**Diagnóstico** em `service_stdout.log`:
- Procure por `[ServiceModeDetector] NO MATCH → UI mode`
- Verifique qual Session ID foi detectado (deve ser `0` para serviços)
- Verifique se `--run-as-service` aparece nos args
- Verifique se `SERVICE_MODE=server` está no env

**Verificar configuração do NSSM**:
```powershell
nssm get BackupDatabaseService AppParameters
# Deve retornar: --minimized --mode=server --run-as-service

nssm get BackupDatabaseService AppEnvironmentExtra
# Deve retornar: SERVICE_MODE=server

nssm get BackupDatabaseService ObjectName
# Deve retornar: LocalSystem
```

**Corrigir AppParameters incorretos**:
```powershell
nssm set BackupDatabaseService AppParameters "--minimized --mode=server --run-as-service"
nssm set BackupDatabaseService AppEnvironmentExtra "SERVICE_MODE=server"
nssm restart BackupDatabaseService
```

---

## 4. Problema: Trava em algum passo

| Passo | Descrição | Causa comum |
|-------|-----------|-------------|
| 1-2 | Carregando .env | Arquivo ausente ou bloqueado |
| 4 | Single instance | Outro processo já tem o mutex |
| 5 | Dependências | Banco de dados travado |
| 7 | Event Log | Sem permissões para Event Viewer |
| 8 | Scheduler | Falha ao iniciar tarefas agendadas |

---

## 5. Testar manualmente (sem NSSM)

```powershell
# Teste de modo serviço real (headless)
cd "C:\Program Files\Backup Database"
.\backup_database.exe --minimized --mode=server --run-as-service
```

Se aparecerem erros de GPU quando você usa `--run-as-service`, o problema é no
`ServiceModeDetector` (Session ID pode não ser 0 em seu ambiente — verifique os logs).

```powershell
# Teste de modo UI servidor (com janela)
.\backup_database.exe --mode=server
```

---

## 6. Verificar configuração completa do NSSM

```powershell
nssm get BackupDatabaseService Application
nssm get BackupDatabaseService AppParameters
nssm get BackupDatabaseService AppDirectory
nssm get BackupDatabaseService ObjectName
nssm get BackupDatabaseService AppEnvironmentExtra

# Valores esperados:
# Application:          C:\Program Files\Backup Database\backup_database.exe
# AppParameters:        --minimized --mode=server --run-as-service
# AppDirectory:         C:\Program Files\Backup Database
# ObjectName:           LocalSystem
# AppEnvironmentExtra:  SERVICE_MODE=server
```

---

## 7. Reinstalar serviço

```powershell
# Como Administrador
nssm stop BackupDatabaseService
nssm remove BackupDatabaseService confirm

cd "C:\Program Files\Backup Database\tools"
.\install_service.ps1

nssm status BackupDatabaseService

# Monitorar logs em tempo real
Get-Content "C:\ProgramData\BackupDatabase\logs\service_stdout.log" -Wait
```

---

## 8. Problemas comuns

### "Em pausa" ou timeout ao iniciar

**Causa**: Processo não completa inicialização no timeout do SCM (30s padrão).

1. Investigar qual passo está travando nos logs
2. Se travar no passo 5, banco pode estar bloqueado
3. Se travar no passo 8, verificar `.env` e credenciais

### Erros de GPU/EGL

**Causa**: App entrou em modo UI em Session 0.

1. Verificar se `--run-as-service` está em `AppParameters` do NSSM
2. Verificar se `SERVICE_MODE=server` está em `AppEnvironmentExtra`
3. Verificar Session ID nos logs: deve ser `0`

### "Serviço não retornou um erro"

**Causa**: Processo terminou com EXIT_FAILURE antes de reportar ao SCM.

1. Verificar `service_stderr.log` para exceções
2. Verificar se `AppDirectory` está configurado (necessário para `.env`)
3. Testar manualmente com `--run-as-service`

### Instalação falhou com "ERRO CRÍTICO"

**Causa**: Chave crítica do NSSM (`AppParameters`, `AppDirectory` ou `AppEnvironmentExtra`) não pôde ser configurada.

1. Executar o script como Administrador
2. Verificar se o NSSM (`tools\nssm.exe`) não está bloqueado por antivírus
3. Reler a mensagem de erro que indica qual chave falhou

---

## 9. Event Viewer

- **Logs do Windows** → **Application**
- Filtrar por fonte: `Backup Database Service`

| ID | Significado |
|----|-------------|
| 3001 | Service started |
| 3002 | Service failed to start |

---

## 10. Informações para suporte

Ao reportar um problema, inclua:
1. Primeiras 50 linhas de `service_stdout.log`
2. Conteúdo completo de `service_stderr.log`
3. Saída de `nssm get BackupDatabaseService AppParameters`
4. Saída de `nssm get BackupDatabaseService AppEnvironmentExtra`
5. Session ID detectado nos logs
