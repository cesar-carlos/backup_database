# ADR-015: Pipeline de icones Windows e refresh do atalho de desktop

- Status: accepted
- Data: 2026-05-28
- Decisores: time aplicativo (Clean Architecture + desktop Windows)
- Contexto relacionado:
  - `installer/setup.iss` (`RemoveExistingDesktopShortcut`, `TouchDesktopShortcut`, `RefreshWindowsIconCache`, `PrepareToInstall`)
  - `installer/build_installer.py`
  - `scripts/verify_windows_icons.py` (flags `--require-exe` / `--json`)
  - `scripts/windows_icon_utils.py`
  - `test/unit/installer/update_installer_scripts_test.dart`
  - `.github/workflows/build-installer.yml`

## Contexto

Apos releases multiplas onde o icone do app foi atualizado em
`assets/image/new/database_512px.png`, varios usuarios reportaram que
**o atalho da area de trabalho continuava exibindo o icone antigo
(quadrado azul Flutter)** mesmo apos a instalacao da nova versao.

A investigacao identificou tres causas independentes que podiam ocorrer
em sequencia ou isoladamente:

1. **`.exe` empacotado sem o icone novo**. O pipeline manual permitia
   rodar `flutter build windows --release` sem antes regerar
   `windows/runner/resources/app_icon.ico` a partir do PNG fonte. O
   `Runner.rc` referencia `app_icon.ico` por nome de arquivo — se o
   `.ico` no disco estivesse desatualizado, o `.exe` levava o icone
   antigo. Inno Setup entao copiava esse `.exe` desatualizado para
   `{app}\backup_database.exe` e o atalho `IconFilename: {app}\{exe}`
   apontava para a arte velha.

2. **`.exe` antigo nao substituido durante upgrade**. Quando o usuario
   tinha o app aberto durante a instalacao, `taskkill` nao conseguia
   fechar e o Inno Setup *logava warning mas seguia*. Arquivos abertos
   ficavam travados em uso; o `.exe` antigo permanecia no disco e o
   atalho continuava apontando para arte velha.

3. **Cache de icones do Windows Explorer**. Mesmo quando o `.exe` era
   substituido com sucesso, o Explorer mantinha cache do icone associado
   ao `.lnk` na area de trabalho ate o proximo refresh / logon.

## Decisao

Adotar **defesa em profundidade** combinando quatro camadas:

### 1. Pipeline de build com gate por hash (`scripts/windows_icon_utils.py`)

- `database_512px.png` -> `flutter_launcher_icons` -> `app_icon.ico` ->
  `Runner.rc` -> `.exe`.
- Sidecar `windows/runner/resources/.app_icon_source_sha256` guarda o
  SHA-256 do PNG no momento da ultima geracao do `.ico`. Drift = gate.
- `installer/build_installer.py` regera `.ico` quando o hash muda
  (mesmo que `mtime` engane), limpa `backup_database.exe` antes do
  rebuild e roda `scripts/verify_windows_icons.py --require-exe` em
  dois pontos: apos `flutter build` (passo 3) e antes do `ISCC`
  (passo 7).

### 2. `verify_windows_icons.py --require-exe`

- Verifica que o PNG de `app_icon.ico` aparece dentro do
  `backup_database.exe` (busca de prefixo de 200 bytes). Detecta
  imediatamente o caso em que o `.exe` foi compilado com arte velha.
- Modo default (sem flag) continua funcionando em CI Linux porque o
  `.exe` so e exigido com a flag explicita.
- Flag `--json` permite integracao programatica (PR comments,
  workflows externos).

### 3. `setup.iss` com diagnostico e remediacao no pos-install

- **`PrepareToInstall`**: re-`StopService('BackupDatabaseService')`
  antes de copiar arquivos (NSSM pode reiniciar entre `InitializeSetup`
  e `PrepareToInstall`).
- **`PrepareToInstall`** em modo interativo: `MsgBox MB_YESNO` (default
  `IDNO`) quando o app continua rodando apos `taskkill`. Mensagem
  explica explicitamente o sintoma "icone do atalho pode permanecer
  desatualizado".
- **`CurStepChanged` / `ssInstall`**: `RemoveExistingDesktopShortcut()`
  apaga `{autodesktop}\Backup Database.lnk` antes da secao `[Icons]`
  do Inno gerar o novo — caso contrario o Explorer pode preservar o
  icone cacheado mesmo quando o `.lnk` e sobrescrito.
