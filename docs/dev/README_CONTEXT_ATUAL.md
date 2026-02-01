# Contexto Atual - Continuidade do Desenvolvimento

> **Última Atualização**: 01/02/2026
> **Branch**: `feature/client-server-architecture`
> **Commit Mais Recente**: `9138ebd`
> **Status**: FASE 0 completada (85%), pronto para iniciar FASE 1

## 🚀 Para Outra IA: Como Continuar Este Projeto

### 1. Leia Primeiro (Ordem Importante)

1. **Este arquivo** (README_CONTEXT_ATUAL.md) - 5 min
   - Contexto imediato do estado atual
   - O que já foi feito
   - Próximos passos

2. **plano_cliente_servidor.md** - 15 min
   - Arquitetura completa do sistema
   - Decisões técnicas (TCP Socket, protocolo binário)
   - Diagramas e especificações

3. **analise_tecnica_ui_banco_pacotes.md** - 10 min
   - Análise de componentes existentes (reutilizar!)
   - Database schema (já implementado v14)
   - Pacotes necessários (qr_flutter já adicionado)

4. **implementacao_cliente_servidor.md** - 20 min
   - Checklist detalhado de TODAS as tarefas
   - FASE 0: 11/13 completados (banco de dados pronto)
   - FASE 1: Pronta para iniciar (0/31 tarefas)

### 2. Estado Atual do Projeto

#### ✅ JÁ IMPLEMENTADO (FASE 0 - 85%)

**Banco de Dados v14** (Commit: `2dbc725`):
- 4 tabelas criadas: `ServerCredentialsTable`, `ConnectionLogsTable`, `ServerConnectionsTable`, `FileTransfersTable`
- 4 DAOs criados com métodos CRUD completos
- Schema version atualizado: 13 → 14
- Migration script v14 implementado e testado automaticamente
- Índices de performance criados
- Código gerado com `build_runner` sem erros

**Pacotes**:
- `qr_flutter: ^4.1.0` adicionado (geração de QR codes)

**Qualidade**:
- `flutter analyze`: No issues found
- Clean Architecture mantida
- Todos os arquivos commitados no GitHub

#### ⏳ PENDENTE (FASE 0 - 15%)

- Testar migration manualmente com backup do banco
- Testar migration com dados existentes

### 3. Próximo Passo Imediato

#### **Tarefa: Criar Constants de Socket**

**Arquivo**: `lib/core/constants/socket_config.dart`

**Conteúdo**:
```dart
// lib/core/constants/socket_config.dart
class SocketConfig {
  static const int defaultPort = 9527;
  static const int chunkSize = 131072; // 128KB
  static const Duration heartbeatInterval = Duration(seconds: 30);
  static const Duration heartbeatTimeout = Duration(seconds: 60);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const int maxRetries = 3;
}
```

**Por que começar aqui?**
- Constantes serão usadas por TODO o código de Socket
- Define os valores acordados no planejamento
- Prepara o terreno para FASE 1

### 4. FASE 1: Fundamentos Socket (0/31 tarefas)

#### Objetivo da FASE 1

Infraestrutura base para comunicação Socket TCP/IP entre Server e Client

#### Critérios de Aceitação

- [ ] Server pode aceitar conexões TCP na porta 9527
- [ ] Client pode conectar ao Server via Socket
- [ ] Autenticação básica funciona (Server ID + Password)
- [ ] Heartbeat/ping-pong funciona
- [ ] Mensagens podem ser enviadas e recebidas
- [ ] Testes unitários passando
- [ ] Zero memory leaks

#### Primeiras 5 Tarefas da FASE 1

1. **Criar `lib/core/constants/socket_config.dart`** (5 min)
   - Definir constantes: porta 9527, chunk 128KB, timeouts

2. **Criar `lib/infrastructure/protocol/message_types.dart`** (15 min)
   - Enum MessageType com 18 tipos (AUTH, HEARTBEAT, FILE_CHUNK, etc.)
   - Veja especificação completa em `implementacao_cliente_servidor.md`

3. **Criar `lib/infrastructure/protocol/message.dart`** (30 min)
   - Class Message (header + payload + checksum)
   - Métodos: serialize(), deserialize()

4. **Criar `lib/core/utils/crc32.dart`** (20 min)
   - Implementar calculateChecksum(List<int> data)
   - Usar crypto package (já existe no projeto)

5. **Criar `lib/infrastructure/protocol/binary_protocol.dart`** (45 min)
   - Serialização/deserialização de mensagens
   - Ler/escrever bytes no Socket

### 5. Estrutura de Pastas (Já Existente)

