# Configuração de Atualização Automática

Este documento explica como configurar e testar o sistema de atualização automática.

> **Nota**: Para instruções de como testar o auto-update, consulte [testing_auto_update.md](testing_auto_update.md).
> **Nota**: Para instruções de como criar releases, consulte [release_guide.md](release_guide.md).

## Visão Geral

O sistema de atualização automática permite que o aplicativo verifique e instale atualizações automaticamente. Ele utiliza o pacote `auto_updater` baseado nas bibliotecas Sparkle (macOS) e WinSparkle (Windows).

## Opção Recomendada: GitHub Releases + GitHub Pages

Este projeto está configurado para usar **GitHub Releases** para hospedar os executáveis e **GitHub Pages** (ou GitHub Raw) para hospedar o `appcast.xml`. O sistema está automatizado via GitHub Actions para atualizar o `appcast.xml` automaticamente sempre que um release é criado.

### Configuração Inicial (Uma vez)

#### 1. Configurar GitHub Pages

1. Acesse: https://github.com/cesar-carlos/backup_database/settings/pages
2. Em "Source", selecione a branch `main` (ou `gh-pages` se preferir)
3. Em "Folder", selecione `/ (root)`
4. Clique em "Save"
5. Aguarde alguns minutos para o GitHub Pages ficar ativo
6. A URL será: `https://cesar-carlos.github.io/backup_database/appcast.xml`

#### 2. Verificar Permissões do GitHub Actions

1. Acesse: https://github.com/cesar-carlos/backup_database/settings/actions
2. Em "Workflow permissions", selecione "Read and write permissions"
3. Marque "Allow GitHub Actions to create and approve pull requests"
4. Salve as alterações

#### 3. Configurar Variável de Ambiente

Adicione a seguinte variável no arquivo `.env`:

```env
AUTO_UPDATE_FEED_URL=https://cesar-carlos.github.io/backup_database/appcast.xml
```

