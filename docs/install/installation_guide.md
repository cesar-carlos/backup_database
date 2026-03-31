# Guia de Instalação - Backup Database

Este guia passo a passo irá ajudá-lo a instalar o **Backup Database** no Windows.

---

## Pré-requisitos

Antes de começar, certifique-se de ter:

1. **Windows 8 ou superior / Windows Server 2012 ou superior** (64 bits)
2. **Permissões de Administrador** para instalação
3. **Conexão com a Internet** (para baixar dependências, se necessário)
4. **Espaço em disco** suficiente (mínimo 500 MB)

Para verificar todos os requisitos detalhados, consulte [requirements.md](requirements.md).

---

## Passo 1: Download do Instalador

1. Baixe o arquivo `BackupDatabase-Setup-{versão}.exe` da [página de releases](https://github.com/cesar-carlos/backup_database/releases)
2. Salve o arquivo em um local de fácil acesso (ex: `Downloads`)

---

## Passo 2: Executar o Instalador

1. **Localize o arquivo** do instalador (ex.: `BackupDatabase-Setup-2.2.7.exe`)
2. **Clique com o botão direito** no arquivo
3. Selecione **"Executar como administrador"**
4. Se aparecer o **Controle de Conta de Usuário (UAC)**, clique em **"Sim"**

---

## Passo 3: Assistente de Instalação

### 3.1 Tela de Boas-vindas

- Clique em **"Avançar"** para continuar

### 3.2 Licença

- Leia os termos de licença
- Se concordar, marque **"Aceito o acordo"**
- Clique em **"Avançar"**

### 3.3 Localização de Instalação

- O instalador sugere: `C:\Program Files\Backup Database`
- Para instalar em outro local, clique em **"Procurar"** e escolha a pasta
- Clique em **"Avançar"**

### 3.4 Componentes Adicionais

O instalador pode mostrar opções para:

- **Criar ícone na área de trabalho**: Marque se desejar um atalho na área de trabalho
- **Criar ícone na barra de tarefas**: Marque se desejar um atalho na barra de tarefas
- **Iniciar com o Windows**: Marque se desejar que o aplicativo inicie automaticamente

Selecione as opções desejadas e clique em **"Avançar"**

### 3.5 Verificação de Dependências

O instalador irá verificar automaticamente:

- **Visual C++ Redistributables**: Se não estiver instalado, o instalador tentará instalar automaticamente

**Nota**: As ferramentas de backup (`sqlcmd` para SQL Server e `dbbackup`/`dbisql` para Sybase) não são verificadas durante a instalação, pois o usuário pode querer usar apenas SQL Server ou apenas Sybase. Você pode verificar essas ferramentas manualmente após a instalação usando o script "Verificar Dependências" no menu Iniciar.

### 3.6 Pronto para Instalar

- Revise as opções selecionadas
- Clique em **"Instalar"** para começar a instalação

### 3.7 Instalação em Andamento

- Aguarde enquanto os arquivos são copiados
- Se o Visual C++ Redistributables precisar ser instalado, isso será feito automaticamente
- **Não feche** a janela durante a instalação

### 3.8 Instalação Concluída

- Marque **"Executar Backup Database"** se desejar iniciar o aplicativo agora
- Clique em **"Concluir"**

---

## Passo 4: Configuração Inicial

### 4.1 Primeira Execução

1. Se você marcou para executar, o aplicativo será iniciado automaticamente
2. Caso contrário, localize o ícone **"Backup Database"** no menu Iniciar e execute

### 4.2 Configurar Dependências (se necessário)

Se você viu avisos sobre dependências faltando durante a instalação:

#### Para SQL Server (sqlcmd):

1. **Se você já tem SQL Server instalado**:
   - Verifique se `sqlcmd.exe` está no PATH
   - Consulte [path_setup.md](path_setup.md) para instruções

2. **Se você não tem SQL Server instalado**:
   - Baixe e instale o **SQL Server Command Line Utilities**
   - Link: https://go.microsoft.com/fwlink/?linkid=2230791
   - Adicione o caminho de instalação ao PATH

#### Para Sybase (dbbackup):

1. **Instale o Sybase SQL Anywhere** (se ainda não tiver)
2. **Localize a pasta `Bin64`** na instalação
3. **Adicione o caminho ao PATH** do sistema
4. Consulte [path_setup.md](path_setup.md) para instruções detalhadas

### 4.3 Verificar Instalação

Para verificar se tudo está funcionando:

1. Abra o **Prompt de Comando** ou **PowerShell**
2. Execute os seguintes comandos:

```cmd
REM Verificar sqlcmd (SQL Server)
sqlcmd -?

REM Verificar dbbackup (Sybase)
dbbackup -?
```

Se ambos os comandos mostrarem a ajuda, está tudo configurado!

---

## Passo 5: Configurar o Aplicativo

Agora você pode configurar o Backup Database:

1. **Configurar conexões com bancos de dados**:
   - SQL Server: Vá em **Configurações > SQL Server**
   - Sybase: Vá em **Configurações > Sybase**

2. **Configurar destinos de backup**:
   - Local: Vá em **Configurações > Destinos**
   - FTP: Configure servidor FTP
   - Google Drive: Configure autenticação OAuth2

3. **Criar agendamentos**:
   - Vá em **Agendamentos**
   - Clique em **"Novo Agendamento"**
   - Configure a frequência e horários

4. **Configurar notificações** (opcional):
   - Vá em **Configurações > Notificações**
   - Configure servidor SMTP para e-mails

---

## Desinstalação

Para desinstalar o Backup Database:

### Método 1: Via Painel de Controle

1. Abra o **Painel de Controle**
2. Vá em **Programas e Recursos**
3. Encontre **"Backup Database"**
4. Clique em **"Desinstalar"**
5. Siga as instruções na tela

### Método 2: Via Menu Iniciar

1. Abra o **Menu Iniciar**
2. Encontre **"Backup Database"**
3. Clique com o botão direito
4. Selecione **"Desinstalar"**

### O que é removido

- Arquivos do aplicativo
- Atalhos e ícones
- Configurações de inicialização automática
- **NÃO remove**: Logs, backups e configurações salvas (ficam em `C:\ProgramData\BackupDatabase\`)

---

## Problemas Comuns na Instalação

### "Você precisa de permissões de administrador"

**Solução**:

1. Feche o instalador
2. Clique com o botão direito no arquivo `.exe`
3. Selecione **"Executar como administrador"**

### "Visual C++ Redistributables falhou ao instalar"

**Solução**:

1. Baixe manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe
2. Execute o instalador como administrador
3. Tente instalar o Backup Database novamente

### "Erro ao copiar arquivos"

**Possíveis causas**:

- Antivírus bloqueando
- Permissões insuficientes
- Disco cheio

**Solução**:

1. Desative temporariamente o antivírus
2. Execute como administrador
3. Verifique espaço em disco
4. Tente novamente

### "Antivírus bloqueando durante teste de conexão (FTP, Nextcloud, etc.)"

**Causa**: Falso positivo comum com aplicativos que fazem conexões de rede legítimas.

**Solução**:

1. Adicione uma exceção no seu antivírus para a pasta de instalação
2. Adicione uma exceção para o arquivo `backup_database.exe` (se necessário)
3. O Backup Database é um aplicativo legítimo - as conexões de rede são necessárias para armazenar backups em servidores remotos

### "Aplicativo não inicia após instalação"

**Solução**:

1. Verifique se o Visual C++ Redistributables está instalado
2. Verifique os logs em: `C:\ProgramData\BackupDatabase\logs\`
3. Tente executar como administrador
4. Reinstale o aplicativo

---

## Próximos Passos

Após a instalação bem-sucedida:

1. ✅ Leia a [documentação de requisitos](requirements.md)
2. ✅ Configure o PATH se necessário ([path_setup.md](path_setup.md))
3. ✅ Se o antivírus bloquear conexões, adicione uma exceção para a pasta de instalação e para `backup_database.exe` (se necessário)
4. ✅ Configure suas conexões de banco de dados
5. ✅ Crie seus primeiros agendamentos de backup
6. ✅ Teste um backup manual antes de confiar nos agendamentos

---

## Suporte

Se você encontrar problemas durante a instalação:

1. Consulte a [documentação de requisitos](requirements.md)
2. Verifique os logs em: `C:\ProgramData\BackupDatabase\logs\`
3. Abra uma issue no repositório do projeto com:
   - Versão do Windows
   - Mensagens de erro
   - Logs relevantes

---

**Boa sorte com seus backups! 🎉**
