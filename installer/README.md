# Installer

Esta pasta concentra o empacotamento Windows do Backup Database. O fluxo
principal hoje e `python installer\build_installer.py`; o restante da pasta
existe para suportar esse caminho ou a manutencao do `setup.iss`.

O upgrade utiliza `rollback_update.ps1` e `rollback_core.ps1` para guardar a
versao instalada antes da copia e recupera-la se houver falha. O protocolo,
o espaco necessario e a recuperacao de instalacoes interrompidas estao em
[Auto update](../docs/install/auto_update_setup.md); os cenarios de regressao
estao no [guia de testes](../docs/install/testing_auto_update.md).

A instalacao avulsa do servico (pela UI, UAC ou `install_service.ps1`)
recusa substituir um registro existente, preservando sua conta e configuracao.
Para atualizar a aplicacao, utilize o instalador completo. Contas customizadas
exigem senha; credenciais incompletas nao usam LocalSystem como fallback.
Falhas nas configuracoes de conta, inicio automatico e recuperacao sao fatais.
O script elevado remove uma instalacao parcial apenas quando ele proprio
confirmou a criacao do servico; um timeout no processo chamador nao autoriza
remover um registro cuja origem nao foi confirmada.

## Fluxo oficial

Execute na raiz do projeto:

```powershell
python installer\build_installer.py
```

O script faz o necessario para uma release local:

1. sincroniza a versao do `pubspec.yaml` com `installer\setup.iss` e `.env`
2. sincroniza `app_icon.ico` (`flutter_launcher_icons`) e `assets\image\new\app_tray.ico` (copia do mesmo ICO para a bandeja)
3. valida ou recompila `flutter build windows --release`
4. baixa dependencias locais quando faltarem
5. compila o instalador com o Inno Setup
6. gera `installer\dist\BackupDatabase-Setup-<versao>.exe`
7. gera `installer\dist\BackupDatabase-Setup-<versao>.exe.sha256`

Use `python installer\update_version.py` sozinho apenas quando precisar
sincronizar versao sem compilar o instalador.

## Pre-requisitos

