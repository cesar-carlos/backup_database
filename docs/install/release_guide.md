# Guia para Criar Release

## 1. Atualizar a versao

Edite `pubspec.yaml` com a proxima versao:

```yaml
version: <versao>
```

O formato deve ser `<major>.<minor>.<patch>[+build]`. O `update_version.py` falha cedo se nao bater com esse regex.

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

Esse script roda apenas em Windows (depende do Inno Setup + PowerShell para inspecionar `VersionInfo` do `.exe`). Em outros sistemas falha cedo com mensagem clara.

O script sincroniza `app_icon.ico` (exe, atalho, barra de tarefas) e recompila o app quando necessario. Se compilar so com Flutter, rode antes `dart run flutter_launcher_icons` e `flutter build windows --release`.

Icones: `database_512px.png` alimenta o `.exe` (`flutter_launcher_icons`); `app_tray.ico` e copiado do mesmo ICO para a bandeja pelo `build_installer.py` (salvo marcador `.tray_icon_custom`). O CI valida com `python scripts/verify_windows_icons.py`.

### Gate de icones embutidos no `.exe`

A partir da release 3.4.0, `build_installer.py` roda
`scripts/verify_windows_icons.py --require-exe` em dois pontos:

1. logo apos `flutter build windows --release` (passo 3)
2. imediatamente antes do `ISCC` empacotar o instalador (passo 7)

A flag `--require-exe` exige que o PNG de `windows/runner/resources/app_icon.ico`
apareca dentro do `backup_database.exe`. Falha de verify aqui significa que o
binario foi compilado com o icone antigo — abortar a release e investigar antes
de continuar.

Para integracoes externas (PR comments, dashboards), `verify_windows_icons.py`
aceita `--json` e devolve `{"ok": bool, "errors": [...]}` em stdout.

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
6. Nao marque como draft ou prerelease (o script de sync os ignora).
7. Publique a release.

> **Cuidado**: editar uma release publicada para virar `prerelease` faz o
> proximo rebuild do appcast remover o item; clientes que ainda nao
> baixaram a versao a perdem. Se for necessario tirar uma release do ar
> sem apaga-la, use `blocked_versions` (ver "Rollback rapido").

## 7. Verificar o appcast

Depois da publicacao:

1. O workflow `.github/workflows/update-appcast.yml` executa.
2. O script `scripts/sync_appcast_from_releases.py` reconstroi o `appcast.xml`.
3. O feed inclui `length` e `sha256`.
4. O release precisa ter sidecar `.sha256`; sem ele o rebuild do feed falha.
5. O workflow faz commit do `appcast.xml` atualizado.
6. Quando `scripts/appcast_policy.json` tem `rollout_percentages`, `min_supported_app_version` ou `min_publication_age_minutes`, o XML gerado reflete a policy. Confira se os atributos esperados estao no enclosure.

## Rollback rapido do feed

Se precisar retirar uma release do auto update sem apagar a release do GitHub:

1. Edite [scripts/appcast_policy.json](/D:/Developer/Flutter/backup_database/scripts/appcast_policy.json)
2. Adicione a versao em `blocked_versions`
3. Faca push na `main`
4. O workflow `update-appcast` sera reexecutado e removera a versao do feed

## Schema de `scripts/appcast_policy.json`

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

- `blocked_versions` — array de versoes (com ou sem prefixo `v`) que devem ser ocultadas.
- `min_supported_app_version` — string `x.y.z`. Vira atributo `sparkle:minSupportedAppVersion` no enclosure. Clientes com versao corrente menor que esse valor nao aplicam a release.
- `rollout_percentages` — mapa `{ "<versao>": 0-100 }`. Cliente decide participacao via FNV-1a(`<targetVersion>:<MachineGuid>`).
- `min_publication_age_minutes` — segura a release fora do feed ate atingir N minutos de idade desde `published_at`. Util para janelas de observacao.

## Manutencao emergencial: `update_appcast_manual.py`

Este utilitario esta marcado como **DEPRECATED** mas continua disponivel para emergencias. Agora exige `--sha256` (sem o hash o runtime descartaria o item silenciosamente):

```powershell
python scripts\update_appcast_manual.py 3.5.0 https://github.com/.../BackupDatabase-Setup-3.5.0.exe 39020908 --sha256 <hex64>
```

Prefira sempre o fluxo oficial via `sync_appcast_from_releases.py`.

## Regras importantes

- O feed aceita apenas releases publicadas.
- Cada release precisa ter exatamente um instalador `.exe` valido.
- O updater usa o hash `sha256` do feed para validar o instalador antes da troca.
- A configuracao ativa da maquina instalada fica em `C:\ProgramData\BackupDatabase\config\.env`.
- Alterar `.env` dentro da pasta do aplicativo nao muda o runtime da maquina instalada.
- Auto update silencioso em modo servico so e suportado quando o Windows Service esta em `LocalSystem` (ou aliases `System` / `NT AUTHORITY\SYSTEM`).
- Antes de abrir o PR, confirme a versao real em `pubspec.yaml` e reaproveite esse mesmo valor em branch, tag e nome do instalador.
