# Guia de Funcionamento - Notificacoes por E-mail (SMTP + OAuth)

## 1. Objetivo

Este documento descreve o funcionamento completo das notificacoes por e-mail no projeto, incluindo:

- configuracao SMTP com senha
- configuracao SMTP com OAuth2 (Google e Microsoft)
- fluxo de teste de conexao
- auditoria de testes SMTP
- variaveis obrigatorias de execucao
- diagnostico de erros comuns

## 2. Arquitetura e componentes

### 2.1 Camada de apresentacao (UI)

- Modal de configuracao SMTP:
  - `lib/presentation/widgets/notifications/notification_config_dialog.dart`
- Tela de notificacoes e historico:
  - `lib/presentation/pages/notifications_page.dart`
  - `lib/presentation/widgets/notifications/email_test_history_panel.dart`

### 2.2 Camada de aplicacao

- Provider principal de notificacoes:
  - `lib/application/providers/notification_provider.dart`
- Service de orquestracao de notificacoes:
  - `lib/application/services/notification_service.dart`
- Use case de teste:
  - `lib/domain/use_cases/notifications/test_email_configuration.dart`

### 2.3 Camada de infraestrutura

- Envio SMTP e montagem de credenciais SMTP/XOAUTH2:
  - `lib/infrastructure/external/email/email_service.dart`
- Fluxo OAuth (connect/reconnect/refresh token):
  - `lib/infrastructure/external/email/oauth_smtp_service.dart`

### 2.4 Configuracoes globais

- Constantes e flags de OAuth:
  - `lib/core/constants/app_constants.dart`

## 3. Modos de autenticacao SMTP

A entidade `EmailConfig` suporta os modos:

- `password` (usuario/senha SMTP)
- `oauth_google`
- `oauth_microsoft`

Regra pratica:

- Se modo = `password`: usa `username` + `password`.
- Se modo = OAuth: usa token OAuth e autentica por XOAUTH2.

## 4. Fluxo de teste de conexao SMTP

Fluxo executado ao clicar em `Testar conexao` no modal:

1. UI monta um `EmailConfig` de rascunho.
2. UI chama `NotificationProvider.testDraftConfiguration(config)`.
3. Provider chama use case `TestEmailConfiguration`.
4. Use case chama `NotificationService.testEmailConfiguration(config)`.
5. Service valida campos minimos:
   - destinatario valido
   - remetente valido
6. Service monta assunto e corpo detalhado de teste com `correlationId`.
7. Service chama `EmailService.sendEmail(...)`.
8. `EmailService` monta `SmtpServer`:
   - senha SMTP, ou
   - OAuth com token valido (XOAUTH2).
9. Resultado e salvo na auditoria de testes SMTP.
10. Provider atualiza historico e mensagem de retorno na UI.

Observacao importante:

- Sucesso no teste significa que a mensagem foi aceita pelo servidor SMTP.
- Entrega final na caixa do destinatario pode depender de spam, quarentena e politicas do provedor.

## 5. Fluxo OAuth no projeto

### 5.1 Connect OAuth

- `NotificationProvider.connectOAuth(...)` chama `IOAuthSmtpService.connect(...)`.
- `OAuthSmtpService` valida client config (client id/secret/flags).
- Abre fluxo OAuth via `oauth2_client` usando redirect local:
  - `http://localhost:8085/oauth2redirect`
- Salva token no `ISecureCredentialService`.
- Retorna estado OAuth para atualizar `EmailConfig`.

### 5.2 Reconnect OAuth

- Mesmo fluxo de `connect`, limpando token anterior da configuracao.

### 5.3 Uso em envio

- `EmailService` chama `resolveValidAccessToken(...)`.
- Se token expirou e existe refresh token, tenta refresh.
- Gera token XOAUTH2 e autentica no SMTP.

## 6. Variaveis obrigatorias (build-time)

As credenciais OAuth sao lidas com `String.fromEnvironment`, nao por `.env`.

Isso significa:

- voce precisa passar `--dart-define` ao iniciar/buildar o app
- hot reload nao aplica mudancas nessas variaveis
- precisa restart completo da aplicacao