```
lib/
├── core/
│   ├── constants/
│   │   └── 📝 socket_config.dart (CRIAR EM BREVE)
│   ├── security/
│   │   └── 📝 password_hasher.dart (criar na FASE 2)
│   └── utils/
│       ├── logger_service.dart (✅ EXISTE - reutilizar)
│       └── 📝 crc32.dart (CRIAR NA FASE 1)
│
├── domain/
│   ├── entities/
│   │   ├── protocol/
│   │   │   ├── 📝 message.dart (CRIAR NA FASE 1)
│   │   │   ├── 📝 file_chunk.dart (CRIAR NA FASE 1)
│   │   │   └── 📝 file_transfer_progress.dart (CRIAR NA FASE 1)
│   │   └── connection/
│   │       ├── 📝 server_connection.dart (CRIAR NA FASE 2)
│   │       └── 📝 connected_client.dart (CRIAR NA FASE 2)
│   └── value_objects/
│       └── 📝 server_id.dart (CRIAR NA FASE 2)
│
├── infrastructure/
│   ├── protocol/
│   │   ├── 📝 binary_protocol.dart (CRIAR NA FASE 1)
│   │   ├── 📝 compression.dart (CRIAR NA FASE 1)
│   │   └── 📝 file_chunker.dart (CRIAR NA FASE 4)
│   ├── socket/
│   │   ├── server/
│   │   │   ├── 📝 tcp_socket_server.dart (CRIAR NA FASE 1)
│   │   │   └── 📝 client_handler.dart (CRIAR NA FASE 1)
│   │   └── client/
│   │       └── 📝 tcp_socket_client.dart (CRIAR NA FASE 1)
│   └── datasources/
│       ├── local/
│       │   ├── database.dart (✅ v14 JÁ ATUALIZADO)
│       │   └── tables/
│       │       ├── server_credentials_table.dart (✅ CRIADO)
│       │       ├── connection_logs_table.dart (✅ CRIADO)
│       │       ├── server_connections_table.dart (✅ CRIADO)
│       │       └── file_transfers_table.dart (✅ CRIADO)
│       └── daos/
│           ├── server_credential_dao.dart (✅ CRIADO)
│           ├── connection_log_dao.dart (✅ CRIADO)
│           ├── server_connection_dao.dart (✅ CRIADO)
│           └── file_transfer_dao.dart (✅ CRIADO)
│
├── presentation/
│   ├── pages/
│   │   ├── server/
│   │   │   ├── 📝 connected_clients_page.dart (CRIAR NA FASE 2)
│   │   │   └── 📝 server_settings_page.dart (CRIAR NA FASE 2)
│   │   └── client/
│   │       ├── 📝 server_login_page.dart (CRIAR NA FASE 2)
│   │       └── 📝 remote_schedules_page.dart (CRIAR NA FASE 3)
│   └── widgets/
│       ├── common/
│       │   ├── app_button.dart (✅ EXISTE - reutilizar)
│       │   ├── app_card.dart (✅ EXISTE - reutilizar)
│       │   └── config_list_item.dart (✅ EXISTE - reutilizar)
│       └── 📝 client/ (CRIAR NOVOS WIDGETS)
│           └── 📝 qr_code_widget.dart (CRIAR NA FASE 2)
```

### 6. Comandos Importantes

```bash
# Verificar código
flutter analyze

# Gerar código Drift após mudar banco de dados
dart run build_runner build --delete-conflicting-outputs

# Rodar testes
flutter test

# Ver mudanças no banco
git diff lib/infrastructure/datasources/local/database.dart

# Fazer commit padrão
git add .
git commit -m "feat(scope): description"
git push origin feature/client-server-architecture
```

### 7. Regras do Projeto (MUITO IMPORTANTE)

**Clean Architecture**:
- Domain Layer NÃO pode importar Infrastructure/Application/Presentation
- Application Layer NÃO pode importar Infrastructure/Presentation
- Infrastructure Layer NÃO pode importar Application/Presentation
- Presentation Layer NÃO pode importar Infrastructure

**Protocolo Binário (CRÍTICO)**:
- Código de protocolo DEVE ser 100% compartilhado entre Server e Client
- NÃO criar arquivos separados para Server/Client do protocolo
- Pasta `lib/infrastructure/protocol/` é compartilhada!

**Reutilização**:
- UI Components existentes em `lib/presentation/widgets/common/` devem ser reutilizados
- Services existentes (LoggerService, EncryptionService) devem ser reutilizados
- Destinos de backup (FTP, Google Drive, etc.) JÁ EXISTEM e funcionam

**Qualidade**:
- Sempre rodar `flutter analyze` antes de commitar
- Seguir padrões de código existentes (naming, estrutura)
- Usar `const` constructors wherever possible
- Adicionar testes unitários para lógica de negócio

