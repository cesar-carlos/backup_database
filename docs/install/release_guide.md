# Guia para Criar Release

Este guia consolida o processo completo de criação de releases: versão, tags, build, instalador e publicação no GitHub.

## Versão Atual

A versão do projeto é definida em `pubspec.yaml` (ex.: 2.2.7).

## Formato de Tags

As tags seguem o padrão **`v{VERSÃO}`**:

- A versão vem do `pubspec.yaml` (campo `version`)
- O prefixo `v` é obrigatório
- Exemplo: versão `2.2.7` → tag `v2.2.7`

## Processo Completo (Recomendado)

### 1. Atualizar Versão

Edite `pubspec.yaml`:

```yaml
version: 2.2.7
```

### 2. Sincronizar Versão

```powershell
python installer\update_version.py
```

Este script atualiza `installer/setup.iss` e `.env` automaticamente.

### 3. Build e Instalador

```bash
flutter build windows --release
python installer\build_installer.py
```

O instalador será criado em `installer\dist\BackupDatabase-Setup-2.2.7.exe`.

### 4. Commit e Push

```bash
git add pubspec.yaml installer/setup.iss .env
git commit -m "chore: bump version to 2.2.7"
git push origin main
```

### 5. Criar Tag e Enviar

```bash
git tag v2.2.7
git push origin v2.2.7
```

### 6. Criar Release no GitHub

1. Acesse: https://github.com/cesar-carlos/backup_database/releases
2. Clique em **"Create a new release"**
3. Selecione a tag `v2.2.7`
4. Título: `Version 2.2.7`
5. Adicione descrição com as mudanças
6. Arraste o instalador (`BackupDatabase-Setup-2.2.7.exe`) para upload
7. Marque **"Set as the latest release"**
8. Clique em **"Publish release"**

### 7. Verificar GitHub Actions

1. Acesse: https://github.com/cesar-carlos/backup_database/actions
2. O workflow **"Update Appcast on Release"** executará automaticamente
3. Aguarde conclusão (1–2 minutos)
4. O `appcast.xml` será atualizado para o auto-update

## Estrutura de Versão

Formato: `MAJOR.MINOR.PATCH+BUILD`

| Parte | Uso |
|-------|-----|
| MAJOR | Mudanças incompatíveis |
| MINOR | Novas funcionalidades compatíveis |
| PATCH | Correções de bugs |
| BUILD | Número de build (opcional) |

Exemplos: `2.2.7` → `v2.2.7`, `2.2.8` → `v2.2.8`

## Comandos Rápidos

```bash
# Sincronizar versão
python installer\update_version.py

# Commit e push
git add pubspec.yaml installer/setup.iss .env
git commit -m "chore: bump version to 2.2.7"
git push origin main

# Tag e push
git tag v2.2.7
git push origin v2.2.7
```

Depois, crie o release manualmente no GitHub e faça upload do instalador.

## Scripts Relacionados

| Script | Propósito |
|--------|-----------|
| `installer/update_version.py` | Sincroniza versão em setup.iss e .env |
| `installer/build_installer.py` | Build Flutter + compila instalador Inno Setup |

## Verificação de Tags

```bash
git tag                    # Listar tags locais
git ls-remote --tags origin  # Listar tags no GitHub
git show v2.2.7            # Ver detalhes de uma tag
```

## Solução de Problemas

### Tag já existe

```bash
git tag -d v2.2.7
git push origin --delete v2.2.7
git tag v2.2.7
git push origin v2.2.7
```

### Workflow não executa

- Verifique se o release foi **publicado** (não draft)
- Confirme que há um asset `.exe` anexado
- Verifique permissões do GitHub Actions (Read and write)

### appcast.xml não atualiza

- Verifique os logs do GitHub Actions
- Confirme que o asset tem extensão `.exe`
- GitHub Pages pode levar alguns minutos para propagar

## Checklist

- [ ] Versão atualizada no `pubspec.yaml`
- [ ] `update_version.py` executado
- [ ] Build Flutter e instalador criados
- [ ] Executável testado localmente
- [ ] Commit e push realizados
- [ ] Tag criada e enviada
- [ ] Release publicado no GitHub com instalador
- [ ] GitHub Actions executou com sucesso




