# Guia para Criar Release

## 1. Atualizar a versao

Edite `pubspec.yaml` com a proxima versao:

```yaml
version: <versao>
```

## 2. Sincronizar instalador e arquivos de ambiente

```powershell
python installer\update_version.py
```

Esse script sincroniza:

- `installer/setup.iss`
- `.env`
- `.env.example`
- `.env.client`
- `.env.server`

## 3. Gerar build e instalador

```powershell
python installer\build_installer.py
```

O script sincroniza `app_icon.ico` (exe, atalho, barra de tarefas) e recompila o app quando necessario. Se compilar so com Flutter, rode antes `dart run flutter_launcher_icons` e `flutter build windows --release`.

Icones: `database_512px.png` alimenta o `.exe` (`flutter_launcher_icons`); `app_tray.ico` e copiado do mesmo ICO para a bandeja pelo `build_installer.py` (salvo marcador `.tray_icon_custom`). O CI valida com `python scripts/verify_windows_icons.py`.

Artefatos esperados:

```text
installer\dist\BackupDatabase-Setup-<versao>.exe
installer\dist\BackupDatabase-Setup-<versao>.exe.sha256
```

## 4. Publicar codigo

Use branch curta e PR. Evite push direto em `main`.

```powershell
git checkout -b codex/release-<versao>
git add pubspec.yaml installer/setup.iss .env .env.example .env.client .env.server docs\install\release_guide.md
git commit -m "chore: bump version to <versao>"
git push origin codex/release-<versao>
```

## 5. Criar tag

Depois do merge:

```powershell
git checkout main
git pull
git tag v<versao>
git push origin v<versao>
```

## 6. Criar release no GitHub

1. Abra a pagina de releases.
2. Selecione a tag `v<versao>`.
3. Anexe exatamente um instalador `.exe`.
4. Anexe tambem o sidecar `.sha256` do mesmo instalador.
5. Use preferencialmente o nome `BackupDatabase-Setup-<versao>.exe`.
6. Nao marque como draft ou prerelease.
7. Publique a release.

## 7. Verificar o appcast

Depois da publicacao:

1. O workflow `.github/workflows/update-appcast.yml` executa.
2. O script `scripts/sync_appcast_from_releases.py` reconstrui o `appcast.xml`.
3. O feed inclui `length` e `sha256`.
4. O release precisa ter sidecar `.sha256`; sem ele o rebuild do feed falha.
5. O workflow faz commit do `appcast.xml` atualizado.

## Rollback rapido do feed

Se precisar retirar uma release do auto update sem apagar a release do GitHub:

1. Edite [scripts/appcast_policy.json](/D:/Developer/Flutter/backup_database/scripts/appcast_policy.json)
2. Adicione a versao em `blocked_versions`
3. Faça push na `main`
4. O workflow `update-appcast` sera reexecutado e removera a versao do feed

## Regras importantes

- O feed aceita apenas releases publicadas.
- Cada release precisa ter exatamente um instalador `.exe` valido.
- O updater usa o hash `sha256` do feed para validar o instalador antes da troca.
- A configuracao ativa da maquina instalada fica em `C:\ProgramData\BackupDatabase\config\.env`.
- Alterar `.env` dentro da pasta do aplicativo nao muda o runtime da maquina instalada.
- Nesta rodada, auto update silencioso em modo servico so e suportado quando o Windows Service esta em `LocalSystem`.
- Antes de abrir o PR, confirme a versao real em `pubspec.yaml` e reaproveite esse mesmo valor em branch, tag e nome do instalador.
