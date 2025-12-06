# Plano Completo – Sistema de Backup Dart/Flutter

## 🎯 Objetivo Geral

Desenvolver um sistema multiplataforma em **Dart/Flutter** para Windows e Windows Server (64 bits), capaz de realizar **backups automáticos** de bancos **SQL Server** e **Sybase SQL Anywhere (ASA)**, com envio para destinos locais e remotos, incluindo notificações por e-mail.

---

## 🧩 Problema a Ser Solucionado

Usuários precisam de uma ferramenta confiável que permita:

- Realizar backup completo de bases SQL Server e Sybase ASA
- Criar agendamentos automáticos
- Enviar arquivos para:
  - Disco local
  - FTP
  - Google Drive
- Receber notificações por e-mail sobre sucesso, erro ou alertas
- Gerenciar logs e históricos dos backups

---

## 🛠️ 1. Requisitos Técnicos

### 1.1 Linguagem / Framework

- Dart
- Flutter (Desktop – Windows 64 bits)

### 1.2 Banco de Dados Suportados

- SQL Server (utilizando `sqlcmd`)
- Sybase SQL Anywhere 16 (utilizando `dbbackup.exe`)

### 1.3 Sistema Operacional

- Windows 10 ou superior (64 bits)
- Windows Server 2012 R2 ou superior (64 bits)
- Plataforma: **Somente 64 bits**
- Compatível com ambientes de servidor (execução como serviço)

#### Considerações para Windows Server

- Execução como serviço do Windows (Windows Service)
- Suporte a execução sem interface gráfica (modo headless)
- Permissões adequadas para acesso a bancos de dados e sistema de arquivos
- Compatibilidade com políticas de grupo e segurança do Windows Server
- Logs de eventos do Windows integrados

### 1.4 Dependências Principais

#### Navegação e Rotas

- `go_router` - Gerenciamento de rotas e navegação declarativa

#### Requisições HTTP

- `dio` - Cliente HTTP para requisições (Google Drive API, FTP, etc.)

#### Injeção de Dependências

- `get_it` - Service locator para injeção de dependências

#### Gerenciamento de Estado

- `provider` - Gerenciamento de estado da aplicação

#### Formatação e Máscaras

- `brasil_fields` - Formatação de datas, CPF, CNPJ, CEP e outras máscaras brasileiras

#### Variáveis de Ambiente

- `flutter_dotenv` - Gerenciamento de variáveis de ambiente (.env)

#### Identificadores

- `uuid` - Geração de IDs únicos (UUID)

#### Validação

- `zard` - Validação de modelos e schemas

#### Controle de Janelas e System Tray

- `window_manager` - Criação e controle de janelas do sistema
- `tray_manager` - Gerenciamento de ícone na bandeja do sistema (System Tray) do Windows
- `single_instance` - Controle de instância única do aplicativo (apenas uma instância por computador)

#### Envio de E-mail

- `flutter_email_sender` - Envio de e-mails via cliente de e-mail do sistema

#### Execução de Processos do Sistema

- `process` - Execução de processos do sistema (sqlcmd, dbbackup.exe)
- `process_run` - Execução avançada de processos com melhor controle

#### Integração com Google Drive

- `googleapis` - Cliente para APIs do Google (Google Drive API)
- `google_sign_in` - Autenticação OAuth2 com Google

#### Seleção de Arquivos e Pastas

- `file_picker` - Seleção de arquivos e pastas do sistema

#### Logging

- `logger` - Logging estruturado e configurável

#### Integração com Windows

- `win32` - Integração com APIs do Windows (Event Log, serviços, etc.)

#### Formatação e Internacionalização

- `intl` - Formatação de datas, números e internacionalização

#### Agendamento

- `cron` - Agendamento de tarefas com expressões cron
- `timezone` - Suporte a fusos horários para agendamentos

#### Manipulação de Arquivos e Caminhos

- `path` - Manipulação de caminhos de arquivos (já incluído no Dart SDK)
- `file` - Operações de arquivo (já incluído no Dart SDK)

#### FTP (Upload de Arquivos)