### 6.1 Google OAuth SMTP

- `ENABLE_GOOGLE_SMTP_OAUTH=true`
- `SMTP_GOOGLE_CLIENT_ID=...`
- `SMTP_GOOGLE_CLIENT_SECRET=...` (quando aplicavel)

### 6.2 Microsoft OAuth SMTP

- `ENABLE_MICROSOFT_SMTP_OAUTH=true`
- `SMTP_MICROSOFT_CLIENT_ID=...`
- `SMTP_MICROSOFT_CLIENT_SECRET=...` (quando aplicavel)
- `SMTP_MICROSOFT_TENANT=common` (ou tenant especifico)

## 7. Perfis VS Code (ja preparados)

Arquivo:

- `.vscode/launch.json`

Perfis adicionados:

- `backup_database (oauth microsoft)`
- `backup_database (oauth google)`

Esses perfis usam variaveis de ambiente do Windows:

- `SMTP_MICROSOFT_CLIENT_ID`
- `SMTP_MICROSOFT_CLIENT_SECRET`
- `SMTP_MICROSOFT_TENANT`
- `SMTP_GOOGLE_CLIENT_ID`
- `SMTP_GOOGLE_CLIENT_SECRET`

## 8. Exemplo de execucao via terminal

### 8.1 Microsoft

```bash
flutter run -d windows \
  --dart-define=ENABLE_MICROSOFT_SMTP_OAUTH=true \
  --dart-define=SMTP_MICROSOFT_TENANT=common \
  --dart-define=SMTP_MICROSOFT_CLIENT_ID=SEU_CLIENT_ID \
  --dart-define=SMTP_MICROSOFT_CLIENT_SECRET=SEU_CLIENT_SECRET
```

### 8.2 Google

```bash
flutter run -d windows \
  --dart-define=ENABLE_GOOGLE_SMTP_OAUTH=true \
  --dart-define=SMTP_GOOGLE_CLIENT_ID=SEU_CLIENT_ID \
  --dart-define=SMTP_GOOGLE_CLIENT_SECRET=SEU_CLIENT_SECRET
```

## 9. Setup de provedor OAuth

### 9.1 Microsoft (Azure/Entra)

Passo a passo:

1. Acesse o portal Entra:
   - `https://entra.microsoft.com`
2. Entre em:
   - `Identity > Applications > App registrations > New registration`
3. Preencha:
   - Name: `Backup Database SMTP OAuth`
   - Supported account types:
     - single-tenant (empresa) ou
     - multi-tenant/consumers (se precisa Outlook pessoal)
4. Crie o app e copie:
   - `Application (client) ID` -> usar em `SMTP_MICROSOFT_CLIENT_ID`
   - `Directory (tenant) ID` (opcional) -> usar em `SMTP_MICROSOFT_TENANT`
5. Configure redirect URI:
   - `Authentication > Add a platform > Mobile and desktop applications`
   - Redirect URI:
     - `http://localhost:8085/oauth2redirect`
6. Habilite public client (quando necessario):
   - `Authentication > Allow public client flows = Yes`
7. Configure permissoes:
   - `API permissions > Add a permission > Microsoft Graph > Delegated permissions`
   - Adicionar:
     - `openid`
     - `profile`
     - `email`
     - `offline_access`
     - `User.Read`
   - `Add a permission > APIs my organization uses` (ou API Outlook) e incluir:
     - `https://outlook.office.com/SMTP.Send`
8. Conceda consentimento:
   - `Grant admin consent` (se sua politica exigir)
9. Se seu fluxo exigir segredo:
   - `Certificates & secrets > New client secret`
   - usar valor em `SMTP_MICROSOFT_CLIENT_SECRET`
10. Validar no app:
   - iniciar com `--dart-define`
   - no modal, selecionar `Microsoft OAuth2`
   - clicar `Conectar`

### 9.2 Google

Passo a passo:

1. Acesse o Google Cloud Console:
   - `https://console.cloud.google.com`
2. Crie/seleciona um projeto.
3. Configure tela de consentimento OAuth:
   - `APIs & Services > OAuth consent screen`
   - Escolha `External` ou `Internal`
   - Preencha dados basicos (nome app, email suporte, dominio quando aplicavel)
