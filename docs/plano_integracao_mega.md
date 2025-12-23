---
name: Integração MEGA como destino de backup
overview: Implementar integração completa com MEGA seguindo padrões do projeto, reutilizando código existente e evitando duplicação. A implementação seguirá a arquitetura Clean Architecture e os padrões estabelecidos para Dropbox/Google Drive.
todos:
  - id: domain-entities
    content: "Atualizar backup_destination.dart: adicionar mega ao enum DestinationType e criar MegaDestinationConfig"
    status: pending
  - id: domain-use-case
    content: Criar SendToMega use case em domain/use_cases/destinations/
    status: pending
    dependencies:
      - domain-entities
  - id: domain-clean-backups
    content: Atualizar CleanOldBackups para incluir MEGA
    status: pending
    dependencies:
      - domain-entities
  - id: core-errors
    content: Criar MegaFailure em core/errors/ e exportar em errors.dart
    status: pending
  - id: core-constants
    content: Adicionar constantes MEGA em app_constants.dart (API URLs, limites, etc)
    status: pending
  - id: infra-auth-service
    content: Criar MegaAuthService com autenticação email/senha seguindo padrão DropboxAuthService
    status: pending
    dependencies:
      - core-errors
      - core-constants
  - id: infra-destination-service
    content: Criar MegaDestinationService com upload, criação de pastas e limpeza seguindo padrão DropboxDestinationService
    status: pending
    dependencies:
      - infra-auth-service
      - core-errors
      - core-constants
  - id: infra-barrel
    content: Criar barrel file mega.dart e exportar em external.dart
    status: pending
    dependencies:
      - infra-auth-service
      - infra-destination-service
  - id: app-provider
    content: Criar MegaAuthProvider seguindo padrão DropboxAuthProvider
    status: pending
    dependencies:
      - infra-auth-service
  - id: presentation-dialog
    content: "Atualizar DestinationDialog: adicionar UI MEGA (campos, autenticação, status)"
    status: pending
    dependencies:
      - app-provider
      - domain-entities
  - id: presentation-list-item
    content: "Atualizar DestinationListItem: adicionar ícone, cor e nome MEGA"
    status: pending
    dependencies:
      - domain-entities
  - id: presentation-colors
    content: Adicionar cor destinationMega em app_colors.dart
    status: pending
  - id: di-service-locator
    content: Registrar MegaAuthService, MegaDestinationService, SendToMega e MegaAuthProvider no service_locator
    status: pending
    dependencies:
      - infra-destination-service
      - app-provider
      - domain-use-case
  - id: di-scheduler
    content: "Atualizar SchedulerService: adicionar MEGA em _sendToDestination e _cleanOldBackups"
    status: pending
    dependencies:
      - di-service-locator
      - domain-use-case
  - id: di-main
    content: Adicionar MegaAuthProvider ao MultiProvider em main.dart e chamar initialize()
    status: pending
    dependencies:
      - di-service-locator
  - id: exports
    content: Adicionar exports necessários em providers.dart, destinations.dart e external.dart
    status: pending
    dependencies:
      - app-provider
      - domain-use-case
      - infra-barrel
---

# Plano de Implementação - Integração MEGA

## Visão Geral

Implementar integração com MEGA (mega.nz) como destino de backup, seguindo os padrões estabelecidos no projeto para Dropbox e Google Drive. A implementação utilizará API REST do MEGA e seguirá Clean Architecture.

## Diferenças Principais MEGA vs Dropbox

- **Autenticação**: Email/senha (MEGA) vs OAuth2 (Dropbox)
- **API**: Comandos JSON customizados (MEGA) vs REST padrão (Dropbox)
- **Criptografia**: E2EE no cliente (futuro) vs servidor (Dropbox)
- **Upload**: Chunks com offset na URL (MEGA) vs sessões (Dropbox)

## Estrutura de Arquivos

```
lib/
├── domain/
│   ├── entities/
│   │   └── backup_destination.dart (adicionar mega ao enum)
│   ├── use_cases/
│   │   └── destinations/
│   │       └── send_to_mega.dart
│   └── services/
│       └── i_mega_backup_service.dart (se necessário)
├── infrastructure/
│   └── external/
│       └── mega/
│           ├── mega_auth_service.dart
│           ├── mega_destination_service.dart
│           └── mega.dart (barrel)
├── application/
│   └── providers/
│       └── mega_auth_provider.dart
├── core/
│   ├── errors/
│   │   └── mega_failure.dart
│   └── constants/
│       └── app_constants.dart (adicionar constantes MEGA)
└── presentation/
    └── widgets/
        └── destinations/
            └── destination_dialog.dart (adicionar UI MEGA)
```