- **`ssPostInstall`**: `TouchDesktopShortcut()` atualiza
  `LastWriteTime` do `.lnk` via PowerShell (`powershell.exe` ->
  fallback `pwsh.exe`), forcando o Explorer a reavaliar o icone na
  proxima atualizacao de desktop. Complementa
  `RefreshWindowsIconCache()` (`ie4uinit.exe -show`).
- Task `desktopicon` agora vem com `Flags: checked` por default
  (uniformiza primeira instalacao).

### 4. CI gates

- `.github/workflows/test.yml`: roda `verify_windows_icons.py` (sem
  `--require-exe`, default Linux-safe) + unittests do modulo Python.
- `.github/workflows/integration-self-hosted.yml`, suite
  `windows-smoke`: agora roda `dart run flutter_launcher_icons` +
  `verify_windows_icons.py` **antes** do `flutter build`, e
  `verify_windows_icons.py --require-exe` **depois** — garante que
  o smoke nao passe com `.exe` desalinhado.
- `.github/workflows/build-installer.yml` (novo): valida
  `installer/build_installer.py` end-to-end em runner Windows
  self-hosted, sobe `.exe` + `.sha256` como artefato. Gate antes
  do release fisico.

## Alternativas consideradas

### Opcao A: aceitar o cache do Windows e documentar workaround

- Descricao: deixar o instalador como esta e ensinar usuarios a remover
  `.lnk` + recriar do menu Iniciar quando o icone aparecer antigo.
- Por que nao foi escolhida: **mau UX** para um sintoma 100% diagnostico
  do produto (o usuario nao tem como saber que e cache). Custo de
  suporte cresce a cada release que muda o icone.

### Opcao B: usar `IconFilename` apontando para um `.ico` separado no `{app}`

- Descricao: embarcar `app_icon.ico` em `{app}` e usar
  `IconFilename: "{app}\app_icon.ico"` no atalho — em vez de apontar
  para o `.exe`.
- Por que nao foi escolhida: nao resolve causas 1 e 2 (`.exe` desatualizado
  continua propagando arte velha em outros lugares: barra de tarefas,
  Alt-Tab, Task Manager, etc.). Apenas troca o problema de lugar.

### Opcao C: refresh-cache obrigatorio via reinicio do Explorer

- Descricao: `taskkill /f /im explorer.exe && start explorer` no
  pos-install.
- Por que nao foi escolhida: muito invasivo. Reiniciar o Explorer
  durante upgrade fecha janelas do usuario e tem risco de race condition
  com outras integracoes (system tray de outros apps, notificacoes
  pendentes). `ie4uinit.exe -show` + touch do `.lnk` cobre 99% dos
  casos sem efeitos colaterais.

## Consequencias

### Positivas

- Pipeline tem 4 gates independentes; qualquer falha em um e detectada
  antes do release publicar instalador quebrado.
- Sintoma "icone antigo" deixa de ser invisivel: regressao no pipeline
  vira falha de CI; regressao no instalador vira falha de smoke.
- ADR documenta o porque do conjunto de procedures aparentemente
  redundantes em `setup.iss` (`RemoveExistingDesktopShortcut` +
  `TouchDesktopShortcut` + `RefreshWindowsIconCache`). Manutenibilidade
  futura nao remove um deles "por limpeza" sem entender o trade-off.

### Negativas

- `setup.iss` ganhou ~120 linhas. Mitigado por ADR-015 + ADR posterior
  de modularizacao via `#include` quando o arquivo ultrapassar limite
  de revisao confortavel (~1000 linhas).
- `build_installer.py` agora chama Python (`verify_windows_icons.py`)
  como subprocesso duas vezes — overhead aceitavel (~1s cada), pago
  apenas em build de release local + CI dedicada.

### Neutras

- Pre-commit hook em `scripts/hooks/pre-commit` e opt-in
  (`python scripts/install_git_hooks.py`). Devs com setup local
  rapido podem usar; devs preferindo CI-only nao sao afetados.

## Notas de implementacao

- `RemoveExistingDesktopShortcut()` so apaga o `.lnk` quando
  `WizardIsTaskSelected('desktopicon')` esta ativo. Usuario que
  desmarca a task em upgrade preserva seu desktop sem `.lnk` orfao.
- `TouchDesktopShortcut()` retorna sucesso silenciosamente se PowerShell
  nao estiver disponivel — best-effort por design. O sintoma sem ele
  e cache de icone, nao falha de instalacao.
- Tests estaticos em
  `test/unit/installer/update_installer_scripts_test.dart` validam o
  contrato via `contains` de substring. Refactors futuros que renomeiem
  procedures precisam atualizar os tests no mesmo PR.