- `dio` pode ser usado para FTP básico, mas para funcionalidades avançadas considerar:
- `ftpconnect` - Cliente FTP completo com suporte a FTPS (opcional)

#### Outras Dependências

- `sqflite` ou `drift` - Persistência local (SQLite)
- `path_provider` - Acesso a diretórios do sistema
- `crypto` - Criptografia de senhas
- `archive` - Compressão ZIP
- `workmanager` ou `flutter_background_service` - Execução em background

#### Dependências Opcionais

- `flutter_local_notifications` - Notificações do sistema Windows (opcional)
- `connectivity_plus` - Verificação de conectividade de rede (opcional)
- `shared_preferences` - Armazenamento simples de preferências (opcional, já temos SQLite)

---

## 🔧 2. Funcionalidades Obrigatórias

### 2.1 Execução de Backup

- Backup manual e automático
- Suporte a múltiplas bases de dados
- Verificação de integridade do arquivo gerado
- Compressão ZIP opcional
- Retenção configurável de backups antigos
- Validação de espaço em disco antes da execução

### 2.2 Destinos de Backup

#### 2.2.1 Local

- Escolha de pasta de destino
- Nome automático baseado em data/hora e nome da base
- Criação automática de subpastas por data
- Limpeza automática de backups antigos (configurável)

#### 2.2.2 FTP

- Upload automático após backup local
- Configuração de host, porta, usuário, senha
- Pasta remota configurável
- Suporte a FTP e FTPS
- Retry automático em caso de falha

#### 2.2.3 Google Drive

- Autenticação OAuth2
- Upload automático para pasta configurada
- Gerenciamento de tokens de acesso
- Suporte a múltiplas contas (opcional)

---

## 🕒 3. Agendamento de Backup

### 3.1 Tipos de Agendamento

- **Diário**: Execução em horário fixo todos os dias
- **Semanal**: Execução em dias específicos da semana
- **Mensal**: Execução em dias específicos do mês
- **Intervalos**: Execução a cada X horas/minutos
- **Personalizado**: Combinação de regras acima

### 3.2 Execução

- Execução via serviço interno do Flutter
- Integração opcional com Windows Task Scheduler
- Execução como serviço do Windows (Windows Service) para ambientes de servidor
- Execução em background mesmo com aplicativo fechado
- Suporte a execução sem interface gráfica (headless) para servidores
- Notificação de execução agendada (opcional)
- **Comportamento ao minimizar**: Quando a janela é minimizada, a aplicação continua rodando em segundo plano com ícone na bandeja do sistema (System Tray)
  - Backups agendados continuam executando normalmente
  - Ícone na bandeja permite restaurar a janela ou acessar menu de contexto
  - Opção de iniciar minimizada diretamente na bandeja
- **Instância única**: Apenas uma instância do programa pode estar em execução por computador
  - Tentativas de abrir segunda instância restauram e trazem para frente a janela da instância existente
  - Previne conflitos e execuções duplicadas de backups agendados

---

## 🗂️ 4. Interface Flutter

### 4.1 Telas Principais

- **Dashboard**: Visão geral de backups, status e estatísticas
- **Configuração SQL Server**: Cadastro e edição de conexões SQL Server
- **Configuração Sybase**: Cadastro e edição de conexões Sybase ASA
- **Destinos**: Configuração de destinos (Local / FTP / Google Drive)
- **Agendamentos**: Criação e gerenciamento de agendamentos
- **Logs**: Visualização de histórico de execuções e logs detalhados
- **Notificações**: Configuração de destinatários de e-mail

### 4.2 Funcionalidades da Interface

- Tema claro/escuro
- Validação de formulários
- Feedback visual de operações
- Exportação de logs
- Filtros e buscas nos logs
- **Ícone na bandeja do sistema (System Tray)**: Quando minimizada, a aplicação continua rodando em segundo plano com ícone na bandeja do Windows
  - Menu de contexto no ícone da bandeja (abrir, executar backup manual, sair)
  - Notificações visuais através do ícone da bandeja
  - Restaurar janela ao clicar no ícone
  - Opção de iniciar minimizada na bandeja