- Windows com Flutter configurado para `flutter build windows`
- Inno Setup 6 instalado
  Download: [jrsoftware.org/isdl.php](https://jrsoftware.org/isdl.php)
- artefatos do app e docs esperados pelo `setup.iss`
- `LICENSE` presente na raiz do repositorio (referenciado por
  `LicenseFile=..\LICENSE` no `setup.iss`). Se o arquivo sumir,
  `build_installer.py` falha tarde com erro do ISCC.

O `build_installer.py` ja encontra `ISCC.exe` nos caminhos padrao do Inno
Setup 6. Se o compilador nao estiver instalado, o script falha com instrucao
objetiva.

`build_installer.py` recusa rodar fora do Windows (depende do ISCC + da
inspecao de `VersionInfo` via PowerShell).

## Arquivos relevantes

- `setup.iss`: definicao do instalador, atalhos, tasks e migracao pos-update
- `build_installer.py`: pipeline local de build do instalador
- `update_version.py`: sincroniza versao entre `pubspec.yaml`, `setup.iss` e `.env`
- `check_dependencies.ps1`: utilitario opcional distribuido com o app para validar CLIs dos bancos suportados
- `install_service.ps1`: instala o app como Windows Service via WinSW
- `uninstall_service.ps1`: remove o Windows Service
- `capture_update_context.ps1`: captura contexto operacional antes do update silencioso
- `restore_update_state.ps1`: restaura UI ou Windows Service depois do update
- `merge_env.ps1`: mescla `.env.example` com a configuracao persistida da maquina
- `migrate_startup_entries.ps1`: remove entradas legadas nos perfis de usuario
  para evitar aberturas duplicadas no Terminal Server
- `encoding_utils.ps1`: helper UTF-8 sem BOM usado pelos scripts PowerShell
- `TROUBLESHOOTING_SERVICE.md`: diagnostico operacional do modo servico

## Atualizacao e preservacao de estado

O wizard nao interrompe o servico ao abrir. A parada ocorre em
`PrepareToInstall`, com destino definido e confirmacao do usuario. Se STOPPED
nao for confirmado, a instalacao nao copia arquivos. O contexto captura se o
servico estava rodando antes da parada; update iniciado pela UI reinicia esse
servico sem reinstalar nem alterar a conta.

A documentacao e empacotada preservando a arvore `docs/`; o atalho aponta para
`docs/install/installation_guide.md`, mantendo links relativos operacionais.
Detalhes do protocolo estao em [auto update](../docs/install/auto_update_setup.md)
e a matriz de homologacao em [testes](../docs/install/testing_auto_update.md).

## Padrao de linguagem

Nesta pasta o padrao passa a ser:

- scripts de manutencao local, build e release: Python
- scripts executados pelo instalador ou pela maquina Windows final: PowerShell

Hoje ja nao existe `.ps1` sobrando para migrar com seguranca. Todos os
PowerShell restantes pertencem ao runtime operacional do instalador ou da
maquina instalada:

- `check_dependencies.ps1`: distribuido em `{app}\tools` para a maquina final
- `install_service.ps1`: distribuido em `{app}\tools` para instalar o Windows Service
- `uninstall_service.ps1`: distribuido em `{app}\tools` para remover o Windows Service
- `capture_update_context.ps1`: executado pelo `setup.iss` durante update silencioso
- `restore_update_state.ps1`: executado pelo `setup.iss` apos update silencioso
- `merge_env.ps1`: executado pelo `setup.iss` no pos-install
- `encoding_utils.ps1`: dependencia compartilhada pelos scripts acima

Motivo: a maquina Windows de destino pode nao ter Python instalado, enquanto
PowerShell faz parte do baseline suportado pelo instalador.

Se surgir novo utilitario que rode apenas na maquina de desenvolvimento ou CI,
ele deve nascer em Python, nao em PowerShell.

## O que nao deve ser tratado como fonte

Estes caminhos sao artefatos locais, nao documentacao nem codigo-fonte:

- `installer\dist\`
- `installer\dependencies\` (exceto o `.gitkeep` versionado, que serve
  apenas para garantir a presenca da pasta no clone)
- `installer\__pycache__\`

`build_installer.py` recria dependencias locais quando necessario:

- `installer\dependencies\vc_redist.x64.exe`
- `installer\dependencies\winsw-2.12.0\BackupDatabaseService.exe`

Se voce precisar compilar o `setup.iss` manualmente, execute antes o
`build_installer.py` ou providencie esses arquivos por conta propria.

## Manual fallback

O caminho manual ainda existe para depuracao do `setup.iss`, mas nao e o fluxo
recomendado:

```powershell
python installer\update_version.py
dart run flutter_launcher_icons
flutter build windows --release
"C:\Program Files (x86)\Inno Setup 6\ISCC.exe" "D:\Developer\Flutter\backup_database\installer\setup.iss"
```

Ao trocar `database_512px.png`, o passo 2 regera `app_icon.ico` e copia para `app_tray.ico` automaticamente.

Icone de bandeja customizado: copie `assets\image\new\.tray_icon_custom.example` para `.tray_icon_custom` na mesma pasta; enquanto o marcador existir, o build nao sobrescreve `app_tray.ico`.

## Conteudo do instalador

O `setup.iss` empacota:

- binarios do app Flutter para Windows
- `.env.example` em `C:\ProgramData\BackupDatabase\config`
- guias operacionais basicos em `{app}\docs` (inclui `TROUBLESHOOTING_SERVICE.md`)
- `check_dependencies.ps1`
- `BackupDatabaseService.exe` (WinSW) e scripts de servico em `{app}\tools`

SO minimo: Windows 8 / Server 2012+ x64 (`MinVersion=6.2`). Auto-update
silencioso desabilitado em Server 2012 / 2012 R2.

O instalador oferece dois modos:

- `Server Mode`
- `Client Mode` (sem atalho de servico; `{app}\tools\install_service.ps1`
  ainda instala o servico se precisar)

IPC local: named pipe Win32; o instalador nao abre porta TCP para IPC.
Socket remoto: TCP 9527. Task opcional (desmarcada, so Server Mode) libera
a porta no Firewall (`Backup Database Remote Socket`). Sem a task, use
`netsh` manual.

Upgrade e overwrite nativo (`Flags: ignoreversion`): o setup nao
desinstala a versao anterior antes de copiar arquivos.

Uninstall: remove logs em `ProgramData\BackupDatabase\logs`; preserva
`.env`/staging/locks no silent; no wizard interativo pergunta se apaga
`C:\ProgramData\BackupDatabase` (padrao Nao).

O auto-update silencioso passa `/MODE=server` ou `/MODE=client` para o
Inno Setup preservar o modo no upgrade (a pagina customizada nao e
restaurada por `UsePreviousTasks`). Sem `/MODE=`, o setup le
`update_context.json` e, se faltar, `{app}\.install_mode`.

## Servico Windows

O servico usa WinSW e inicia o app com:

```text
--mode=server --minimized --run-as-service
```

Referencias operacionais:

- troubleshooting: `installer\TROUBLESHOOTING_SERVICE.md`
- comportamento do update: `docs\install\auto_update_setup.md`

Servicos NSSM existentes sao migrados sem delete/create e sem alterar a conta
ou senha. A configuracao XML, os limites de conversao, a recuperacao e a matriz
de homologacao estao em [migracao WinSW](../docs/install/winsw_migration.md).
Contas customizadas podem atualizar silenciosamente sob WinSW quando o token
do processo possui permissoes administrativas; caso contrario, use Setup elevado.
Assinatura Authenticode: procedimento em `docs\install\release_guide.md`;
`build_installer.py` nao chama `signtool`.

## Distribuicao

Antes de publicar uma release:

1. teste o `.exe` em uma VM limpa
2. valide instalacao, execucao, uninstall e logs
3. publique o `.exe` e o `.sha256` na release
4. confirme o workflow `update-appcast`

O guia operacional de release fica em `docs\install\release_guide.md`.