## Implementação Detalhada

### 1. Domain Layer

#### 1.1 Atualizar `backup_destination.dart`

**Arquivo**: `lib/domain/entities/backup_destination.dart`

- Adicionar `mega` ao enum `DestinationType`
- Criar classe `MegaDestinationConfig` seguindo padrão de `DropboxDestinationConfig`:
  ```dart
  class MegaDestinationConfig {
    final String folderPath;
    final String folderName;
    final int retentionDays;
    
    const MegaDestinationConfig({
      required this.folderPath,
      this.folderName = 'Backups',
      this.retentionDays = 30,
    });
    
    Map<String, dynamic> toJson() => {
      'folderPath': folderPath,
      'folderName': folderName,
      'retentionDays': retentionDays,
    };
    
    factory MegaDestinationConfig.fromJson(Map<String, dynamic> json) {
      return MegaDestinationConfig(
        folderPath: json['folderPath'] as String,
        folderName: json['folderName'] as String? ?? 'Backups',
        retentionDays: json['retentionDays'] as int? ?? 30,
      );
    }
  }
  ```


#### 1.2 Criar Use Case `SendToMega`

**Arquivo**: `lib/domain/use_cases/destinations/send_to_mega.dart`

- Seguir padrão de `SendToDropbox`
- Validar `sourceFilePath` e `config.folderName`
- Chamar `MegaDestinationService.upload`

#### 1.3 Atualizar `CleanOldBackups`

**Arquivo**: `lib/domain/use_cases/destinations/clean_old_backups.dart`

- Adicionar `megaDeleted` ao `CleanOldBackupsResult`
- Adicionar `MegaDestinationService` ao construtor
- Adicionar case `DestinationType.mega` no switch
- Chamar `megaService.cleanOldBackups(config)`

### 2. Infrastructure Layer

#### 2.1 Criar `MegaFailure`

**Arquivo**: `lib/core/errors/mega_failure.dart`

- Seguir padrão de `DropboxFailure`
- Estender `Failure`
- Exportar em `lib/core/errors/errors.dart`

#### 2.2 Adicionar Constantes MEGA

**Arquivo**: `lib/core/constants/app_constants.dart`

- Adicionar:
  ```dart
  static const String megaApiBaseUrl = 'https://g.api.mega.co.nz';
  static const String megaContentBaseUrl = 'https://eu.api.mega.co.nz';
  static const int megaSimpleUploadLimit = 100 * 1024 * 1024; // 100MB
  static const int megaChunkSize = 4 * 1024 * 1024; // 4MB
  ```


#### 2.3 Criar `MegaAuthService`

**Arquivo**: `lib/infrastructure/external/mega/mega_auth_service.dart`

**Padrões a seguir** (baseado em `DropboxAuthService`):

- Usar `dio` para HTTP
- Usar `result_dart` para retornos
- Armazenar credenciais com `EncryptionService`
- Usar `SharedPreferences` para persistência
- Cache de tokens em memória

**Métodos principais**:

- `initialize()`: Inicializar `Dio` com base URL
- `signIn(email, password)`: Autenticar via API MEGA
  - Comando `us` (user session)
  - Retornar `MegaAuthResult` com session ID e email
- `signInSilently()`: Restaurar sessão salva
- `signOut()`: Limpar sessão
- `_loadStoredCredentials()`: Carregar credenciais salvas
- `_saveCredentials()`: Salvar credenciais criptografadas
- `_clearStoredCredentials()`: Limpar credenciais

**Diferenças vs Dropbox**:

- Não usa OAuth2, usa email/senha diretamente
- Não tem refresh token, apenas session ID
- API usa comandos JSON customizados

#### 2.4 Criar `MegaDestinationService`

**Arquivo**: `lib/infrastructure/external/mega/mega_destination_service.dart`

**Padrões a seguir** (baseado em `DropboxDestinationService`):

- Usar `result_dart` para retornos
- Retry com `maxRetries`
- Upload em chunks para arquivos grandes
- Tratamento de erros HTTP consistente
- Cache de `Dio` autenticado