- **Instância única**: Apenas uma instância do programa pode rodar por computador
  - Ao tentar abrir uma segunda instância, a janela da instância existente é restaurada e trazida para frente
  - Previne conflitos e execuções duplicadas de backups
  - Controle via mutex ou named pipe do Windows

---

## 📡 5. Notificações por E-mail

### 5.1 Tipos de Notificação

- ✔ **Sucesso**: Backup concluído com sucesso
- ❗ **Erro**: Falha na execução do backup
- ⚠ **Avisos**: Alertas e informações importantes
- 📅 **Informativos**: Notificações de agendamento (opcional)

### 5.2 Configuração de E-mail

**Nota**: O sistema utiliza `flutter_email_sender`, que abre o cliente de e-mail padrão do Windows. Não é necessária configuração SMTP.

- **Destinatários**: Lista de e-mails que receberão as notificações
- **Remetente**: Nome do remetente (opcional, usa configuração do cliente de e-mail padrão)
- **Cliente de E-mail**: Utiliza o cliente de e-mail configurado no Windows (Outlook, Mail, etc.)

### 5.3 Comportamento

- Abre o cliente de e-mail padrão do Windows com o e-mail pré-preenchido
- Enviar após cada execução de backup
- Não travar backup caso envio falhe (execução assíncrona)
- Anexo de log opcional (arquivo de log pode ser anexado)
- Tipos de e-mail configuráveis por usuário
- Template de e-mail personalizável
- Usuário pode revisar e enviar manualmente o e-mail através do cliente padrão

---

## 🔧 6. Classe Dart para Envio de E-mail

```dart
import 'package:flutter_email_sender/flutter_email_sender.dart';

class EmailService {
  final List<String> recipients;
  final String senderName;

  EmailService({
    required this.recipients,
    this.senderName = 'Sistema de Backup',
  });

  Future<bool> sendEmail({
    required String subject,
    required String body,
    List<String>? attachmentPaths,
  }) async {
    try {
      final Email email = Email(
        body: body,
        subject: subject,
        recipients: recipients,
        attachmentPaths: attachmentPaths,
        isHTML: false,
      );

      await FlutterEmailSender.send(email);
      return true;
    } catch (e) {
      // Log do erro sem travar o processo
      return false;
    }
  }

  Future<bool> sendSuccessNotification({
    required String databaseName,
    required String backupPath,
    required int fileSize,
    String? logPath,
  }) async {
    final subject = '✅ Backup Concluído com Sucesso - $databaseName';
    final body = '''
Backup realizado com sucesso!

Base de Dados: $databaseName
Arquivo: $backupPath
Tamanho: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB
Data/Hora: ${DateTime.now().toString()}
''';

    return await sendEmail(
      subject: subject,
      body: body,
      attachmentPaths: logPath != null ? [logPath] : null,
    );
  }

  Future<bool> sendErrorNotification({
    required String databaseName,
    required String errorMessage,
    String? logPath,
  }) async {
    final subject = '❌ Erro no Backup - $databaseName';
    final body = '''
Erro ao realizar backup!

Base de Dados: $databaseName
Erro: $errorMessage
Data/Hora: ${DateTime.now().toString()}
''';

    return await sendEmail(
      subject: subject,
      body: body,
      attachmentPaths: logPath != null ? [logPath] : null,
    );
  }
}
```

---

## 🔄 7. Fluxo de Execução de Backup

```
INICIAR BACKUP
    ↓
VALIDAR CONFIGURAÇÕES
    ↓
VERIFICAR ESPAÇO EM DISCO
    ↓
EXECUTAR BACKUP (SQL Server / Sybase)
    ↓
VERIFICAR INTEGRIDADE DO ARQUIVO
    ↓
COMPRIMIR (se configurado)
    ↓
SALVAR LOCALMENTE
    ↓
ENVIAR PARA DESTINOS CONFIGURADOS
    ├─→ FTP (se configurado)
    ├─→ Google Drive (se configurado)
    └─→ Outros destinos
    ↓
GERAR LOG DA EXECUÇÃO
    ↓
LIMPAR BACKUPS ANTIGOS (se configurado)
    ↓
ENVIAR E-MAIL (sucesso/erro/aviso)
    ↓
ATUALIZAR HISTÓRICO
    ↓
FINALIZAR
```