**Alternativa (GitHub Raw):**

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
```

### Fluxo de Trabalho Automatizado

1. **Fazer build do aplicativo:**

   ```bash
   flutter build windows --release
   ```

2. **Criar instalador:**

   Consulte `installer/README.md` para instruções completas.

3. **Criar um release no GitHub:**

   Consulte [release_guide.md](release_guide.md) para instruções detalhadas.

4. **GitHub Actions executa automaticamente:**

   - O workflow `.github/workflows/update-appcast.yml` detecta o release
   - Obtém informações do asset (URL, tamanho)
   - Atualiza o `appcast.xml` com a nova versão
   - Faz commit e push do arquivo atualizado

5. **Clientes recebem atualização:**
   - Na próxima verificação automática (a cada 1 hora)
   - Ou quando o usuário verificar manualmente

### Estrutura do appcast.xml

O arquivo `appcast.xml` é mantido automaticamente pelo GitHub Actions. Ele segue o formato Sparkle/WinSparkle:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Backup Database Updates</title>
    <link>https://github.com/cesar-carlos/backup_database/releases</link>
    <description>Atualizações do Backup Database</description>

    <item>
      <title>Version 1.0.1</title>
      <pubDate>Mon, 15 Jan 2024 10:00:00 +0000</pubDate>
      <description>
        <![CDATA[
          <h2>Nova Versão 1.0.1</h2>
          <p>Atualização automática via GitHub Release.</p>
        ]]>
      </description>
      <enclosure
        url="https://github.com/cesar-carlos/backup_database/releases/download/v1.0.1/backup_database-1.0.1.exe"
        sparkle:version="1.0.1"
        sparkle:os="windows"
        length="52428800"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

### Vantagens desta Abordagem

- **Automático**: Não precisa atualizar `appcast.xml` manualmente
- **Sem erros**: Tamanho e URL são obtidos automaticamente
- **Rastreável**: Cada release gera um commit no histórico
- **Gratuito**: GitHub oferece hospedagem gratuita
- **HTTPS**: GitHub usa HTTPS por padrão

## Configuração Básica (Método Manual)

Se preferir usar um servidor próprio ao invés do GitHub, siga as instruções abaixo.

### 1. Variável de Ambiente

Adicione no arquivo `.env`:

```env
AUTO_UPDATE_FEED_URL=https://seu-servidor.com/updates/appcast.xml
```

### 2. Estrutura do Feed (appcast.xml)

O feed de atualização deve seguir o formato Sparkle/WinSparkle.

**Elementos Importantes:**

- **`sparkle:version`**: Versão da atualização (deve ser maior que a versão atual)
- **`sparkle:os`**: Sistema operacional (`windows` para Windows)
- **`url`**: URL completa do arquivo executável de atualização
- **`length`**: Tamanho do arquivo em bytes
- **`pubDate`**: Data de publicação no formato RFC 822

### 3. Hospedagem dos Arquivos

**Requisitos:**

1. **Servidor Web**: O feed XML e os arquivos executáveis devem estar acessíveis via HTTP/HTTPS
2. **CORS**: Se necessário, configure CORS no servidor
3. **HTTPS Recomendado**: Use HTTPS para garantir segurança

**Estrutura de Diretórios Recomendada:**

```
servidor/
├── updates/
│   ├── appcast.xml
│   ├── backup_database-1.0.0.exe
│   └── backup_database-1.0.1.exe
```

## Funcionamento

### ⚠️ ATUALIZAÇÃO AUTOMÁTICA FORÇADA

**IMPORTANTE**: O aplicativo está configurado para **atualização automática FORÇADA**. Isso significa:

- ✅ **SEM prompts ao usuário**: Quando uma nova versão é detectada, a atualização é baixada e instalada automaticamente
- ✅ **Fechamento automático**: O aplicativo fecha automaticamente para instalar a atualização
- ✅ **Instalação silenciosa**: O instalador executa em modo `/SILENT` sem mostrar diálogos
- ✅ **Sempre atualizado**: Os usuários sempre terão a versão mais recente

### Verificação Automática

- O aplicativo verifica atualizações automaticamente na inicialização
- Verificações periódicas a cada 1 hora (3600 segundos)
- As verificações ocorrem em background
- **Quando uma atualização é encontrada, ela é baixada e instalada automaticamente**

### Verificação Manual

- Os usuários podem verificar atualizações manualmente através da página de Configurações
- Clique no botão de atualizar na seção "Atualizações"
- **Mesmo em verificação manual, a atualização é instalada automaticamente se disponível**

### Processo de Atualização (Automático)

1. O aplicativo verifica o feed XML
2. Compara a versão disponível com a versão atual
3. Se houver atualização disponível:
   - **Baixa automaticamente** o novo instalador
   - **Fecha o aplicativo** automaticamente
   - **Executa o instalador** em modo silencioso (`/SILENT`)
   - **Desinstala a versão anterior** automaticamente
   - **Instala a nova versão** automaticamente
4. Todo o processo ocorre **SEM interação do usuário**

### Comportamento do Instalador em Modo Silencioso

**Modo `/SILENT` (atualização automática):**

- ✅ Fecha o aplicativo automaticamente
- ✅ Desinstala a versão anterior automaticamente
- ✅ Instala a nova versão sem mostrar diálogos
- ✅ Não solicita permissões ou confirmações

**Modo manual (duplo clique):**

- ℹ️ Pergunta ao usuário se deseja fechar o aplicativo
- ℹ️ Mostra progresso da instalação
- ℹ️ Permite escolher opções (ícones, inicialização automática, etc.)
- ℹ️ Mostra tela de conclusão

## Solução de Problemas

### Atualizações não são detectadas

1. Verifique se a URL do feed está correta no arquivo `.env`
2. Verifique se o servidor está acessível
3. Verifique os logs do aplicativo
4. Confirme que o formato do XML está correto

### Erro ao baixar atualização

1. Verifique se a URL do arquivo executável está correta
2. Confirme que o arquivo existe no servidor
3. Verifique permissões de acesso ao servidor
4. Confirme que o tamanho do arquivo está correto

### GitHub Actions não executa

1. Verifique se as permissões do workflow estão configuradas
2. Verifique os logs do GitHub Actions
3. Confirme que o release foi publicado (não draft)

### appcast.xml não atualiza

1. Verifique se o asset do release tem extensão `.exe`
2. Verifique os logs do GitHub Actions
3. Confirme que o workflow tem permissão de escrita

## Documentação Relacionada

- **[testing_auto_update.md](testing_auto_update.md)**: Como testar o sistema de atualização
- **[release_guide.md](release_guide.md)**: Como criar releases no GitHub
- **installer/README.md**: Como criar o instalador
- **[release_guide.md](release_guide.md)**: Como criar releases e tags

## Notas Importantes

- A versão no `appcast.xml` deve seguir o formato semântico (ex: `1.0.1`)
- O aplicativo compara versões automaticamente
- Apenas versões mais recentes serão oferecidas para atualização
- Recomenda-se testar o feed antes de disponibilizar para usuários
- **GitHub**: A tag do release deve ter o prefixo `v` (ex: `v1.0.1`)
- **GitHub**: A versão no `appcast.xml` será sem o prefixo (ex: `1.0.1`)
- **GitHub**: O workflow obtém automaticamente o tamanho do arquivo
- **GitHub**: O `appcast.xml` é atualizado na branch `main` automaticamente