4. Configure escopos no consentimento:
   - `https://mail.google.com/`
   - `https://www.googleapis.com/auth/userinfo.email`
   - `openid`
   - `profile`
5. Crie credencial OAuth:
   - `APIs & Services > Credentials > Create Credentials > OAuth client ID`
   - Application type: `Desktop app` (recomendado para loopback local)
6. Copie credenciais:
   - `Client ID` -> `SMTP_GOOGLE_CLIENT_ID`
   - `Client secret` -> `SMTP_GOOGLE_CLIENT_SECRET` (quando usado)
7. Se usar tipo Web em vez de Desktop:
   - adicionar redirect URI autorizado:
     - `http://localhost:8085/oauth2redirect`
8. Publicar app/consentimento:
   - em ambiente externo, concluir publishing e adicionar test users se necessario
9. Validar no app:
   - iniciar com `--dart-define`
   - no modal, selecionar `Google OAuth2`
   - clicar `Conectar`

### 9.3 Resultado esperado para o desenvolvedor

Ao final do setup, o desenvolvedor deve ter:

- `SMTP_MICROSOFT_CLIENT_ID` (e opcionalmente secret/tenant)
- `SMTP_GOOGLE_CLIENT_ID` (e opcionalmente secret)
- permissao de consentimento concluida no tenant/projeto
- fluxo `Conectar` funcionando no modal de notificacao

## 10. Matriz de erros comuns e acao

### Erro

`SMTP_MICROSOFT_CLIENT_ID nao configurado`

Causa:

- modo `Microsoft OAuth2` selecionado sem `--dart-define` correspondente.

Acao:

- definir `SMTP_MICROSOFT_CLIENT_ID` e reiniciar app.

### Erro

`SMTP_GOOGLE_CLIENT_ID nao configurado`

Causa:

- modo `Google OAuth2` selecionado sem `--dart-define` correspondente.

Acao:

- definir `SMTP_GOOGLE_CLIENT_ID` e reiniciar app.

### Erro

`Conexao OAuth SMTP nao configurada para esta conta`

Causa:

- modo OAuth ativo sem token salvo.

Acao:

- usar `Conectar` no modal para completar OAuth.

### Erro

`Falha de autenticacao SMTP`

Causa comum:

- usuario/senha invalidos
- porta/SSL incorretos
- conta bloqueando auth basica

Acao:

- revisar credenciais, porta, SSL e politica do provedor.

### Erro

`Invalid message` ou rejeicao SMTP

Causa comum:

- remetente/destinatario invalidos
- servidor exige regra especifica de from/user
- anti-spam rejeitando conteudo

Acao:

- validar remetente e destinatario
- validar politicas do provedor
- checar logs e historico de testes SMTP

## 11. Checklist operacional de teste

Antes de testar:

- [ ] servidor SMTP correto
- [ ] porta correta (587/465 conforme provedor)
- [ ] modo autenticacao correto (senha ou OAuth)
- [ ] e-mail usuario SMTP valido
- [ ] senha ou OAuth conectado
- [ ] e-mail de destino valido

Ao testar:

- [ ] validar mensagem de sucesso no modal
- [ ] conferir historico de testes SMTP
- [ ] conferir inbox/spam/quarentena do destinatario

## 12. Boas praticas de seguranca

- nao versionar client secret em arquivo de codigo
- usar variaveis de ambiente para segredos
- evitar `ALLOW_INSECURE_SMTP=true` fora de ambiente controlado
- revisar periodicamente credenciais e consentimentos OAuth

## 13. Resumo do que faltava no erro atual

Para o erro visto em tela (`SMTP_MICROSOFT_CLIENT_ID nao configurado`), faltava:

1. definir `SMTP_MICROSOFT_CLIENT_ID` no ambiente/execucao
2. executar com `--dart-define` (ou perfil VS Code OAuth Microsoft)
3. reiniciar completamente a aplicacao

Sem isso, o modo `Microsoft OAuth2` nao consegue iniciar o fluxo de autenticacao.
