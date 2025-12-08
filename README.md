# Backup Database

Sistema completo de backup automático para SQL Server e Sybase SQL Anywhere (ASA) no Windows.

## 🎯 Funcionalidades

### Backup de Bancos de Dados

- ✅ SQL Server (via `sqlcmd`)
- ✅ Sybase SQL Anywhere 16 (via `dbbackup.exe`)
- ✅ Compressão ZIP automática
- ✅ Verificação de integridade
- ✅ Verificação de espaço em disco

### Destinos de Backup

- ✅ Local (diretório do sistema)
- ✅ FTP/FTPS
- ✅ Google Drive (via OAuth2)
- ✅ Limpeza automática de backups antigos

### Agendamento

- ✅ Agendamento diário, semanal, mensal
- ✅ Agendamento por intervalo (horas)
- ✅ Execução em background
- ✅ Integração com Windows Task Scheduler

### Notificações

- ✅ E-mail (SMTP)
- ✅ Notificação de sucesso, erro e avisos
- ✅ Anexo automático de logs
- ✅ Templates personalizados

### Interface

- ✅ Dashboard com estatísticas
- ✅ Configuração de bancos de dados
- ✅ Configuração de destinos
- ✅ Gerenciamento de agendamentos
- ✅ Visualização e exportação de logs
- ✅ Tema claro/escuro
- ✅ System tray com menu de contexto

## 🖥️ Requisitos do Sistema

- **Windows**: 10 ou superior / Windows Server 2012 R2 ou superior
- **Arquitetura**: 64 bits apenas
- **SQL Server**: Qualquer versão com `sqlcmd` instalado
- **Sybase ASA**: Versão 16 com `dbbackup.exe`
- **.NET**: Runtime necessário para execução

## 📦 Instalação

### 1. Download

