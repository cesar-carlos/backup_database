# Troubleshooting - Windows Service

## Flags usadas pelo servico

| Flag | Proposito |
|------|-----------|
| `--mode=server` | Modo funcional do app no papel de servidor. |
| `--mode=client` | Modo funcional do app no papel de cliente remoto. |
| `--run-as-service` | Forca execucao headless como servico Windows. |
| `--minimized` | Mantem a UI minimizada quando o app nao esta em modo headless. |

`--run-as-service` e `--mode=server` sao independentes. Um atalho com
`--mode=server` abre a UI. Somente o processo iniciado via NSSM com
`--run-as-service` entra no fluxo headless.

## Como o modo servico e detectado

O `ServiceModeDetector` verifica, nesta ordem:

1. Session 0
2. Argumento `--run-as-service`
3. Variavel de ambiente `SERVICE_MODE=server`

Se nenhuma camada casar, o processo cai em modo UI.

## Logs principais

```text
C:\ProgramData\BackupDatabase\logs\service_stdout.log
C:\ProgramData\BackupDatabase\logs\service_stderr.log
```

## Sinais de inicializacao correta

Procure por:

```text
[main] args=[--minimized, --mode=server, --run-as-service]
[main] env: SERVICE_MODE=server, ...
[ServiceModeDetector] MATCH layer-1: Session 0
==> Modo Servico detectado - inicializando sem UI
>>> [8/8] Servico de agendamento iniciado
```

## Problema: app entrou em modo UI

Sintoma comum no `service_stderr.log`:

```text
[ERROR:flutter/...]
Could not create additional swap chains
```

Verifique:

```powershell
nssm get BackupDatabaseService AppParameters
nssm get BackupDatabaseService AppEnvironmentExtra
nssm get BackupDatabaseService ObjectName
```

Esperado:

```text
AppParameters: --mode=server --minimized --run-as-service
AppEnvironmentExtra: SERVICE_MODE=server
ObjectName: LocalSystem
```

Correcao:

```powershell
nssm set BackupDatabaseService AppParameters "--mode=server --minimized --run-as-service"
nssm set BackupDatabaseService AppEnvironmentExtra "SERVICE_MODE=server"
nssm restart BackupDatabaseService
```

## Problema: trava em algum passo

| Passo | Descricao | Causa comum |
|------|-----------|-------------|
| 1-2 | Carregamento de ambiente | `C:\ProgramData\BackupDatabase\config\.env` ausente ou invalido |
| 4 | Single instance | Outro processo manteve o mutex |
| 5 | Dependencias | Banco travado ou configuracao invalida |
| 7 | Event Log | Falta permissao para registrar fonte |
| 8 | Scheduler | Falha ao iniciar tarefas agendadas |

## Teste manual sem NSSM

```powershell
cd "C:\Program Files\Backup Database"
.\backup_database.exe --minimized --mode=server --run-as-service
```

Para validar UI em modo servidor:

```powershell
.\backup_database.exe --mode=server
```

## Verificar configuracao completa do NSSM

```powershell
nssm get BackupDatabaseService Application
nssm get BackupDatabaseService AppParameters
nssm get BackupDatabaseService AppDirectory
nssm get BackupDatabaseService ObjectName
nssm get BackupDatabaseService AppEnvironmentExtra
```

Valores esperados:

```text
Application:         C:\Program Files\Backup Database\backup_database.exe
AppParameters:       --mode=server --minimized --run-as-service
AppDirectory:        C:\Program Files\Backup Database
ObjectName:          LocalSystem
AppEnvironmentExtra: SERVICE_MODE=server
```

`AppDirectory` continua necessario para assets, binarios auxiliares e scripts.
O `.env` ativo da maquina nao vem mais da pasta do app; ele mora em:

```text
C:\ProgramData\BackupDatabase\config\.env
```

## Reinstalar servico

```powershell
nssm stop BackupDatabaseService
nssm remove BackupDatabaseService confirm

cd "C:\Program Files\Backup Database\tools"
.\install_service.ps1

nssm status BackupDatabaseService
Get-Content "C:\ProgramData\BackupDatabase\logs\service_stdout.log" -Wait
```

## Problemas comuns

### Timeout ao iniciar

1. Veja qual passo parou nos logs.
2. Se travou no passo 5, valide banco e credenciais.
3. Se travou no passo 8, valide scheduler e dependencias.
4. Confirme que `C:\ProgramData\BackupDatabase\config\.env` existe.

### "Servico nao retornou um erro"

1. Leia `service_stderr.log`.
2. Confirme `AppDirectory` no NSSM.
3. Confirme o `.env` em `ProgramData`.
4. Teste manualmente com `--run-as-service`.

### Instalacao falhou com "ERRO CRITICO"

1. Execute o script como Administrador.
2. Verifique se `tools\nssm.exe` nao esta bloqueado.
3. Releia a mensagem para identificar qual chave do NSSM falhou.

## Event Viewer

- Logs do Windows -> Application
- Filtrar por fonte: `Backup Database Service`

| ID | Significado |
|----|-------------|
| 3001 | Service started |
| 3002 | Service failed to start |

## Informacoes para suporte

Inclua:

1. Primeiras 50 linhas de `service_stdout.log`
2. Conteudo completo de `service_stderr.log`
3. Saida de `nssm get BackupDatabaseService AppParameters`
4. Saida de `nssm get BackupDatabaseService AppEnvironmentExtra`
5. Session ID detectado nos logs
