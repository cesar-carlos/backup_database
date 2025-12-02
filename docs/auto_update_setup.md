# Configuração de Atualização Automática

Este documento explica como configurar o sistema de atualização automática do aplicativo usando `auto_updater`.

## Visão Geral

O sistema de atualização automática permite que o aplicativo verifique e instale atualizações automaticamente. Ele utiliza o pacote `auto_updater` que é baseado nas bibliotecas Sparkle (macOS) e WinSparkle (Windows).

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

2. **Criar um release no GitHub:**
   - Acesse: https://github.com/cesar-carlos/backup_database/releases
   - Clique em "Create a new release"
   - Crie uma tag: `v1.0.1` (use o prefixo `v` seguido da versão)
   - Título: "Version 1.0.1"
   - Descrição: Adicione notas da versão
   - Faça upload do arquivo `.exe` (ex: `backup_database-1.0.1.exe`)
   - Marque como "Set as the latest release"
   - Clique em "Publish release"

3. **GitHub Actions executa automaticamente:**
   - O workflow `.github/workflows/update-appcast.yml` detecta o release
   - Obtém informações do asset (URL, tamanho)
   - Atualiza o `appcast.xml` com a nova versão
   - Faz commit e push do arquivo atualizado

4. **Clientes recebem atualização:**
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

Se preferir usar um servidor próprio ao invés do GitHub, siga as instruções abaixo:

### 1. Variável de Ambiente

Adicione a seguinte variável no arquivo `.env`:

```env
AUTO_UPDATE_FEED_URL=https://seu-servidor.com/updates/appcast.xml
```

Substitua `https://seu-servidor.com/updates/appcast.xml` pela URL do seu feed de atualização.

### 2. Estrutura do Feed (appcast.xml)

O feed de atualização deve seguir o formato Sparkle/WinSparkle. Exemplo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Backup Database Updates</title>
    <link>https://seu-servidor.com/updates</link>
    <description>Atualizações do Backup Database</description>

    <item>
      <title>Version 1.0.1</title>
      <pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
      <description>
        <![CDATA[
          <h2>Nova Versão 1.0.1</h2>
          <ul>
            <li>Correção de bugs</li>
            <li>Melhorias de performance</li>
          </ul>
        ]]>
      </description>
      <enclosure
        url="https://seu-servidor.com/updates/backup_database-1.0.1.exe"
        sparkle:version="1.0.1"
        sparkle:os="windows"
        length="52428800"
        type="application/octet-stream" />
    </item>

    <item>
      <title>Version 1.0.0</title>
      <pubDate>Mon, 01 Dec 2023 00:00:00 +0000</pubDate>
      <enclosure
        url="https://seu-servidor.com/updates/backup_database-1.0.0.exe"
        sparkle:version="1.0.0"
        sparkle:os="windows"
        length="51200000"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

### Elementos Importantes

- **`sparkle:version`**: Versão da atualização (deve ser maior que a versão atual)
- **`sparkle:os`**: Sistema operacional (`windows` para Windows)
- **`url`**: URL completa do arquivo executável de atualização
- **`length`**: Tamanho do arquivo em bytes
- **`pubDate`**: Data de publicação no formato RFC 822

## Hospedagem dos Arquivos (Método Manual)

### Requisitos

1. **Servidor Web**: O feed XML e os arquivos executáveis devem estar acessíveis via HTTP/HTTPS
2. **CORS**: Se necessário, configure CORS no servidor para permitir requisições do aplicativo
3. **HTTPS Recomendado**: Use HTTPS para garantir a segurança das atualizações

### Estrutura de Diretórios Recomendada

```
servidor/
├── updates/
│   ├── appcast.xml
│   ├── backup_database-1.0.0.exe
│   ├── backup_database-1.0.1.exe
│   └── backup_database-1.0.2.exe
```

### Atualização Manual do appcast.xml

Quando usar um servidor próprio, você precisa atualizar o `appcast.xml` manualmente a cada nova versão:

1. Adicione um novo `<item>` no início do arquivo
2. Atualize a versão, URL, tamanho e data
3. Faça upload do novo executável
4. Faça upload do `appcast.xml` atualizado

