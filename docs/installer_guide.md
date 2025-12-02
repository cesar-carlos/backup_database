# Guia Completo - Criar e Distribuir Instalador

Este guia explica como criar o instalador do Backup Database e fazer upload para o GitHub Releases.

## Pré-requisitos

### 1. Inno Setup

Baixe e instale o **Inno Setup** (versão 6.0 ou superior):
- **Download**: https://jrsoftware.org/isdl.php
- **Versão recomendada**: Inno Setup 6.2.2 ou superior
- **Instalação**: Execute o instalador e siga as instruções

### 2. Build do Projeto

Certifique-se de que o projeto foi compilado:

```bash
flutter build windows --release
```

Os arquivos estarão em: `build\windows\x64\runner\Release\`

## Criar o Instalador

### Método 1: Via Interface Gráfica (Recomendado)

1. **Abra o Inno Setup Compiler**
   - Procure por "Inno Setup Compiler" no menu Iniciar
   - Ou navegue até: `C:\Program Files (x86)\Inno Setup 6\Compil32.exe`

2. **Abra o arquivo de script**
   - No Inno Setup, clique em **File > Open**
   - Navegue até: `D:\Developer\Flutter\backup_database\installer\setup.iss`
   - Abra o arquivo

3. **Compile o instalador**
   - Clique em **Build > Compile** (ou pressione `Ctrl+F9`)
   - Aguarde a compilação (pode levar alguns minutos)
   - O instalador será criado em: `installer\dist\BackupDatabase-Setup-1.0.0.exe`

### Método 2: Via Linha de Comando

```bash
# Navegue até a pasta do Inno Setup
cd "C:\Program Files (x86)\Inno Setup 6"

# Compile o script
ISCC.exe "D:\Developer\Flutter\backup_database\installer\setup.iss"
```

O instalador será criado em: `installer\dist\BackupDatabase-Setup-1.0.0.exe`

## Verificar o Instalador

Após criar o instalador:

1. **Verifique o tamanho**: Deve ser aproximadamente 50-100 MB
2. **Verifique o local**: `installer\dist\BackupDatabase-Setup-1.0.0.exe`
3. **Teste o instalador** (opcional, mas recomendado):
   - Execute o instalador em uma VM limpa
   - Verifique se a instalação funciona corretamente
   - Teste a desinstalação

## Onde Fazer Upload do Instalador

### GitHub Releases

O instalador deve ser enviado para o **GitHub Releases** junto com o release:

1. **Acesse a página de Releases**:
   - https://github.com/cesar-carlos/backup_database/releases

2. **Crie um novo release** (ou edite um existente):
   - Clique em **"Create a new release"**
   - Ou edite um release existente

3. **Preencha as informações**:
   - **Tag**: `v1.0.0` (ou a versão correspondente)
   - **Title**: `Version 1.0.0`
   - **Description**: Adicione as notas da versão

4. **Faça upload do instalador**:
   - Na seção **"Attach binaries"**
   - Arraste e solte o arquivo: `installer\dist\BackupDatabase-Setup-1.0.0.exe`
   - Ou clique e selecione o arquivo

5. **Publicar o release**:
   - Clique em **"Publish release"**
   - O GitHub Actions atualizará o `appcast.xml` automaticamente

## Estrutura de Arquivos no Release

Para cada release, você pode incluir:

1. **Instalador** (recomendado):
   - `BackupDatabase-Setup-1.0.0.exe`
   - Tamanho: ~50-100 MB
   - Inclui tudo necessário para instalação

2. **ZIP completo** (alternativa):
   - `backup_database-1.0.0.zip`
   - Tamanho: ~15-25 MB
   - Para usuários que preferem instalação manual

3. **Executável individual** (para auto-update):
   - `backup_database.exe`
   - Tamanho: ~75 KB
   - Usado pelo sistema de atualização automática

## Atualização Automática

O sistema de atualização automática funciona assim:

1. **O workflow do GitHub Actions** detecta o release publicado
2. **Procura por um arquivo `.exe`** nos assets do release
3. **Atualiza o `appcast.xml`** automaticamente com:
   - URL do asset `.exe`
   - Versão do release
   - Tamanho do arquivo

**Importante**: Para o auto-update funcionar, você precisa fazer upload de um arquivo `.exe` no release. O instalador não é usado para auto-update, apenas para instalação inicial.

## Recomendação: Incluir Ambos

Para melhor experiência do usuário, inclua no release:

1. **Instalador** (`BackupDatabase-Setup-1.0.0.exe`):
   - Para instalação inicial
   - Inclui todas as dependências
   - Interface gráfica de instalação

2. **Executável** (`backup_database.exe`):
   - Para atualização automática
   - Usado pelo sistema de auto-update
   - Menor tamanho

## Exemplo de Release Completo

```
Release: v1.0.0
Title: Version 1.0.0

Assets:
├── BackupDatabase-Setup-1.0.0.exe  (Instalador - 80 MB)
├── backup_database-1.0.0.zip        (ZIP completo - 15 MB)
└── backup_database.exe              (Executável - 75 KB) [para auto-update]
```

## Atualizar Versão do Instalador

Quando criar uma nova versão:

1. **Atualize o `pubspec.yaml`**:
   ```yaml
   version: 1.0.1+1
   ```

2. **Atualize o `installer/setup.iss`**:
   ```iss
   #define MyAppVersion "1.0.1"
   ```

3. **Recompile o instalador**

4. **Crie o novo release no GitHub**

## Checklist Antes de Publicar

- [ ] Projeto compilado (`flutter build windows --release`)
- [ ] Instalador criado (`installer\dist\BackupDatabase-Setup-1.0.0.exe`)
- [ ] Instalador testado (opcional, mas recomendado)
- [ ] Versão atualizada no `pubspec.yaml` e `setup.iss`
- [ ] Release criado no GitHub
- [ ] Instalador enviado para o release
- [ ] Executável `.exe` enviado para auto-update (opcional)
- [ ] GitHub Actions executado com sucesso
- [ ] `appcast.xml` atualizado automaticamente

## Solução de Problemas

### Erro ao compilar o instalador

- Verifique se o Inno Setup está instalado corretamente
- Verifique se o caminho do `setup.iss` está correto
- Verifique se os arquivos em `build\windows\x64\runner\Release\` existem

### Instalador muito grande

- Normal: Instaladores Flutter costumam ter 50-100 MB
- Use compressão LZMA (já configurado no `setup.iss`)

### Auto-update não funciona

- Verifique se há um arquivo `.exe` no release
- Verifique se o GitHub Actions executou com sucesso
- Verifique o `appcast.xml` atualizado
- Verifique a URL no `.env`

## Próximos Passos

Após criar o instalador:

1. **Teste o instalador** em uma VM limpa
2. **Crie o release no GitHub**
3. **Faça upload do instalador**
4. **Verifique o GitHub Actions**
5. **Teste o auto-update** (se configurado)

---

**Pronto para criar e distribuir seu instalador!**

