# Guia para Criar Release

Este guia explica como criar o primeiro release e os releases subsequentes no GitHub.

## Versão Atual

A versão atual do projeto é: **1.0.0+1** (definida em `pubspec.yaml`)

## Passo a Passo para Criar o Primeiro Release

### 1. Fazer Build do Executável

Execute o comando para gerar o executável Windows em modo release:

```bash
flutter build windows --release
```

O executável será gerado em:

```
build/windows/x64/runner/Release/backup_database.exe
```

**Nota**: O executável pode ter dependências (DLLs) na mesma pasta. Para distribuição, você pode precisar incluir todos os arquivos da pasta `Release` ou criar um instalador.

### 2. Preparar o Arquivo para Upload

**Opção A: Apenas o executável**

- Use apenas o arquivo `backup_database.exe`
- Renomeie para `backup_database-1.0.0.exe` (opcional, mas recomendado)

**Opção B: Pacote completo (recomendado)**

- Crie um arquivo ZIP com todos os arquivos da pasta `Release`
- Inclua: `backup_database.exe` e todas as DLLs necessárias
- Nome sugerido: `backup_database-1.0.0.zip`

### 3. Criar o Release no GitHub

1. Acesse: https://github.com/cesar-carlos/backup_database/releases

2. Clique em **"Create a new release"** (ou **"Draft a new release"**)

3. Preencha os campos:

   - **Choose a tag**: Digite `v1.0.0` e clique em **"Create new tag: v1.0.0 on publish"**
   - **Release title**: `Version 1.0.0`
   - **Description**: Adicione as notas da versão, por exemplo:

     ```
     ## Version 1.0.0

     Primeira versão do Backup Database.

     ### Funcionalidades
     - Backup automático para SQL Server e Sybase ASA
     - Suporte para múltiplos destinos (Local, FTP, Google Drive)
     - Agendamento de backups
     - Notificações por e-mail
     - Interface gráfica completa
     ```

4. **Arraste e solte** o arquivo `.exe` (ou `.zip`) na área de upload de assets

5. Marque **"Set as the latest release"** (se disponível)

6. Clique em **"Publish release"**

### 4. Verificar o GitHub Actions

Após publicar o release:

1. Acesse: https://github.com/cesar-carlos/backup_database/actions

2. Você verá um workflow chamado **"Update Appcast on Release"** em execução

3. Aguarde a conclusão (geralmente leva 1-2 minutos)

4. Verifique se o workflow foi bem-sucedido (ícone verde)

5. Se houver erro, clique no workflow para ver os detalhes

### 5. Verificar o appcast.xml Atualizado

1. Acesse: https://github.com/cesar-carlos/backup_database/blob/main/appcast.xml

2. Verifique se o novo item foi adicionado com:

   - Versão: `1.0.0`
   - URL do asset correta
   - Tamanho do arquivo correto
   - Data de publicação atual

3. Verifique via GitHub Pages (se configurado):
   - https://cesar-carlos.github.io/backup_database/appcast.xml

### 6. Testar a Atualização

1. Configure o `.env` com a URL do feed:

   ```env
   AUTO_UPDATE_FEED_URL=https://cesar-carlos.github.io/backup_database/appcast.xml
   ```

2. Execute o aplicativo

3. Verifique os logs para confirmar que está verificando atualizações

4. Teste a verificação manual (se disponível na interface)

## Criar Releases Futuros

Para criar novos releases:

1. **Atualize a versão no `pubspec.yaml`**:

   ```yaml
   version: 1.0.1+1 # Incremente conforme necessário
   ```

2. **Faça commit da mudança**:

   ```bash
   git add pubspec.yaml
   git commit -m "Bump version to 1.0.1"
   git push
   ```

3. **Faça build**:

   ```bash
   flutter build windows --release
   ```

4. **Crie o release no GitHub**:

   - Tag: `v1.0.1`
   - Título: `Version 1.0.1`
   - Upload do novo executável
   - Publique

5. **O GitHub Actions atualizará o `appcast.xml` automaticamente**

## Estrutura de Versão

O projeto usa o formato: `MAJOR.MINOR.PATCH+BUILD`

- **MAJOR**: Mudanças incompatíveis
- **MINOR**: Novas funcionalidades compatíveis
- **PATCH**: Correções de bugs
- **BUILD**: Número de build (geralmente incrementado automaticamente)

Exemplos:

- `1.0.0+1` → Tag: `v1.0.0`
- `1.0.1+1` → Tag: `v1.0.1`
- `1.1.0+1` → Tag: `v1.1.0`
- `2.0.0+1` → Tag: `v2.0.0`

## Checklist do Release

Antes de criar um release, verifique:

- [ ] Versão atualizada no `pubspec.yaml`
- [ ] Build executado com sucesso
- [ ] Executável testado localmente
- [ ] Notas da versão preparadas
- [ ] GitHub Pages configurado (se usar)
- [ ] Permissões do GitHub Actions configuradas
- [ ] `.env` configurado com a URL correta

## Solução de Problemas

### Workflow não executa

- Verifique se o release foi **publicado** (não apenas criado como draft)
- Verifique as permissões do GitHub Actions
- Verifique se há um arquivo `.exe` no release

### appcast.xml não atualiza

- Verifique os logs do GitHub Actions
- Confirme que o asset tem extensão `.exe`
- Verifique se o workflow tem permissão de escrita

### Erro ao baixar atualização

- Verifique se a URL do asset está correta no `appcast.xml`
- Confirme que o arquivo existe no release
- Verifique o tamanho do arquivo no `appcast.xml`

## Notas Importantes

- A tag do release deve ter o prefixo `v` (ex: `v1.0.0`)
- A versão no `appcast.xml` será sem o prefixo (ex: `1.0.0`)
- O workflow obtém automaticamente o tamanho do arquivo
- GitHub Pages pode levar alguns minutos para atualizar após o commit
- Sempre teste o executável antes de criar o release
