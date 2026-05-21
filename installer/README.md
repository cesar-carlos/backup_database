# Installer

Esta pasta concentra o empacotamento Windows do Backup Database. O fluxo
principal hoje e `python installer\build_installer.py`; o restante da pasta
existe para suportar esse caminho ou a manutencao do `setup.iss`.

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

O `build_installer.py` ja encontra `ISCC.exe` nos caminhos padrao do Inno
Setup 6. Se o compilador nao estiver instalado, o script falha com instrucao
objetiva.

## Arquivos relevantes

- `setup.iss`: definicao do instalador, atalhos, tasks e migracao pos-update
- `build_installer.py`: pipeline local de build do instalador
- `update_version.py`: sincroniza versao entre `pubspec.yaml`, `setup.iss` e `.env`
- `check_dependencies.ps1`: utilitario opcional distribuido com o app para validar CLIs dos bancos suportados
- `install_service.ps1`: instala o app como Windows Service via NSSM
- `uninstall_service.ps1`: remove o Windows Service
- `capture_update_context.ps1`: captura contexto operacional antes do update silencioso
- `restore_update_state.ps1`: restaura UI ou Windows Service depois do update
- `merge_env.ps1`: mescla `.env.example` com a configuracao persistida da maquina
- `encoding_utils.ps1`: helper UTF-8 sem BOM usado pelos scripts PowerShell
- `TROUBLESHOOTING_SERVICE.md`: diagnostico operacional do modo servico

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
- `installer\dependencies\`
- `installer\__pycache__\`

`build_installer.py` recria dependencias locais quando necessario:

- `installer\dependencies\vc_redist.x64.exe`
- `installer\dependencies\nssm-2.24\win64\nssm.exe`

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
- guias operacionais basicos em `{app}\docs`
- `check_dependencies.ps1`
- `nssm.exe` e scripts de servico em `{app}\tools`

O instalador oferece dois modos:

- `Server Mode`
- `Client Mode`

## Servico Windows

O servico continua baseado em NSSM e inicia o app com:

```text
--mode=server --minimized --run-as-service
```

Referencias operacionais:

- troubleshooting: `installer\TROUBLESHOOTING_SERVICE.md`
- comportamento do update: `docs\install\auto_update_setup.md`

Importante: update silencioso do servico so e restaurado automaticamente
quando a conta do Windows Service e `LocalSystem`.

## Distribuicao

Antes de publicar uma release:

1. teste o `.exe` em uma VM limpa
2. valide instalacao, execucao, uninstall e logs
3. publique o `.exe` e o `.sha256` na release
4. confirme o workflow `update-appcast`

O guia operacional de release fica em `docs\install\release_guide.md`.