### 8. Decisões Já Tomadas (NÃO MUDAR)

✅ **Porta**: 9527 (configurável, mas default é 9527)
✅ **Chunk size**: 128KB (131072 bytes)
✅ **Compressão**: Sim (zlib)
✅ **TLS/SSL**: Não para v1 (planejado para v2)
✅ **Limite clientes**: Ilimitado
✅ **Protocolo**: TCP Socket (dart:io nativo)
✅ **Autenticação**: Server ID + Password (SHA-256 hash)
✅ **Banco**: Drift/SQLite v14 (já implementado)

### 9. Arquivos de Referência

| Arquivo | Para Que Serve |
|---------|----------------|
| `plano_cliente_servidor.md` | Arquitetura completa, decisões técnicas |
| `implementacao_cliente_servidor.md` | Checklist DETALHADO de todas as tarefas |
| `analise_tecnica_ui_banco_pacotes.md` | Análise técnica, componentes existentes |
| `ui_instalacao_cliente_servidor.md` | Wireframes de UI, instalador Inno Setup |
| `.claude/rules/` | Regras de código (Clean Architecture, estilo) |

### 10. Comandos Rápidos Para Começar

```bash
# 1. Verificar branch atual
git branch

# 2. Ver se está tudo commitado
git status

# 3. Ler os documentos de planejamento
# - plano_cliente_servidor.md (arquitetura)
# - implementacao_cliente_servidor.md (checklist FASE 1)

# 4. Criar primeiro arquivo
# lib/core/constants/socket_config.dart

# 5. Rodar analyze
flutter analyze

# 6. Commit
git add lib/core/constants/socket_config.dart
git commit -m "feat(core): add SocketConfig constants"
git push origin feature/client-server-architecture
```

### 11. Perguntas Frequentes

**Q: Posso mudar o chunk size de 128KB?**
A: Não! Essa decisão já foi tomada e validada. Mantenha 131072 bytes.

**Q: Preciso criar dois protocolos (Server e Client)?**
A: NÃO! Protocolo binário DEVE ser 100% compartilhado. Pasta `lib/infrastructure/protocol/` é usada por ambos.

**Q: Posso usar gRPC em vez de TCP Socket?**
A: Não! Decisão técnica já foi tomada. Use TCP Socket com dart:io nativo.

**Q: Onde coloco código de Socket Server?**
A: `lib/infrastructure/socket/server/tcp_socket_server.dart`

**Q: Onde coloco código de Socket Client?**
A: `lib/infrastructure/socket/client/tcp_socket_client.dart`

**Q: Preciso recriar os destinos de backup?**
A: NÃO! Eles JÁ EXISTEM em `lib/infrastructure/external/destinations/` e funcionam perfeitamente. Apenas reutilize.

**Q: Como testar a migration v14?**
A:
1. Backup do banco atual
2. Rodar o app (migration acontece automaticamente)
3. Verificar se as 4 novas tabelas foram criadas
4. Inserir dados de teste
5. Verificar se DAOs funcionam

### 12. Checkpoint - O Que Deveria Estar Próximo

Após ler este documento, você deveria ser capaz de:

- [ ] Saber EXATAMENTE o que já foi implementado (banco v14)
- [ ] Saber EXATAMENTE o que fazer a seguir (FASE 1 - Socket)
- [ ] Conhecer todas as decisões técnicas já tomadas
- [ ] Saber quais arquivos reutilizar vs quais criar
- [ ] Entender a arquitetura e regras do projeto
- [ ] Ter os primeiros arquivos da FASE 1 criados

### 13. Suporte e Referências

**Documentos do Projeto**:
- Todos em `docs/dev/`
- Leitura obrigatória antes de codificar

**Regras de Código**:
- `.claude/rules/` - Clean Architecture, estilo Dart, UI patterns
- LEIA antes de escrever código!

**Commits Recentes** (entender o que foi feito):
- `2dbc725` - Banco de dados v14 implementado
- `9138ebd` - Documentação atualizada

---

## 📝 Notas para a Próxima IA

1. **NÃO pule a leitura dos documentos** - O planejamento é EXTENSIVO por um motivo
2. **Comece PEQUENO** - Primeiro crie `socket_config.dart` (5 minutos)
3. **Reutilize TUDO** - UI components, services, destinos - JÁ EXISTEM
4. **Siga Clean Architecture** - Violations causarão problemas
5. **Teste constantemente** - `flutter analyze` é seu amigo
6. **Commit frequentemente** - Commits pequenos são melhores que um monolítico

**Boa sorte! 🚀**
