# Guia de Criação de Tags

Este guia explica como criar tags para releases do projeto Backup Database.

## Formato de Tags

As tags seguem o padrão: **`v{VERSÃO}`**

- A versão vem do `pubspec.yaml` (campo `version`)
- O prefixo `v` é obrigatório
- Exemplo: Se a versão é `1.0.19`, a tag será `v1.0.19`

## Processo de Criação de Tag

### 1. Verificar Versão Atual

Verifique a versão no `pubspec.yaml`:

```yaml
version: 1.0.19
```

### 2. Sincronizar Versão (Opcional mas Recomendado)

Antes de criar a tag, sincronize a versão com os arquivos do instalador:

```powershell
powershell -ExecutionPolicy Bypass -File installer\update_version.ps1
```

Este script:

- Lê a versão do `pubspec.yaml`
- Atualiza `installer\setup.iss` (campo `#define MyAppVersion`)
- Atualiza `.env` (campo `APP_VERSION`)

### 3. Criar a Tag Localmente

```bash
git tag v1.0.19
```

Ou com mensagem:

```bash
git tag -a v1.0.19 -m "Release version 1.0.19"
```

### 4. Enviar Tag para GitHub

```bash
git push origin v1.0.19
```

Ou para enviar todas as tags:

```bash
git push origin --tags
```

## Processo Completo (Recomendado)

### Passo a Passo Completo

1. **Atualizar versão no `pubspec.yaml`** (se necessário):

   ```yaml
   version: 1.0.19
   ```

2. **Sincronizar versão**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File installer\update_version.ps1
   ```

3. **Fazer commit das mudanças** (se houver):

   ```bash
   git add pubspec.yaml installer/setup.iss .env
   git commit -m "Bump version to 1.0.19"
   ```

4. **Fazer merge com main** (se estiver em outra branch):

   ```bash
   git checkout main
   git merge feature/nome-da-branch
   ```

5. **Fazer push para GitHub**:

   ```bash
   git push origin main
   ```

6. **Criar e enviar a tag**:

   ```bash
   git tag v1.0.19
   git push origin v1.0.19
   ```

7. **Criar Release no GitHub** (via interface web):
   - Acesse: https://github.com/cesar-carlos/backup_database/releases
   - Clique em "Create a new release"
   - Selecione a tag `v1.0.19` (ou crie uma nova)
   - Adicione título: `Version 1.0.19`
   - Adicione descrição com as mudanças
   - Faça upload do instalador (se disponível)
   - Publique o release

## Relação entre Versão e Tag

### Estrutura de Versão

O formato no `pubspec.yaml` é: `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR**: Mudanças incompatíveis (ex: `1.0.19` → `2.0.0`)
- **MINOR**: Novas funcionalidades compatíveis (ex: `1.0.19` → `1.1.0`)
- **PATCH**: Correções de bugs (ex: `1.0.19` → `1.0.20`)
- **BUILD**: Número de build (geralmente incrementado automaticamente)

### Exemplos de Tags

| Versão no pubspec.yaml | Tag Git   | Release GitHub |
| ---------------------- | --------- | -------------- |
| `1.0.19`               | `v1.0.19` | `v1.0.19`      |
| `1.0.20`               | `v1.0.20` | `v1.0.20`      |
| `1.1.0`                | `v1.1.0`  | `v1.1.0`       |
| `2.0.0`                | `v2.0.0`  | `v2.0.0`       |

**Importante**: A tag usa apenas `MAJOR.MINOR.PATCH`, ignorando o `+BUILD`.

## Verificação de Tags

### Listar Tags Locais

```bash
git tag
```

### Listar Tags no GitHub

```bash
git ls-remote --tags origin
```

### Verificar Tag Específica

```bash
git show v1.0.19
```

## Integração com GitHub Actions

O projeto possui um workflow (`.github/workflows/update-appcast.yml`) que:

1. **Detecta novos releases** automaticamente
2. **Extrai a tag** do release (formato `v1.0.19`)
3. **Remove o prefixo `v`** para obter a versão (`1.0.19`)
4. **Atualiza o `appcast.xml`** automaticamente
5. **Faz commit** das mudanças no `appcast.xml`

### Requisitos para o Workflow Funcionar

- A tag deve ter o prefixo `v` (ex: `v1.0.19`)
- O release deve ser **publicado** (não apenas criado como draft)
- O release deve ter um asset `.exe` anexado
- O workflow precisa ter permissões de escrita no repositório

## Scripts Relacionados

### `installer/update_version.ps1`

Sincroniza a versão do `pubspec.yaml` com:

- `installer/setup.iss` (campo `#define MyAppVersion`)
- `.env` (campo `APP_VERSION`)

### `installer/build_installer.ps1`

Script automatizado que:

1. Executa `update_version.ps1` para sincronizar versão
2. Verifica se o build do Flutter existe
3. Compila o instalador usando Inno Setup

### `scripts/sync_appcast_from_releases.ps1`

Sincroniza o `appcast.xml` com todos os releases do GitHub:

- Busca releases via API do GitHub
- Extrai tags e versões
- Atualiza o `appcast.xml` com informações dos releases

## Checklist para Criar Tag

Antes de criar uma tag, verifique:

- [ ] Versão atualizada no `pubspec.yaml`
- [ ] Versão sincronizada com `installer/setup.iss` (via `update_version.ps1`)
- [ ] Todas as mudanças commitadas
- [ ] Merge com `main` realizado (se necessário)
- [ ] Push para GitHub realizado
- [ ] Tag criada localmente (`git tag v1.0.19`)
- [ ] Tag enviada para GitHub (`git push origin v1.0.19`)
- [ ] Release criado no GitHub (via interface web)
- [ ] Instalador anexado ao release (se disponível)
- [ ] GitHub Actions executado com sucesso
- [ ] `appcast.xml` atualizado automaticamente

## Comandos Rápidos

### Criar Tag e Release Rápido

```bash
# 1. Sincronizar versão
powershell -ExecutionPolicy Bypass -File installer\update_version.ps1

# 2. Commit (se necessário)
git add pubspec.yaml installer/setup.iss .env
git commit -m "Bump version to 1.0.19"
git push origin main

# 3. Criar e enviar tag
git tag v1.0.19
git push origin v1.0.19
```

Depois, crie o release manualmente no GitHub via interface web.

## Solução de Problemas

### Tag já existe

Se a tag já existir, você pode:

1. **Deletar tag local**:

   ```bash
   git tag -d v1.0.19
   ```

2. **Deletar tag no GitHub**:

   ```bash
   git push origin --delete v1.0.19
   ```

3. **Recriar a tag**:
   ```bash
   git tag v1.0.19
   git push origin v1.0.19
   ```

### Versão não sincronizada

Se a versão não estiver sincronizada:

```powershell
powershell -ExecutionPolicy Bypass -File installer\update_version.ps1
```

### GitHub Actions não executou

Verifique:

- O release foi **publicado** (não apenas criado como draft)?
- O release tem um asset `.exe` anexado?
- As permissões do GitHub Actions estão configuradas?
- O workflow está habilitado?

## Notas Importantes

1. **Sempre use o prefixo `v`** nas tags (ex: `v1.0.19`)
2. **A versão no `appcast.xml`** será sem o prefixo (ex: `1.0.19`)
3. **O workflow remove automaticamente** o prefixo `v` da tag
4. **Sincronize sempre a versão** antes de criar o instalador
5. **Crie o release no GitHub** após criar a tag para que o workflow funcione
