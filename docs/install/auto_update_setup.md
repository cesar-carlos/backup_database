# Configuracao de Atualizacao Automatica

Este documento descreve o fluxo atual de auto update no Windows.

## Resumo

O aplicativo nao usa mais `auto_updater`/WinSparkle para decidir ou instalar atualizacoes.

O runtime faz este pipeline:

1. Le `AUTO_UPDATE_FEED_URL`
2. Baixa e parseia `appcast.xml`
3. Seleciona a release Windows mais nova respeitando `minSupportedAppVersion` e `rolloutPercentage` (ver "Staged rollout")
4. Compara com a versao atual
5. Checa espaco livre no diretorio de staging (>= 2x o tamanho do instalador) antes de baixar
6. Baixa o instalador `BackupDatabase-Setup-<versao>.exe`
7. Valida `length` e `sha256`
8. Persiste `update_context.json` (origin UI ou service) e dispara o instalador com:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

9. Verifica que o processo do instalador segue vivo por ate 5 s; se morrer cedo (UAC negado, antivirus, binario corrompido) NAO encerra o app e emite snapshot de erro.
10. Encerra o processo atual:
    - modo UI: `exit(0)`
    - modo servico: `exit(78)` (`ServiceModeExitCode.handoffForInstaller`) para impedir que o NSSM tente reiniciar enquanto o `setup.iss` ainda esta substituindo binarios.

Antes do handoff silencioso, o app grava `update_context.json` em:

```text
C:\ProgramData\BackupDatabase\staging\updates\update_context.json
```

Esse contexto e consumido pelo instalador (`setup.iss`) e por `restore_update_state.ps1` para relancar a UI ou re-registrar o Windows Service apos a troca de versao.

> O `restore_update_state.ps1` tambem registra a assinatura Authenticode do
> binario alvo no log do servico (`service_stdout.log`). Hoje e' apenas
> trilha (best-effort) — assinatura ainda nao bloqueia o restore.

## Matriz de plataformas suportadas