**Classes auxiliares**:

- `MegaUploadResult`: Similar a `DropboxUploadResult`
  ```dart
  class MegaUploadResult {
    final String fileId;
    final String fileName;
    final int fileSize;
    final Duration duration;
  }
  ```


**Métodos principais**:

- `upload()`: Método principal de upload
  - Validar arquivo existe
  - Criar/obter pastas (main + date)
  - Deletar arquivo se existir
  - Escolher upload simples ou resumável
  - Retry com backoff
- `_uploadSimple()`: Upload direto para arquivos pequenos
  - Obter URL de upload (comando `u`)
  - POST direto com dados
  - Completar upload (comando `p`)
- `_uploadResumable()`: Upload em chunks
  - Obter URL de upload
  - Upload chunks com offset na URL (`/x`)
  - Completar upload com todos os handles
- `_getOrCreateFolder()`: Criar pasta se não existir
  - Verificar se existe (comando `f`)
  - Criar se não existir (comando `p` com tipo folder)
- `_deleteFileIfExists()`: Deletar arquivo antes de upload
- `cleanOldBackups()`: Limpar backups antigos
  - Listar arquivos na pasta
  - Filtrar por data (formato `yyyy-MM-dd`)
  - Deletar arquivos antigos
- `_getAuthenticatedDio()`: Obter `Dio` com sessão válida
- `_executeWithTokenRefresh()`: Executar operação com retry em caso de 401
  - MEGA não tem refresh token, re-autenticar se 401
- `_getMegaErrorMessage()`: Mensagens de erro amigáveis
  - Mapear códigos HTTP (401, 403, 409, 429, 507)
  - Mapear códigos MEGA negativos (-9, -15, -17)
  - Tratar erros de rede e timeout
  - Retornar mensagens claras para o usuário

**Diferenças vs Dropbox**:

- API usa comandos JSON (`{"a": "comando"}`)
- Upload usa offset na URL (`/x` onde x é o byte offset)
- Não usa headers especiais, apenas JSON no body
- Autenticação via session ID, não Bearer token

#### 2.5 Criar Barrel File

**Arquivo**: `lib/infrastructure/external/mega/mega.dart`

- Exportar `mega_auth_service.dart` e `mega_destination_service.dart`
- Exportar em `lib/infrastructure/external/external.dart`

### 3. Application Layer

#### 3.1 Criar `MegaAuthProvider`

**Arquivo**: `lib/application/providers/mega_auth_provider.dart`

**Padrões a seguir** (baseado em `DropboxAuthProvider`):

- Estender `ChangeNotifier`
- Gerenciar estado de autenticação
- Armazenar configuração OAuth (email/senha) criptografada
- Usar `EncryptionService` para salvar credenciais

**Propriedades**:

- `isLoading`, `isInitialized`, `isConfigured`, `isSignedIn`
- `error`, `currentEmail`
- `MegaAuthConfig?` (email/senha)

**Métodos**:

- `initialize()`: Carregar configuração salva e tentar sign in silencioso
- `configureAuth(email, password)`: Salvar credenciais
- `signIn()`: Autenticar via `MegaAuthService`
- `signOut()`: Limpar sessão
- `removeAuthConfig()`: Remover configuração
- `_loadAuthConfig()`: Carregar configuração salva
- `_saveAuthConfig()`: Salvar configuração criptografada

**Diferenças vs Dropbox**:

- Não usa OAuth2, apenas email/senha
- Não precisa de Client ID/Secret
- Configuração mais simples

### 4. Presentation Layer

#### 4.1 Atualizar `DestinationDialog`

**Arquivo**: `lib/presentation/widgets/destinations/destination_dialog.dart`

**Adicionar**:

- Controller: `_megaFolderPathController`, `_megaFolderNameController`
- Método `_buildMegaFields()`: Similar a `_buildDropboxFields()`
  - Status de autenticação
  - Seção de login (email/senha)
  - Campos de pasta (path, name)
  - Aviso se não autenticado
- Método `_buildMegaAuthStatus()`: Mostrar status de autenticação
- Método `_buildMegaLoginSection()`: Formulário de login
- Método `_connectToMega()`: Chamar `MegaAuthProvider.signIn()`
- Atualizar `_buildTypeSpecificFields()`: Adicionar case MEGA
- Atualizar `_getTypeIcon()`: Adicionar ícone MEGA
- Atualizar `_getTypeName()`: Adicionar nome "MEGA"
- Atualizar `_save()`: Adicionar case MEGA para criar config JSON
- Atualizar `initState()`: Carregar config MEGA se editando
- Atualizar `dispose()`: Dispose dos controllers MEGA