### 7.1 Tratamento de Erros

- Captura de erros em cada etapa
- Log detalhado de erros
- Continuidade do processo mesmo com falhas parciais
- Notificação de erros críticos

---

## 💾 8. Persistência de Dados

### 8.1 Banco de Dados Local (SQLite)

Armazenamento de:

- **Configurações de Conexão**: SQL Server e Sybase
- **Destinos**: Configurações de Local, FTP e Google Drive
- **Agendamentos**: Regras e horários de execução
- **Histórico de Backups**: Registro de todas as execuções
- **Logs**: Histórico detalhado de operações
- **Configurações de E-mail**: Destinatários de notificações

### 8.2 Segurança

- Tokens OAuth2 do Google Drive armazenados de forma segura
- Validação de integridade dos dados
- Dados sensíveis criptografados quando necessário

### 8.3 Estrutura de Tabelas (Exemplo)

```sql
-- Configurações de conexão SQL Server
CREATE TABLE sql_server_configs (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  server TEXT NOT NULL,
  database TEXT NOT NULL,
  username TEXT NOT NULL,
  password TEXT NOT NULL,
  port INTEGER DEFAULT 1433,
  enabled INTEGER DEFAULT 1
);

-- Configurações de conexão Sybase
CREATE TABLE sybase_configs (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  server_name TEXT NOT NULL,
  database_file TEXT NOT NULL,
  username TEXT NOT NULL,
  password TEXT NOT NULL,
  enabled INTEGER DEFAULT 1
);

-- Agendamentos
CREATE TABLE schedules (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  database_config_id INTEGER NOT NULL,
  database_type TEXT NOT NULL, -- 'sql_server' ou 'sybase'
  schedule_type TEXT NOT NULL, -- 'daily', 'weekly', 'monthly', 'interval'
  schedule_config TEXT NOT NULL, -- JSON com configurações
  enabled INTEGER DEFAULT 1
);

-- Histórico de backups
CREATE TABLE backup_history (
  id INTEGER PRIMARY KEY,
  schedule_id INTEGER,
  database_name TEXT NOT NULL,
  database_type TEXT NOT NULL,
  backup_path TEXT NOT NULL,
  file_size INTEGER NOT NULL,
  status TEXT NOT NULL, -- 'success', 'error', 'warning'
  error_message TEXT,
  started_at TEXT NOT NULL,
  finished_at TEXT,
  duration_seconds INTEGER
);

-- Configurações de E-mail
CREATE TABLE email_config (
  id INTEGER PRIMARY KEY,
  sender_name TEXT NOT NULL DEFAULT 'Sistema de Backup',
  recipients TEXT NOT NULL, -- JSON array de e-mails
  enabled INTEGER DEFAULT 1
);
```

---

## 📋 9. Logs e Monitoramento

### 9.1 Tipos de Log

- **Execução**: Logs de cada etapa do backup
- **Erros**: Logs detalhados de erros e exceções
- **Sistema**: Logs de operações do sistema
- **Auditoria**: Logs de alterações de configuração

### 9.2 Funcionalidades

- Visualização de logs em tempo real
- Filtros por data, tipo, status
- Exportação de logs em formato texto/JSON
- Rotação automática de logs antigos
- Busca textual nos logs

---

## ✅ 10. Checklist de Requisitos

### Funcionalidades Core

- [x] Backup SQL Server via `sqlcmd`
- [x] Backup Sybase ASA via `dbbackup.exe`
- [x] Agendamento de backups
- [x] Destinos: Local / FTP / Google Drive
- [x] Logs detalhados
- [x] Notificações por e-mail
- [x] Interface Flutter completa
- [x] Persistência em SQLite
- [x] Criptografia de senhas
- [x] Execução em background

### Funcionalidades Adicionais