Auto update silencioso requer Windows 8.1+ ou Server 2016+ (Windows 10 e' a fronteira interna usada por `WindowsCompatibilityPolicy`).

| Plataforma | App roda? | Auto update silencioso? |
| --- | --- | --- |
| Windows 8.1 / 10 / 11 | Sim | Sim |
| Windows Server 2016 ou superior | Sim | Sim |
| Windows Server 2012 / 2012 R2 | Sim | **Nao** (`autoUpdateUnsupportedLegacyServer`) |
| Windows 8 ou anterior | Nao | Nao |
| Sessao nao interativa (Session 0 puro) | Sim como servico | Sim, apenas quando o servico esta em `LocalSystem` |

Em servidores legados (2012 / 2012 R2), a UI mostra um `InfoBar` explicando
o bloqueio. A atualizacao manual via instalador permanece suportada.

## Configuracao da maquina

Em instalacoes Windows, a configuracao ativa fica em:

```text
C:\ProgramData\BackupDatabase\config\.env
```

Esse arquivo tem precedencia sobre o asset `.env` empacotado no app.

O asset `.env` continua existindo apenas como fallback para desenvolvimento local com `flutter run`.

O instalador e o runtime tentam migrar automaticamente um `.env` legado
da pasta `{app}` para `ProgramData`, preservando um backup em:

```text
C:\ProgramData\BackupDatabase\config\.env.migrated-from-appdir.bak
```

## Variavel obrigatoria

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
```

## Variaveis opcionais

| Variavel | Default | Efeito |
| --- | --- | --- |
| `AUTO_UPDATE_CHECK_INTERVAL_SECONDS` | `3600` | Intervalo do timer periodico. `0` desativa (so executa em startup ou manual). Valores `< 60` sao clampados para `60s`. |

## Formato do feed

Cada item do `appcast.xml` precisa ter:

- `sparkle:version`
- `sparkle:os="windows"`
- `url`
- `length`
- `sha256`

Atributos opcionais reconhecidos pelo cliente (preenchidos pelo workflow `update-appcast` a partir de `scripts/appcast_policy.json`):

- `sparkle:minSupportedAppVersion` — versao minima da app instalada para receber a release. Clientes mais antigos pulam.
- `sparkle:rolloutPercentage` — `0..100`. Cliente decide participacao via FNV-1a determinístico de `targetVersion:MachineGuid`. Sem `MachineGuid` legivel, deixa passar (nao bloqueia por dado faltante).

Exemplo:

```xml
<item>
  <title>Version X.Y.Z</title>
  <pubDate>Sun, 19 Apr 2026 17:07:49 +0000</pubDate>
  <description>Automatic update via GitHub Release.</description>
  <enclosure
    url="https://github.com/cesar-carlos/backup_database/releases/download/vX.Y.Z/BackupDatabase-Setup-X.Y.Z.exe"
    sparkle:version="X.Y.Z"
    sparkle:os="windows"
    length="39020908"
    type="application/octet-stream"
    sha256="..."
    sparkle:minSupportedAppVersion="3.0.0"
    sparkle:rolloutPercentage="50"
  />
</item>
```

## Release e appcast

O feed nao e mais editado inline no workflow.

O fluxo oficial agora e:

1. Publicar a release no GitHub com o instalador `.exe`
2. Publicar tambem o sidecar `BackupDatabase-Setup-<versao>.exe.sha256`
3. O workflow `.github/workflows/update-appcast.yml` executa
4. O script `scripts/sync_appcast_from_releases.py` reconstroi o `appcast.xml` do zero
5. O script deduplica versoes, ordena por `published_at`, aplica a policy (`blocked_versions`, `min_publication_age_minutes`, `rollout_percentages`, `min_supported_app_version`) e exige o hash do sidecar
6. O workflow faz commit do `appcast.xml` atualizado na `main`

## Rollback operacional

Se uma release publicada precisar sair do feed sem ser apagada do GitHub:

1. Edite [scripts/appcast_policy.json](/D:/Developer/Flutter/backup_database/scripts/appcast_policy.json)
2. Adicione a versao em `blocked_versions`
3. Faca push na `main` ou rode o workflow manualmente

O workflow reconstroi o `appcast.xml` sem as versoes bloqueadas.

## Staged rollout

`scripts/appcast_policy.json` aceita campos adicionais para entrega controlada:

```jsonc
{
  "blocked_versions": ["3.2.0"],
  "min_supported_app_version": "3.0.0",
  "rollout_percentages": {
    "3.5.0": 25
  },
  "min_publication_age_minutes": {
    "3.5.0": 120
  }
}
```

- `min_supported_app_version` — clientes em versao menor sao bloqueados (vira atributo no enclosure; o cliente respeita).
- `rollout_percentages` — gradua a release por porcentagem deterministica baseada no `MachineGuid` do cliente. Para subir para 100% basta remover a chave ou setar `100`.
- `min_publication_age_minutes` — segura a release fora do feed ate atingir N minutos de idade; serve como janela de observacao.

## Diretorios e arquivos operacionais

| Arquivo | Onde | Para que |
| --- | --- | --- |
| `update_context.json` | `…\staging\updates\` | Contexto da troca de versao (`origin`, `appMode`, `relaunchArguments`, configuracao do servico). TTL de 45 minutos: contextos expirados sao removidos por `restore_update_state.ps1` e pela proxima `initialize()` do servico. |
| `auto_update_history.jsonl` | `…\staging\updates\` | Trilha das ultimas tentativas. Cada linha tem `schemaVersion`, `source`, `status`, `stage`, `installerBytes`, `downloadDurationMs`, `downloadMbps` e `error`. Rotacao automatica em ate `256 KiB` ou `14 dias`. |
| `auto_update.lock` | `…\locks\` | Coordenacao entre instancias (UI + servico + execucao agendada). Arquivo texto `chave=valor` (`pid`, `acquiredAt`, `source`, `stage`, `targetVersion`). Considerado obsoleto se: (a) excedeu `2h` (`defaultLockStaleAfter`) OU (b) o `pid` registrado ja nao existe. |
| `BackupDatabase-Setup-*.exe` | `…\staging\updates\` | Instaladores baixados. Limpeza mantem o alvo atual + 1 anterior por ate `7 dias`; cobertura para rollback rapido. |

## Observacoes

- O updater e Windows-only.
- UI e Windows Service usam o mesmo pipeline.
- Em modo servico, auto update silencioso so e suportado quando o Windows Service esta em `LocalSystem` (ou aliases `System` / `NT AUTHORITY\SYSTEM`).
- A instalacao e forcada e silenciosa.
- Em modo UI, se o usuario logado nao for administrador, o instalador silencioso pode disparar prompt UAC (o `/VERYSILENT` nao suprime UAC). Quando o prompt e negado, o spawn morre cedo: o app NAO encerra, e o snapshot vira `error` com a mensagem do `setup.iss`.
- Alterar `.env` dentro da pasta `{app}` nao muda o runtime da maquina instalada.
- Em caso de erro entre `evaluating_release` e `preparing_install`, o `update_context.json` recem-gravado e removido para evitar que um restore manual aplique um estado parcial.