#### 4.2 Atualizar `DestinationListItem`

**Arquivo**: `lib/presentation/widgets/destinations/destination_list_item.dart`

- Adicionar case MEGA em `_getTypeIcon()`
- Adicionar case MEGA em `_getTypeColor()`
- Adicionar case MEGA em `_getTypeName()`
- Adicionar case MEGA em `_getConfigSummary()`

#### 4.3 Adicionar Cor MEGA

**Arquivo**: `lib/core/theme/app_colors.dart`

- Adicionar `destinationMega = Color(0xFFDC143C)` (cor oficial MEGA)

### 5. Service Locator

**Arquivo**: `lib/core/di/service_locator.dart`

**Adicionar registros**:

```dart
getIt.registerLazySingleton<MegaAuthService>(() => MegaAuthService());

getIt.registerLazySingleton<MegaDestinationService>(
  () => MegaDestinationService(getIt<MegaAuthService>()),
);

getIt.registerLazySingleton<SendToMega>(
  () => SendToMega(getIt<MegaDestinationService>()),
);

getIt.registerLazySingleton<MegaAuthProvider>(
  () => MegaAuthProvider(getIt<MegaAuthService>()),
);
```

**Atualizar `CleanOldBackups`**:

- Adicionar `megaService` ao construtor
- Passar `getIt<MegaDestinationService>()` na criação

**Atualizar `SchedulerService`**:

- Adicionar `MegaDestinationService` e `SendToMega` ao construtor
- Adicionar case MEGA em `_sendToDestination()`
- Adicionar case MEGA em `_cleanOldBackups()`
- Atualizar verificação de destinos remotos para incluir MEGA:
  ```dart
  final hasRemoteDestinations = destinations.any(
    (d) =>
        d.type == DestinationType.ftp ||
        d.type == DestinationType.googleDrive ||
        d.type == DestinationType.dropbox ||
        d.type == DestinationType.mega, // Adicionar MEGA
  );
  ```


### 6. Providers

**Arquivo**: `lib/main.dart`

- Adicionar `MegaAuthProvider` ao `MultiProvider`
- Chamar `initialize()` no `MegaAuthProvider` após registro

**Arquivo**: `lib/application/providers/providers.dart`

- Exportar `mega_auth_provider.dart`

### 7. Use Cases

**Arquivo**: `lib/domain/use_cases/destinations/destinations.dart`

- Exportar `send_to_mega.dart`

## Padrões de Reutilização

### 7.1 Padrões Comuns Identificados

1. **Tratamento de Erros HTTP**:

   - Reutilizar lógica de `_getDropboxErrorMessage()` adaptada para MEGA
   - Usar `result_dart` consistentemente

2. **Retry com Token Refresh**:

   - Adaptar `_executeWithTokenRefresh()` para MEGA
   - MEGA não tem refresh token, apenas re-autenticar se 401

3. **Upload em Chunks**:

   - Adaptar lógica de `_uploadResumable()` do Dropbox
   - MEGA usa offset na URL, não sessões

4. **Criação de Pastas**:

   - Adaptar `_getOrCreateFolder()` do Dropbox
   - MEGA usa comandos JSON, não REST

5. **Armazenamento de Credenciais**:

   - Reutilizar padrão de `EncryptionService` + `SharedPreferences`
   - Mesma estrutura de `_saveCredentials()` e `_loadStoredCredentials()`

6. **Provider Pattern**:

   - Reutilizar estrutura de `DropboxAuthProvider`
   - Adaptar para email/senha ao invés de OAuth2

## Considerações Técnicas

### 7.2 API MEGA - Detalhes Técnicos

**Base URL da API**:

- API Commands: `https://g.api.mega.co.nz/cs`
- Upload/Download: `https://eu.api.mega.co.nz` (ou outros servidores regionais)

**Estrutura de Comandos**:

- Todos os comandos são enviados via POST para `/cs`
- Body contém array de comandos JSON: `[{"a": "comando", ...}]`
- Resposta é um array de respostas: `[{...}]`
- Session ID deve ser incluído nas requisições (formato a ser pesquisado)
- Múltiplos comandos podem ser enviados em uma única requisição
- Cada comando na requisição corresponde a uma resposta no array

