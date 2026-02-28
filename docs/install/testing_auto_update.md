# Guia de Teste - Sistema de Auto-Atualização

Este guia explica como testar o sistema de atualização automática do Backup Database.

## Pré-requisitos

1. **Arquivo `.env` configurado** na raiz do projeto:
   ```env
   AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
   ```

2. **GitHub Pages configurado** (opcional, mas recomendado):
   - Acesse: https://github.com/cesar-carlos/backup_database/settings/pages
   - Selecione branch `main` e folder `/ (root)`

## Como Testar

### Método 1: Teste Manual na Interface

1. **Execute o aplicativo:**
   ```bash
   flutter run -d windows
   ```

2. **Acesse a página de Configurações:**
   - Clique em "Configurações" no menu lateral

3. **Verifique a seção "Atualizações":**
   - Se o serviço estiver inicializado, você verá:
     - Status: "Atualizações Automáticas Ativas"
     - URL do feed
     - Botão "Verificar Atualizações" (ícone de refresh)

4. **Clique no botão de atualizar:**
   - O aplicativo verificará o `appcast.xml`
   - Se houver atualização disponível, uma janela será exibida
   - Se não houver atualização, nenhuma janela aparecerá (comportamento normal)

### Método 2: Teste com Versão de Desenvolvimento

Para testar se uma atualização é detectada, você precisa criar uma versão mais nova:

1. **Atualize a versão no `pubspec.yaml`:**
   ```yaml
   version: 2.2.8+1  # Versão maior que a atual (ex.: 2.2.7)
   ```

2. **Faça build:**
   ```bash
   flutter build windows --release
   ```

3. **Crie o instalador:**
   - Compile o instalador Inno Setup
   - O arquivo será: `installer\dist\BackupDatabase-Setup-2.2.8.exe`

4. **Crie um novo release no GitHub:**
   - Tag: `v2.2.8`
   - **IMPORTANTE**: Marque como "Set as the latest release" (não como Pre-release)
   - Faça upload do novo instalador
   - Publique o release

5. **Aguarde o workflow executar:**
   - Acesse: https://github.com/cesar-carlos/backup_database/actions
   - Verifique se o workflow "Update Appcast on Release" foi executado
   - Aguarde alguns minutos para o `appcast.xml` ser atualizado

6. **Teste no aplicativo:**
   - Execute a versão 2.2.7 do aplicativo
   - Vá em Configurações > Atualizações
   - Clique em "Verificar Atualizações"
   - Uma janela deve aparecer oferecendo a atualização para 2.2.8

### Método 3: Verificar Logs

1. **Execute o aplicativo com logs:**
   ```bash
   flutter run -d windows
   ```

2. **Verifique os logs no console:**
   - Procure por mensagens como:
     - `AutoUpdateService inicializado com feed URL: ...`
     - `Verificando atualizações...`
     - `Erro ao verificar atualizações: ...` (se houver erro)

3. **Verifique os logs do aplicativo:**
   - Os logs também são salvos em arquivo (verifique a documentação de logs)

## Verificações Importantes

### 1. Verificar se o appcast.xml foi atualizado

Acesse a URL do feed no navegador:
- GitHub Raw: https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
- GitHub Pages: https://cesar-carlos.github.io/backup_database/appcast.xml

O arquivo deve conter um `<item>` com informações do release:
```xml
<item>
  <title>Version 1.0.0</title>
  <pubDate>...</pubDate>
  <enclosure
    url="https://github.com/cesar-carlos/backup_database/releases/download/v1.0.0/BackupDatabase-Setup-1.0.0.exe"
    sparkle:version="1.0.0"
    sparkle:os="windows"
    length="13107923"
    type="application/octet-stream" />
</item>
```

### 2. Verificar se o workflow foi executado

1. Acesse: https://github.com/cesar-carlos/backup_database/actions
2. Procure pelo workflow "Update Appcast on Release"
3. Verifique se foi executado com sucesso (ícone verde)
4. Se falhou, clique para ver os detalhes do erro

### 3. Verificar permissões do GitHub Actions

1. Acesse: https://github.com/cesar-carlos/backup_database/settings/actions
2. Em "Workflow permissions", deve estar:
   - "Read and write permissions" selecionado
   - "Allow GitHub Actions to create and approve pull requests" marcado

## Problemas Comuns

### O workflow não executou

**Causa**: O release foi criado como "Pre-release"

**Solução**: 
1. Edite o release no GitHub
2. Desmarque "Set as a pre-release"
3. Salve as alterações
4. O workflow deve executar automaticamente

### O appcast.xml está vazio

**Causa**: O workflow não encontrou o arquivo `.exe` no release

**Solução**:
1. Verifique se o arquivo `.exe` foi anexado ao release
2. Verifique se o nome do arquivo termina com `.exe`
3. Re-execute o workflow manualmente (se possível) ou crie um novo release

### Erro "AUTO_UPDATE_FEED_URL não configurada"

**Causa**: O arquivo `.env` não existe ou não contém a variável

**Solução**:
1. Crie o arquivo `.env` na raiz do projeto
2. Adicione: `AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml`
3. Reinicie o aplicativo

### Erro ao verificar atualizações

**Causa**: URL do feed inacessível ou formato XML inválido

**Solução**:
1. Teste a URL no navegador
2. Verifique se o XML está bem formatado
3. Verifique os logs do aplicativo para mais detalhes

## Teste Completo (Passo a Passo)

### Passo 1: Preparar ambiente

1. Certifique-se de que o arquivo `.env` existe e está configurado
2. Verifique se o GitHub Pages está configurado (opcional)

### Passo 2: Criar release inicial (1.0.0)

1. Crie um release no GitHub com tag `v1.0.0`
2. **IMPORTANTE**: NÃO marque como Pre-release
3. Faça upload do instalador `BackupDatabase-Setup-1.0.0.exe`
4. Publique o release

### Passo 3: Verificar workflow

1. Aguarde 1-2 minutos
2. Acesse: https://github.com/cesar-carlos/backup_database/actions
3. Verifique se o workflow foi executado com sucesso
4. Verifique se o `appcast.xml` foi atualizado

### Passo 4: Testar no aplicativo

1. Execute a versão 1.0.0 do aplicativo
2. Vá em Configurações > Atualizações
3. Clique em "Verificar Atualizações"
4. Se tudo estiver correto, não deve aparecer nenhuma atualização (você já está na versão mais recente)

### Passo 5: Criar versão de teste (1.0.1)

1. Atualize `pubspec.yaml` para versão `1.0.1+2`
2. Faça build: `flutter build windows --release`
3. Crie o instalador
4. Crie um novo release com tag `v1.0.1`
5. Publique o release (não como Pre-release)
6. Aguarde o workflow atualizar o `appcast.xml`

### Passo 6: Testar detecção de atualização

1. Execute a versão 1.0.0 do aplicativo (a versão antiga)
2. Vá em Configurações > Atualizações
3. Clique em "Verificar Atualizações"
4. Uma janela deve aparecer oferecendo a atualização para 1.0.1
5. Teste o download e instalação

## Notas Importantes

- O workflow só executa quando um release é **publicado** (não Pre-release)
- O `appcast.xml` pode levar alguns minutos para atualizar após o workflow executar
- O aplicativo verifica atualizações automaticamente na inicialização
- Verificações periódicas ocorrem a cada 1 hora (3600 segundos)
- A versão no `appcast.xml` deve corresponder à tag do release (sem o prefixo `v`)