Baixe o instalador da [página de releases](https://github.com/seu-usuario/backup_database/releases).

### 2. Instalação

Execute o instalador e siga as instruções na tela.

### 3. Configuração Inicial

1. Execute o aplicativo
2. Configure as conexões com os bancos de dados
3. Configure os destinos de backup
4. Crie agendamentos de backup
5. (Opcional) Configure notificações por e-mail

## ⚙️ Configuração

### Variáveis de Ambiente

Crie um arquivo `.env` na raiz do aplicativo (ou use `.env.example` como base):

```env
# API Keys (se necessário)
GOOGLE_CLIENT_ID=seu_client_id
GOOGLE_CLIENT_SECRET=seu_client_secret

# FTP (opcional)
FTP_DEFAULT_PORT=21
FTPS_DEFAULT_PORT=990

# Logs
LOG_LEVEL=info
```

### SQL Server

1. Acesse **Configurações > SQL Server**
2. Clique em **Nova Configuração**
3. Preencha:
   - Nome da configuração
   - Servidor
   - Porta (padrão: 1433)
   - Nome do banco
   - Usuário e senha
4. Teste a conexão
5. Salve

### Sybase SQL Anywhere

1. Acesse **Configurações > Sybase**
2. Clique em **Nova Configuração**
3. Preencha:
   - Nome da configuração
   - Caminho do `dbbackup.exe`
   - Nome do banco
   - Parâmetros adicionais
4. Teste a conexão
5. Salve

### Destinos de Backup

#### Local

1. Acesse **Destinos > Novo Destino**
2. Tipo: **Local**
3. Informe o caminho do diretório
4. Configure retenção (dias)

#### FTP

1. Acesse **Destinos > Novo Destino**
2. Tipo: **FTP**
3. Preencha:
   - Servidor
   - Porta
   - Usuário e senha
   - Diretório remoto
   - SSL/TLS (se necessário)

#### Google Drive

1. Acesse **Destinos > Novo Destino**
2. Tipo: **Google Drive**
3. Clique em **Autenticar com Google**
4. Autorize o aplicativo
5. Escolha a pasta de destino

### Agendamentos

1. Acesse **Agendamentos > Novo Agendamento**
2. Preencha:
   - Nome
   - Banco de dados (previamente configurado)
   - Tipo de agendamento (diário, semanal, mensal, intervalo)
   - Horário/dias
   - Destinos (um ou mais)
   - Opções (compressão, retenção, etc.)
3. Salve

### E-mail (Notificações)

1. Acesse **Configurações > E-mail**
2. Preencha:
   - Servidor SMTP
   - Porta
   - Usuário e senha
   - Remetente
   - Destinatários
3. Configure quando enviar (sucesso, erro, avisos)
4. Teste a configuração
5. Salve

## 🚀 Uso

### Executar Backup Manual

1. Acesse **Agendamentos**
2. Selecione o agendamento
3. Clique em **Executar Agora**

Ou via System Tray:

1. Clique com botão direito no ícone na bandeja
2. Selecione **Executar Backup Agora**

### Visualizar Logs

1. Acesse **Logs**
2. Use filtros (nível, categoria, data, busca)
3. Exporte logs (TXT, JSON, CSV)

### Histórico de Backups

1. Acesse **Histórico**
2. Visualize todos os backups realizados
3. Filtre por status, banco, data
4. Exporte relatórios

## 🔧 Linha de Comando

### Executar Backup Específico

```bash
backup_database.exe --schedule-id=<schedule_id>
```

### Iniciar Minimizado

```bash
backup_database.exe --minimized
```

## 🪟 Windows Service

O Backup Database pode ser instalado como serviço do Windows usando o **NSSM (Non-Sucking Service Manager)**. Isso permite que o aplicativo execute automaticamente em background, mesmo sem usuário logado.

### Pré-requisitos

1. **Instalar o aplicativo** normalmente (via instalador)
2. **Configurar backups** antes de instalar como serviço:
   - Configurar conexões com bancos de dados
   - Configurar destinos de backup
   - Criar agendamentos de backup
   - (Opcional) Configurar notificações por e-mail

### Instalação do NSSM

1. Baixe o NSSM: https://nssm.cc/download
2. Extraia o arquivo ZIP
3. Copie `nssm.exe` (versão 64-bit) para uma pasta no PATH ou use o caminho completo

### Instalação do Serviço

Execute os seguintes comandos no **PowerShell como Administrador**:

```bash
# 1. Instalar o serviço (com --minimized recomendado)
nssm install BackupDatabaseService "C:\Program Files\Backup Database\backup_database.exe" --minimized

# 2. Configurar diretório de trabalho
nssm set BackupDatabaseService AppDirectory "C:\Program Files\Backup Database"

# 3. Configurar nome de exibição
nssm set BackupDatabaseService DisplayName "Backup Database Service"

# 4. Configurar descrição
nssm set BackupDatabaseService Description "Serviço de backup automático para SQL Server e Sybase"

# 5. Configurar para iniciar automaticamente
nssm set BackupDatabaseService Start SERVICE_AUTO_START

# 6. (Opcional) Configurar usuário do serviço
# Use uma conta de usuário com permissões adequadas para acessar bancos de dados
nssm set BackupDatabaseService ObjectName ".\UsuarioLocal" "SenhaDoUsuario"

# 7. Iniciar o serviço
nssm start BackupDatabaseService
```

**Nota**: Ajuste o caminho `"C:\Program Files\Backup Database"` se você instalou em outro local.

### O que Funciona como Serviço

✅ **Funciona perfeitamente**:

- Execução automática de backups agendados
- Verificação de agendamentos a cada minuto
- Envio de notificações por e-mail
- Geração de logs em `C:\ProgramData\BackupDatabase\logs\`
- Acesso a bancos de dados SQL Server e Sybase
- Upload para FTP e Google Drive

⚠️ **Limitações**:

- Interface gráfica pode não ser acessível (mas não é necessária)
- System tray pode não funcionar corretamente
- Para acessar a interface, execute o aplicativo normalmente (ele detectará o serviço rodando)

### Gerenciamento do Serviço

```bash
# Verificar status
nssm status BackupDatabaseService

# Parar o serviço
nssm stop BackupDatabaseService

# Iniciar o serviço
nssm start BackupDatabaseService

# Reiniciar o serviço
nssm restart BackupDatabaseService

# Ver logs do serviço
nssm get BackupDatabaseService AppStdout
nssm get BackupDatabaseService AppStderr

# Remover o serviço
nssm remove BackupDatabaseService confirm
```

### Verificação

Após instalar o serviço, verifique:

1. **Status do serviço**:

   ```bash
   nssm status BackupDatabaseService
   ```

   Deve retornar: `SERVICE_RUNNING`

2. **Logs do aplicativo**:

   - Verifique os logs em: `C:\ProgramData\BackupDatabase\logs\`
   - Procure por: `"Serviço de agendamento iniciado"`

3. **Teste um backup**:
   - Aguarde o próximo horário agendado ou
   - Execute manualmente via interface gráfica

### Solução de Problemas

**Serviço não inicia**:

- Verifique se o caminho do executável está correto
- Verifique permissões do usuário do serviço
- Verifique logs em `C:\ProgramData\BackupDatabase\logs\`

**Backups não executam**:

- Verifique se os agendamentos estão habilitados
- Verifique se o serviço está rodando: `nssm status BackupDatabaseService`
- Verifique os logs do aplicativo

**Erro de permissões**:

- Configure o serviço para rodar com uma conta de usuário que tenha acesso aos bancos de dados
- Use: `nssm set BackupDatabaseService ObjectName ".\Usuario" "Senha"`

### Desinstalação

Para remover o serviço:

```bash
# Parar o serviço
nssm stop BackupDatabaseService

# Remover o serviço
nssm remove BackupDatabaseService confirm
```

**Importante**: Remover o serviço não desinstala o aplicativo. Use o desinstalador normal para remover o aplicativo completamente.

## 📁 Estrutura de Diretórios

```
C:\ProgramData\BackupDatabase\
├── logs/              # Logs do aplicativo
├── temp/              # Arquivos temporários
└── database.db        # Banco de dados local (SQLite)
```

## 🧪 Testes

Para executar os testes:

```bash
flutter test
```

Com cobertura:

```bash
flutter test --coverage
```

## 🏗️ Build

Para gerar o executável Windows:

```bash
flutter build windows --release
```

O executável estará em: `build/windows/x64/runner/Release/backup_database.exe`

## 📝 Logs

Logs são armazenados em:

- **Windows**: `C:\ProgramData\BackupDatabase\logs\`
- **Retenção**: 90 dias (configurável)
- **Níveis**: DEBUG, INFO, WARNING, ERROR
- **Categorias**: EXECUTION, SYSTEM, DATABASE, NETWORK

## 🛟 Suporte

Para reportar bugs ou solicitar funcionalidades, abra uma [issue](https://github.com/seu-usuario/backup_database/issues).

## 📄 Licença

Este projeto está licenciado sob a licença MIT - veja o arquivo [LICENSE](LICENSE) para mais detalhes.

## 🏛️ Arquitetura

O projeto segue **Clean Architecture** com **Domain-Driven Design (DDD)**:

- **Domain**: Entidades, use cases, interfaces
- **Application**: Serviços, providers
- **Infrastructure**: Repositórios, data sources, external services
- **Presentation**: UI, páginas, widgets

### Tecnologias Utilizadas

- **Flutter**: Framework UI
- **Drift**: ORM SQLite
- **Dio**: HTTP client
- **Get It**: Dependency injection
- **Provider**: State management
- **Go Router**: Navegação
- **Mailer**: E-mail
- **FTPConnect**: FTP
- **Google APIs**: Google Drive
- **Result Dart**: Error handling
- **Window Manager**: Gerenciamento de janelas
- **Tray Manager**: System tray
- **Cron**: Agendamento

## 👥 Contribuindo

Contribuições são bem-vindas! Por favor:

1. Fork o projeto
2. Crie uma branch para sua feature (`git checkout -b feature/MinhaFeature`)
3. Commit suas mudanças (`git commit -m 'Adiciona MinhaFeature'`)
4. Push para a branch (`git push origin feature/MinhaFeature`)
5. Abra um Pull Request

## 📸 Screenshots

(Adicionar screenshots aqui)

## ⚠️ Notas Importantes

- Sempre teste backups em ambiente de teste antes de usar em produção
- Mantenha backups em múltiplos destinos
- Verifique regularmente a integridade dos backups
- Configure notificações para ser alertado sobre falhas
- Mantenha o aplicativo atualizado

---

**Desenvolvido para facilitar backups no Windows**
