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
[main] processRole=service bootstrap=service_no_ui_surface
[bootstrap] processRole=service ... coexists_with_ui=false lock_scope=machine_global
>>> [10/11] OK Iniciando scheduler, health, fila persistida e limpeza de staging
>>> [11/11] OK Inicializando auto update do servico
```

UI e servico compartilham o mesmo mutex global. Com o servico rodando, a UI
nao sobe (dialog ou exit 0 no atalho de startup). `exit 77` no servico significa
que outro processo ja detem o lock.

Instalar o servico **com a UI aberta** registra o servico no SCM, mas o processo
do servico nao consegue ficar RUNNING (o app segura o mutex). A tela de
Configuracoes deve oferecer **Fechar o aplicativo e iniciar o servico** (handoff:
prompt UAC se preciso, `sc start` atrasado, depois o app sai). Nao interprete
essa falha de start como `.env` em falta.

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
| 1 | Init | Falha muito cedo no `ServiceBootstrapLog` |
| 2 | Carregamento de ambiente | `C:\ProgramData\BackupDatabase\config\.env` ausente ou invalido |
| 3 | Modo do aplicativo | `.install_mode` / `APP_MODE` inconsistente |
| 4 | Single instance | Outro processo (UI ou servico) manteve o mutex compartilhado |
| 5 | Dependencias (DI) | Banco travado ou configuracao invalida |
| 6 | Resolve servicos | Registro GetIt ausente |
| 7 | IPC | Named pipe `\\.\pipe\BackupDatabase_Ipc_*` ocupado, ACL ou processo peer recusado. IPC **nao** usa TCP; o instalador nao abre porta para isso. |
| 8 | Event Log | Falta permissao para registrar fonte |
| 9 | Shutdown handler | Falha ao registrar Ctrl+C / SCM stop |
| 10 | Scheduler / health / fila / socket | Falha ao iniciar tarefas agendadas ou socket remoto (TCP 9527) |
| 11 | Auto update | Feed ou conta de servico bloqueada |

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

Se o servico usar conta customizada, a execucao pode continuar normal, mas o
update silencioso nao sera restaurado automaticamente. Esse fluxo segue
restrito a `LocalSystem`. O `restore_update_state.ps1` **nao** chama
`nssm remove`/`install` nesse caso (`exit 2`). Se o update veio da UI
(`origin=ui`), o restore so relanca a UI e **nao** starta o servico.

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
3. Se travou no passo 10, valide scheduler, fila e socket remoto (TCP 9527).
4. Confirme que `C:\ProgramData\BackupDatabase\config\.env` existe.

### Clientes remotos nao conectam (TCP 9527)

IPC local e named pipe; nao precisa de firewall. O socket remoto escuta
TCP **9527**. No wizard de instalacao (Server Mode) existe a task opcional
(desmarcada) que cria a regra `Backup Database Remote Socket`. Sem ela:

```powershell
netsh advfirewall firewall add rule name="Backup Database Remote Socket" dir=in action=allow protocol=TCP localport=9527 profile=any
```

O atalho `{group}\Troubleshooting do Serviço` aponta para esta pagina em
`{app}\docs\TROUBLESHOOTING_SERVICE.md`.

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

## Auto update do servico

### Diretorios e arquivos

| Arquivo | Onde | Funcao |
| --- | --- | --- |
| `update_context.json` | `C:\ProgramData\BackupDatabase\staging\updates\` | Contexto do handoff (origem, modo, args, config do NSSM). TTL 45 min. |
| `auto_update_history.jsonl` | `…\staging\updates\` | Trilha de tentativas (`schemaVersion`, `source`, `status`, `stage`, `installerBytes`, `downloadMbps`, `error`). |
| `auto_update.lock` | `C:\ProgramData\BackupDatabase\locks\` | Coordenacao entre UI/servico/execucoes agendadas. Texto `chave=valor` por linha. |
| `BackupDatabase-Setup-*.exe` | `…\staging\updates\` | Instaladores baixados; rotacao mantem o atual + 1 anterior por 7 dias. |

### Como ler o `auto_update.lock`

```text
pid=1234
acquiredAt=2026-05-27T14:00:00.000Z
source=periodic
currentVersion=3.2.1
attempt=2
stage=downloading_installer
targetVersion=3.2.2
```

Lock e considerado **obsoleto** quando: (a) excedeu 2 h desde
`acquiredAt`, OU (b) o `pid` registrado ja nao existe (`tasklist /FI "PID
eq <pid>"`). O proximo `checkNow` remove e tenta novamente.

### Forcando o auto update no servico

Nao ha comando exposto. Para forcar:

```powershell
nssm restart BackupDatabaseService
```

O bootstrap dispara `checkNow(source: AppUpdateSource.startup)` apos
inicializar.

### Bloqueio por conta customizada

O `ServiceAccountProbe` consulta `Win32_Service.StartName`. Auto update
silencioso so e aceito para `LocalSystem`, `System` e
`NT AUTHORITY\SYSTEM` (case-insensitive). Outras contas geram log:

```text
Atualizacao automatica silenciosa bloqueada: o Windows Service esta configurado
com a conta "CONTOSO\backupsvc". ... Atualize manualmente ou reinstale o servico
com LocalSystem.
```

E o snapshot vira `blockedByActiveBackup` (status sentinel reusado para
qualquer bloqueio pre-launch).

### Exit codes especificos

| Codigo | Significado | NSSM `AppExit` |
| --- | --- | --- |
| `0` | Encerramento normal | `Default Restart` (servico sobe de novo) |
| `1` | Falha de bootstrap | `Default Restart` |
| `77` | Single-instance lock denied | `Exit` (nao reinicia) |
| `78` | Handoff para auto update | `Exit` (nao reinicia ate o `restore_update_state.ps1` recriar o servico) |

Esses codigos sao definidos em `lib/core/exit_codes.dart` e mapeados em
`install_service.ps1` / `restore_update_state.ps1`.

## Informacoes para suporte

Inclua:

1. Primeiras 50 linhas de `service_stdout.log`
2. Conteudo completo de `service_stderr.log`
3. Saida de `nssm get BackupDatabaseService AppParameters`
4. Saida de `nssm get BackupDatabaseService AppEnvironmentExtra`
5. Saida de `nssm get BackupDatabaseService AppExit`
6. Conteudo de `C:\ProgramData\BackupDatabase\locks\auto_update.lock` (se existir)
7. Ultimas 20 linhas de `C:\ProgramData\BackupDatabase\staging\updates\auto_update_history.jsonl`
8. Session ID detectado nos logs