**Exemplo de Requisição Múltipla**:

```
POST https://g.api.mega.co.nz/cs
[
  {"a": "f", "c": 1},
  {"a": "us", "user": "email@example.com", "uh": "hash"}
]
```

**Tratamento de Respostas**:

- Sempre verificar se resposta é array
- Extrair primeiro elemento se array de tamanho 1
- Verificar campo `e` para erros (código negativo)
- Validar estrutura antes de acessar campos

**Autenticação**:

```
POST https://g.api.mega.co.nz/cs
[{
  "a": "us",
  "user": "email@example.com",
  "uh": "hashed_password"
}]
```

**Nota Importante sobre Hash de Senha**:

- A senha precisa ser hasheada antes de enviar
- Algoritmo: SHA-256 da senha + base64 (verificar durante implementação)
- Possível necessidade de biblioteca `crypto` do Dart
- **Pesquisa necessária**: Verificar algoritmo exato e formato do campo `uh`

**Resposta de Autenticação**:

- Retorna `session ID` e `master key` (criptografado)
- Session ID usado em requisições subsequentes
- Master key necessário para descriptografar dados (E2EE - futuro)
- Armazenar session ID criptografado usando `EncryptionService`

**Upload de Arquivo**:

1. Obter URL de upload:
   ```
   [{"a": "u", "s": file_size}]
   ```

Resposta: `[{"p": "upload_url"}]`

2. Upload chunks:

   - POST direto para `{upload_url}/{offset}` (offset em bytes)
   - Chunks podem ser enviados em qualquer ordem
   - Cada chunk retorna completion handle (27 caracteres base64) ou erro
   - Tamanho de chunk: 4MB (configurável)

3. Completar upload:
   ```
   [{
     "a": "p",
     "t": folder_handle,
     "n": [{
       "h": completion_handle,
       "t": 0,
       "a": encrypted_attributes
     }]
   }]
   ```

   - `t: 0` = arquivo, `t: 1` = pasta
   - `encrypted_attributes`: Atributos criptografados (formato a ser pesquisado)

**Criação de Pasta**:

```
[{
  "a": "p",
  "t": parent_handle,
  "n": [{
    "n": "folder_name",
    "t": 1
  }]
}]
```

- `t: 1` indica que é uma pasta (folder)
- `t: 0` indica que é um arquivo (file)
- Retorna handle da pasta criada

**Listagem de Arquivos/Pastas**:

```
[{
  "a": "f",
  "c": 1
}]
```

- Retorna estrutura de nós (nodes) da conta
- Cada nó tem handle, tipo, nome, etc.
- Usar para navegar estrutura e encontrar pastas

**Deleção de Arquivo/Pasta**:

```
[{
  "a": "d",
  "n": node_handle
}]
```

**Obter Handle da Pasta Raiz**:

- Pasta raiz geralmente tem handle específico (pesquisar durante implementação)
- Ou usar comando para listar e encontrar pasta raiz

### 7.3 Códigos de Erro MEGA

**Códigos HTTP**:

- 200: Sucesso
- 400: Requisição inválida
- 401: Não autenticado (sessão expirada)
- 403: Sem permissão
- 409: Conflito (arquivo já existe)
- 429: Rate limit excedido
- 500: Erro do servidor

**Códigos de Erro MEGA (negativos na resposta JSON)**:

- -1: Erro interno
- -2: Argumentos inválidos
- -3: Rate limit
- -4: Tentativas de login excedidas
- -6: Conta não encontrada
- -9: Rate limit (específico)
- -11: Acesso negado
- -13: Erro de quota
- -15: Quota excedida
- -16: Nó não encontrado
- -17: Circular linkage (nó já existe)
- -18: Nó já existe

**Tratamento de Erros**:

- Verificar campo `e` na resposta JSON para códigos de erro
- Mapear códigos para mensagens amigáveis em `_getMegaErrorMessage()`
- Incluir `originalError` para debugging

### 7.4 Criptografia E2EE (Futuro)

**Implementação Inicial**:

- Usar HTTPS para comunicação
- Não implementar E2EE na primeira versão
- Armazenar master key criptografado (usar `EncryptionService`)
- Usar atributos básicos não criptografados para upload inicial

**Implementação Futura (se necessário)**:

