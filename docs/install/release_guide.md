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

O instalador esperado e:

```text
installer\dist\BackupDatabase-Setup-3.0.2.exe
```

## 4. Publicar codigo

```powershell
git add pubspec.yaml installer/setup.iss .env .env.example
git commit -m "chore: bump version to 3.0.2"
git push origin main
```

## 5. Criar tag

```powershell
git tag v3.0.2
git push origin v3.0.2
```

## 6. Criar release no GitHub

1. Abra a pagina de releases
2. Selecione a tag `v3.0.2`
3. Anexe exatamente um instalador `.exe`
4. Use preferencialmente o nome `BackupDatabase-Setup-3.0.2.exe`
5. Nao marque como draft ou prerelease
6. Publique a release

## 7. Verificar o appcast

Depois da publicacao:

1. O workflow `.github/workflows/update-appcast.yml` executa
2. O script `scripts/sync_appcast_from_releases.py` reconstrui o `appcast.xml`
3. O feed passa a incluir `length` e `sha256`
4. O workflow faz commit do `appcast.xml` atualizado

## Regras importantes

- O feed aceita apenas releases publicadas.
- Cada release precisa ter exatamente um instalador `.exe` valido.
- O updater usa o hash `sha256` do feed para validar o instalador antes da troca.
- A configuracao ativa da maquina instalada fica em `C:\ProgramData\BackupDatabase\config\.env`.
