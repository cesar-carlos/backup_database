# Guia para Criar Release

## 1. Atualizar a versao

Edite `pubspec.yaml`:

```yaml
version: 3.0.2
```

## 2. Sincronizar instalador e arquivos de ambiente

```powershell
python installer\update_version.py
```

Esse script sincroniza:

- `installer/setup.iss`
- `.env`
- `.env.example`

## 3. Gerar build e instalador

```powershell
flutter build windows --release
python installer\build_installer.py
```

Artefatos esperados:

```text
installer\dist\BackupDatabase-Setup-3.0.2.exe
installer\dist\BackupDatabase-Setup-3.0.2.exe.sha256
```

## 4. Publicar codigo

Use branch curta e PR. Evite push direto em `main`.

```powershell
git checkout -b codex/release-3.0.2
git add pubspec.yaml installer/setup.iss .env .env.example docs\install\release_guide.md
git commit -m "chore: bump version to 3.0.2"
git push origin codex/release-3.0.2
```

## 5. Criar tag

Depois do merge:

```powershell
git checkout main
git pull
git tag v3.0.2
git push origin v3.0.2
```

## 6. Criar release no GitHub

1. Abra a pagina de releases.
2. Selecione a tag `v3.0.2`.
3. Anexe exatamente um instalador `.exe`.
4. Anexe tambem o sidecar `.sha256` do mesmo instalador.
5. Use preferencialmente o nome `BackupDatabase-Setup-3.0.2.exe`.
6. Nao marque como draft ou prerelease.
7. Publique a release.

## 7. Verificar o appcast

Depois da publicacao:

1. O workflow `.github/workflows/update-appcast.yml` executa.
2. O script `scripts/sync_appcast_from_releases.py` reconstrui o `appcast.xml`.
3. O feed inclui `length` e `sha256`.
4. Se o release tiver sidecar `.sha256`, o script reutiliza esse hash e evita baixar o `.exe` inteiro.
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