- Requer implementação de AES-128 CTR para criptografia
- Requer CBC-MAC para integridade
- Requer gerenciamento de chaves de criptografia por arquivo
- Complexidade alta - adiar para versão futura

### 7.5 Pesquisa Adicional Necessária Durante Implementação

**Pontos que precisam ser pesquisados/testados**:

1. **Hash de Senha**:

   - Algoritmo exato de hash (SHA-256 + base64?)
   - Formato do campo `uh` na requisição
   - Testar com credenciais reais durante desenvolvimento

2. **Session ID**:

   - Como incluir session ID nas requisições (header? query param? body?)
   - Validade da sessão
   - Como detectar sessão expirada (código de erro específico?)

3. **Node Handles**:

   - Formato dos handles (base64? hex? string?)
   - Como obter handle da pasta raiz
   - Como navegar estrutura de pastas
   - Como encontrar pasta por nome/caminho

4. **Upload Chunks**:

   - Tamanho ideal de chunks (4MB é padrão)
   - Ordem de upload (sequencial ou paralelo?)
   - Como tratar falhas em chunks individuais
   - Como retomar upload interrompido

5. **Encrypted Attributes**:

   - Formato dos atributos criptografados
   - Se necessário para upload sem E2EE (atributos básicos)
   - Como gerar atributos básicos (nome do arquivo, etc.)

6. **Estrutura de Resposta**:

   - Formato exato das respostas da API
   - Como extrair dados das respostas
   - Tratamento de arrays de respostas

**Recomendação**:

- Criar POC (Proof of Concept) primeiro
- Testar autenticação e upload simples
- Documentar descobertas durante implementação
- Ajustar plano conforme necessário
- Usar ferramentas como Postman/Insomnia para testar API antes de implementar

## Checklist de Implementação

- [ ] Domain: Adicionar `mega` ao enum `DestinationType`
- [ ] Domain: Criar `MegaDestinationConfig`
- [ ] Domain: Criar `SendToMega` use case
- [ ] Domain: Atualizar `CleanOldBackups`
- [ ] Core: Criar `MegaFailure`
- [ ] Core: Adicionar constantes MEGA
- [ ] Infrastructure: Criar `MegaAuthService`
- [ ] Infrastructure: Criar `MegaDestinationService`
- [ ] Infrastructure: Criar barrel file
- [ ] Application: Criar `MegaAuthProvider`
- [ ] Presentation: Atualizar `DestinationDialog`
- [ ] Presentation: Atualizar `DestinationListItem`
- [ ] Presentation: Adicionar cor MEGA
- [ ] DI: Registrar serviços no `service_locator`
- [ ] DI: Atualizar `SchedulerService`
- [ ] DI: Adicionar `MegaAuthProvider` ao `MultiProvider`
- [ ] Export: Adicionar exports necessários

## Banco de Dados

### Análise da Estrutura Existente

**Conclusão: NÃO É NECESSÁRIA MIGRAÇÃO DE BANCO DE DADOS**

A tabela `backup_destinations_table` já possui todos os campos necessários:

- `id`: Identificador único
- `name`: Nome do destino
- `type`: Tipo do destino (texto) - suporta qualquer valor, incluindo "mega"
- `config`: Configuração em JSON - armazena `MegaDestinationConfig` serializado
- `enabled`: Status ativo/inativo
- `createdAt` e `updatedAt`: Timestamps

**Como funciona**:

- O campo `type` armazena o nome do enum como string (ex: "mega")
- O campo `config` armazena JSON com `MegaDestinationConfig.toJson()`
- O `BackupDestinationRepository` já faz a conversão automática

**Exemplo de config JSON para MEGA**:

```json
{
  "folderPath": "/Backups",
  "folderName": "Backups",
  "retentionDays": 30
}
```

## Melhorias no Uso de result_dart

### Padrões Identificados e Melhorias

#### 1. Mensagens de Erro Específicas

**Padrão atual (Dropbox)**:

- `_getDropboxErrorMessage()` retorna mensagens amigáveis baseadas no tipo de erro
- Cobre casos: 401, 403, 409, 507, network, timeout

**Aplicar para MEGA**:

- Criar `_getMegaErrorMessage()` seguindo o mesmo padrão
- Mapear códigos de erro da API MEGA para mensagens amigáveis
- Incluir códigos específicos do MEGA (ex: -9 para rate limit, -15 para over quota)

#### 2. Uso Consistente de Result