## Assinatura de Atualizações (Opcional)

Para maior segurança, você pode assinar os arquivos de atualização. Isso requer:

1. **OpenSSL instalado** no Windows
2. **Chaves geradas** usando o comando:
   ```bash
   dart run auto_updater:generate_keys
   ```

As chaves geradas devem ser mantidas em segurança e usadas para assinar cada atualização.

## Funcionamento

### Verificação Automática

- O aplicativo verifica atualizações automaticamente na inicialização
- Verificações periódicas a cada 1 hora (3600 segundos)
- As verificações ocorrem em background e não bloqueiam a interface

### Verificação Manual

- Os usuários podem verificar atualizações manualmente através da página de Configurações
- Clique no botão de atualizar na seção "Atualizações"

### Processo de Atualização

1. O aplicativo verifica o feed XML
2. Compara a versão disponível com a versão atual
3. Se houver atualização disponível, notifica o usuário
4. O usuário pode iniciar o download e instalação
5. O WinSparkle gerencia o download e a instalação automaticamente

## Solução de Problemas

### Atualizações não são detectadas

1. Verifique se a URL do feed está correta no arquivo `.env`
2. Verifique se o servidor está acessível
3. Verifique os logs do aplicativo para erros de rede
4. Confirme que o formato do XML está correto

### Erro ao baixar atualização

1. Verifique se a URL do arquivo executável está correta
2. Confirme que o arquivo existe no servidor
3. Verifique permissões de acesso ao servidor
4. Confirme que o tamanho do arquivo (`length`) está correto

### Verificação não funciona

1. Verifique se `AUTO_UPDATE_FEED_URL` está configurada
2. Verifique os logs do aplicativo
3. Confirme que o formato do XML está válido
4. Teste a URL do feed em um navegador

## Exemplo Completo (Método Manual)

### Arquivo .env

```env
AUTO_UPDATE_FEED_URL=https://exemplo.com/updates/appcast.xml
```

### Arquivo appcast.xml no servidor

```xml
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Backup Database Updates</title>
    <link>https://exemplo.com/updates</link>
    <description>Atualizações do Backup Database</description>

    <item>
      <title>Version 1.0.1</title>
      <pubDate>Mon, 15 Jan 2024 10:00:00 +0000</pubDate>
      <enclosure
        url="https://exemplo.com/updates/backup_database-1.0.1.exe"
        sparkle:version="1.0.1"
        sparkle:os="windows"
        length="52428800"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
```

### Estrutura no servidor

```
https://exemplo.com/
└── updates/
    ├── appcast.xml
    └── backup_database-1.0.1.exe
```

## Solução de Problemas Específicos do GitHub

### GitHub Actions não executa

1. Verifique se as permissões do workflow estão configuradas corretamente
2. Verifique os logs do GitHub Actions em: https://github.com/cesar-carlos/backup_database/actions
3. Confirme que o release foi publicado (não apenas criado como draft)

### appcast.xml não atualiza

1. Verifique se o asset do release tem extensão `.exe`
2. Verifique os logs do GitHub Actions para erros
3. Confirme que o workflow tem permissão de escrita no repositório

### GitHub Pages não atualiza

1. GitHub Pages pode levar alguns minutos para atualizar após o commit
2. Verifique se o GitHub Pages está ativado nas configurações
3. Teste a URL diretamente no navegador: `https://cesar-carlos.github.io/backup_database/appcast.xml`

## Notas Importantes

- A versão no `appcast.xml` deve seguir o formato semântico (ex: `1.0.1`)
- O aplicativo compara versões automaticamente
- Apenas versões mais recentes serão oferecidas para atualização
- O processo de atualização pode requerer privilégios de administrador no Windows
- Recomenda-se testar o feed antes de disponibilizar para usuários
- **GitHub**: A tag do release deve ter o prefixo `v` (ex: `v1.0.1`), mas a versão no `appcast.xml` será sem o prefixo (ex: `1.0.1`)
- **GitHub**: O workflow obtém automaticamente o tamanho do arquivo do asset do release
- **GitHub**: O `appcast.xml` é atualizado na branch `main` automaticamente