- [ ] Compressão ZIP
- [ ] Retenção configurável de backups
- [ ] Validação de integridade
- [ ] Retry automático em falhas
- [ ] Dashboard com estatísticas
- [ ] Exportação de logs
- [ ] Tema claro/escuro
- [ ] Templates de e-mail personalizáveis

---

## 🏗️ 11. Estrutura do Projeto

```
lib/
├── core/
│   ├── database/          # Configuração SQLite
│   ├── encryption/        # Criptografia de senhas
│   ├── errors/            # Tratamento de erros
│   ├── routes/            # Configuração go_router
│   ├── di/                # Configuração get_it (service locator)
│   ├── validation/        # Schemas zard para validação
│   └── utils/             # Utilitários gerais
├── domain/
│   ├── entities/          # Entidades do domínio
│   ├── repositories/      # Interfaces de repositórios
│   └── use_cases/         # Casos de uso
├── infrastructure/
│   ├── datasources/       # Fontes de dados (SQLite, APIs)
│   ├── repositories/     # Implementações de repositórios
│   ├── external/          # Integrações externas (FTP, Google Drive)
│   └── http/              # Configuração dio (cliente HTTP)
├── application/
│   ├── services/          # Serviços de aplicação
│   └── providers/         # Providers de estado (provider)
└── presentation/
    ├── pages/             # Telas da aplicação (rotas go_router)
    ├── widgets/           # Widgets reutilizáveis
    ├── theme/             # Tema da aplicação
    └── managers/          # Configuração window_manager e tray_manager (system tray)
```

---

## 📝 Notas de Implementação

### Arquitetura e Padrões

- O sistema deve seguir os princípios de Clean Architecture
- Todas as operações de I/O devem ser assíncronas
- Implementar tratamento robusto de erros em todas as camadas
- Testes unitários para lógica de negócio
- Testes de integração para fluxos completos
- Documentação inline do código (apenas quando necessário)

### Configuração de Bibliotecas

- **go_router**: Configurar rotas em `core/routes/` com rotas nomeadas e parâmetros
- **dio**: Configurar interceptors para autenticação e tratamento de erros em `infrastructure/http/`
- **get_it**: Registrar todas as dependências em `core/di/service_locator.dart`
- **provider**: Usar `ChangeNotifierProvider` e `MultiProvider` para gerenciamento de estado
- **brasil_fields**: Usar para formatação de campos brasileiros (CPF, CNPJ, CEP, telefone, etc.)
- **flutter_dotenv**: Carregar variáveis de ambiente no `main.dart` antes de inicializar a aplicação
- **uuid**: Usar para geração de IDs únicos de entidades e agendamentos
- **zard**: Criar schemas de validação em `core/validation/` para validação de modelos e formulários
- **window_manager**: Configurar controle de janelas em `presentation/managers/` para gerenciar tamanho, posição e estado das janelas
- **tray_manager**: Configurar system tray em `presentation/managers/tray_manager.dart` para ícone na bandeja do Windows, menu de contexto e notificações
- **single_instance**: Configurar em `main.dart` antes de `runApp()` para garantir apenas uma instância do aplicativo por computador, restaurando a janela existente se tentar abrir segunda instância
- **process/process_run**: Usar em `infrastructure/external/` para executar sqlcmd e dbbackup.exe
- **googleapis/google_sign_in**: Configurar OAuth2 em `infrastructure/external/google_drive/` para autenticação e upload
- **file_picker**: Usar em `presentation/widgets/` para seleção de pastas de destino
- **logger**: Configurar em `core/utils/logger.dart` para logging estruturado em toda a aplicação
- **win32**: Usar em `infrastructure/external/windows/` para integração com Event Log e serviços do Windows
- **intl**: Usar para formatação de datas e números em toda a aplicação
- **cron/timezone**: Configurar em `application/services/scheduler_service.dart` para agendamento de backups
- **sqflite/drift**: Configurar em `infrastructure/datasources/` para persistência local
- **archive**: Usar em `infrastructure/external/` para compressão ZIP dos backups
- **flutter_email_sender**: Usar em `infrastructure/external/email_service.dart` para envio de notificações