**Garantir que todos os métodos retornem `rd.Result<T>`**:

- `MegaAuthService`: Todos os métodos retornam `rd.Result<MegaAuthResult>`
- `MegaDestinationService`: Todos os métodos retornam `rd.Result<T>`
- `SendToMega`: Retorna `rd.Result<MegaUploadResult>`

**Padrão de tratamento**:

```dart
final result = await service.upload(...);
return result.fold(
  (success) => rd.Success(success),
  (failure) => rd.Failure(
    MegaFailure(
      message: _getMegaErrorMessage(failure),
      originalError: failure,
    ),
  ),
);
```

#### 3. Validações com Result

**No Use Case `SendToMega`**:

- Validar `sourceFilePath.isEmpty` → retornar `ValidationFailure`
- Validar `config.folderName.isEmpty` → retornar `ValidationFailure`
- Usar mensagens específicas e claras

#### 4. Tratamento de Erros HTTP

**Mapear códigos HTTP para mensagens**:

- 401: "Sessão MEGA expirada. Faça login novamente."
- 403: "Sem permissão para acessar o MEGA."
- 409: "Arquivo ou pasta já existe. O sistema tentará sobrescrever."
- 429: "Muitas requisições. Aguarde alguns instantes."
- 507: "Limite de armazenamento atingido. Libere espaço."

**Códigos de erro MEGA (negativos)**:

- -9: "Limite de requisições excedido. Tente novamente mais tarde."
- -15: "Quota de armazenamento excedida."
- -17: "Arquivo muito grande para o plano atual."

#### 5. Erros de Rede e Timeout

**Tratamento específico**:

- Network errors: "Erro de conexão com o MEGA. Verifique sua internet."
- Timeout: "Tempo limite excedido. Para arquivos grandes, o upload pode levar vários minutos."
- Connection refused: "Não foi possível conectar ao MEGA. Verifique sua conexão."

#### 6. Preservar Erro Original

**Sempre incluir `originalError`**:

```dart
return rd.Failure(
  MegaFailure(
    message: _getMegaErrorMessage(e),
    originalError: e,
  ),
);
```

Isso permite logging detalhado e debugging sem expor detalhes técnicos ao usuário.

## Dependências Adicionais

### Bibliotecas Necessárias

**Já presentes no projeto**:

- `dio`: HTTP client (já usado)
- `result_dart`: Tratamento de erros (já usado)
- `shared_preferences`: Armazenamento (já usado)
- `encryption_service`: Criptografia de credenciais (já existe)

**Possivelmente necessárias** (verificar durante implementação):

- `crypto`: Para hash de senha (SHA-256)
  - Verificar se já está no projeto
  - Se não, adicionar: `crypto: ^3.0.3`

**Não necessárias inicialmente**:

- Bibliotecas de criptografia AES (para E2EE futuro)
- Bibliotecas específicas do MEGA (não existem)

## Estratégia de Implementação

### Fase 1: POC (Proof of Concept)

**Antes de implementar tudo, criar POC para validar**:

1. Autenticação básica (email/senha)

   - Testar hash de senha
   - Obter session ID
   - Validar formato de resposta

2. Upload simples

   - Upload de arquivo pequeno (< 4MB)
   - Validar fluxo completo
   - Testar tratamento de erros

3. Criação de pasta

   - Criar pasta de teste
   - Validar estrutura de comandos

**Resultado esperado**:

- Validar que a API funciona como esperado
- Documentar descobertas técnicas
- Ajustar plano se necessário

### Fase 2: Implementação Completa

**Após POC validado**:

- Implementar seguindo o plano completo
- Reutilizar padrões do Dropbox
- Testar cada componente isoladamente

## Notas Importantes

- **Banco de Dados**: Não é necessária migração - estrutura atual já suporta MEGA
- **POC Primeiro**: Criar POC antes de implementação completa para validar API
- **Pesquisa Durante Implementação**: Alguns detalhes técnicos precisam ser pesquisados/testados
- Evitar comentários desnecessários no código
- Seguir padrões de nomenclatura do projeto
- Usar `result_dart` para todos os retornos que podem falhar
- Mensagens de erro devem ser amigáveis e específicas
- Sempre incluir `originalError` para debugging
- Reutilizar padrões de retry e tratamento de erros
- Manter consistência com implementação Dropbox
- Testar autenticação e upload antes de completar

