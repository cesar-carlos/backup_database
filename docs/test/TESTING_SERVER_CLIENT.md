# Guia de Testes: Servidor + Cliente Local

Este guia explica como rodar **duas instâncias** do Backup Database localmente para testar a comunicação socket entre servidor e cliente.

---

## 📋 Pré-requisitos

- Windows 11/10
- Flutter instalado e configurado
- PowerShell
- Dois terminais (ou use o script `start_both.ps1`)

---

## 🚀 Início Rápido

### Opção 1: Automático (Ambas as Instâncias)

```powershell
# Verifica ambiente
.\test\scripts\verify_env.ps1

# Inicia server + client automaticamente
.\test\scripts\start_both.ps1
```

### Opção 2: Manual (Dois Terminais)

**Terminal 1 - Servidor:**
```powershell
.\test\scripts\start_server.ps1
```

**Terminal 2 - Cliente:**
```powershell
.\test\scripts\start_client.ps1
```

---

## 🔧 Como Funciona

### Isolamento de Configuração

Cada modo tem seu próprio arquivo `.env`:

```
.env.server    → Configurações do servidor
.env.client    → Configurações do cliente
.env           → Arquivo ativo (alterado pelos scripts)
```

### Chaves de Configuração

| Configuração | Valor (Server) | Valor (Client) | Propósito |
|--------------|----------------|----------------|-----------|
| `SINGLE_INSTANCE_ENABLED` | `false` | `false` | Permite múltiplas instâncias |
| `DEBUG_APP_MODE` | `server` | `client` | Define modo de operação |
| `SOCKET_SERVER_PORT` | `9527` | (não usado) | Porta do socket server |

### Isolamento de Banco de Dados

✅ **PROBLEMA RESOLVIDO:** Server e client usam **BANCOS SEPARADOS** para evitar conflitos.

```
%APPDATA%\backup_database\
├── backup_database.db              ← SERVER (mantém compatibilidade)
└── backup_database_client.db       ← CLIENT (isolado)
```

**Por que separar?**
- ❌ **Antes:** Ambas as instâncias usavam o mesmo arquivo → write conflicts, locks, corrupção
- ✅ **Depois:** Cada instância tem seu próprio banco → zero conflitos

**Documentação completa:** Veja `DATABASE_ISOLATION.md` para detalhes técnicos.

---

## 📝 Fluxo de Teste Completo

### 1. Preparação

```powershell
# Verificar se ambiente está correto
.\test\scripts\verify_env.ps1
```

Saída esperada:
```
✓ Ambiente configurado corretamente!
✓ Pronto para rodar server + client
```

### 2. Iniciar Servidor

```powershell
.\test\scripts\start_server.ps1
```

O que acontece:
1. Backup do `.env` atual → `.env.backup`
2. Copia `.env.server` → `.env`
3. Inicia app em modo servidor
4. Socket server escuta na porta 9527
5. App mostra UI de servidor (gerenciar clientes, agendamentos)

**Indicadores de sucesso:**
- Console mostra: "Modo detectado: AppMode.server"
- Console mostra: "Socket server iniciado na porta 9527"
- UI mostra aba "Clientes Conectados"

### 3. Verificar Servidor

```powershell
# Em outro terminal
.\test\scripts\check_server.ps1
```

Saída esperada:
```
✓ SUCESSO: Server está rodando e aceitando conexões
  - Host: localhost
  - Porta: 9527
  - Status: Conectado
```

### 4. Iniciar Cliente

```powershell
# Em outro terminal
.\test\scripts\start_client.ps1
```

O que acontece:
1. Backup do `.env` atual → `.env.backup`
2. Copia `.env.client` → `.env`
3. Inicia app em modo cliente
4. **NÃO** inicia socket server
5. App mostra UI de cliente (conectar a servidor, agendamentos remotos)

**Indicadores de sucesso:**
- Console mostra: "Modo detectado: AppMode.client"
- Console mostra: "Socket server não será iniciado"
- UI mostra tela "Conectar ao Servidor"

### 5. Conectar Cliente ao Servidor

**Na UI do cliente:**

1. Abra a tela "Conectar ao Servidor"
2. Preencha:
   - **Nome da Conexão**: "Servidor Local"
   - **Host/IP**: `localhost`
   - **Porta**: `9527`
   - **Server ID**: (pegar do servidor, ver abaixo)
   - **Password**: (pegar do servidor, ver abaixo)
3. Clique "Conectar"

**Como obter Server ID e Password:**

**Na UI do servidor:**
1. Vá em "Configurações" → "Credenciais de Acesso"
2. Anote o "Server ID" e "Password" da credencial ativa
3. Ou crie uma nova credencial para testes

### 6. Testar Comunicação

**Na UI do cliente, após conectar:**

1. **Listar Agendamentos Remotos:**
   - Vá para "Agendamentos Remotos"
   - Veja a lista de agendamentos do servidor
   - Tente alterar um agendamento (tipo, data, etc)

2. **Transferir Arquivos:**
   - Vá para "Transferir Backups"
   - Veja a lista de arquivos disponíveis no servidor
   - Selecione um arquivo
   - Escolha pasta de destino
   - Clique "Transferir"
   - Acompanhe progresso da transferência

3. **Ver Dashboard:**
   - Vá para "Dashboard"
   - Veja métricas combinadas (local + servidor)

**Na UI do servidor:**

1. **Monitorar Clientes:**
   - Vá para "Configurações" → "Clientes Conectados"
   - Veja o cliente conectado
   - Veja last heartbeat, IP, porta

2. **Ver Log de Conexões:**
   - Vá para "Configurações" → "Log de Conexões"
   - Veja tentativas de conexão (sucesso/falha)

---

## 🧪 Testes Automatizados

### Testes de Integração

```powershell
# Teste comunicação socket básica
dart test test/integration/socket_integration_test.dart

# Teste transferência de arquivos
dart test test/integration/file_transfer_integration_test.dart
```

### Testes Unitários

```powershell
# Testar protocolo
dart test test/unit/infrastructure/protocol/

# Testar socket server
dart test test/unit/infrastructure/socket/tcp_socket_server_test.dart

# Testar socket client
dart test test/unit/infrastructure/socket/tcp_socket_client_test.dart
```

---

## 🛠️ Scripts Disponíveis

Todos os scripts estão localizados em `test/scripts/`:

| Script | Propósito |
|--------|-----------|
| `test/scripts/verify_env.ps1` | Verifica configuração do ambiente |
| `test/scripts/start_server.ps1` | Inicia app em modo servidor |
| `test/scripts/start_client.ps1` | Inicia app em modo cliente |
| `test/scripts/start_both.ps1` | Inicia server + client automaticamente |
| `test/scripts/check_server.ps1` | Verifica se server está respondendo |
| `test/scripts/test_socket.ps1` | Testa configuração de socket |
| `test/scripts/stop_all.ps1` | Para todas as instâncias do Flutter |
| `test/scripts/find_logs.ps1` | Encontra e exibe logs recentes |
| `test/scripts/get_logs.ps1` | Coleta todos os logs para análise |
| `test/scripts/run_integration_tests.ps1` | Executa todos os testes de integração |

---

## ⚠️ Solução de Problemas

### Erro: "Já existe uma instância rodando"

**Causa:** `SINGLE_INSTANCE_ENABLED=true` no `.env`

**Solução:**
```powershell
# Edite .env.server e .env.client
SINGLE_INSTANCE_ENABLED=false
```

### Erro: "Server não está respondendo"

**Causas possíveis:**
1. Server não iniciado
2. Firewall bloqueando porta 9527
3. Server em porta diferente

**Solução:**
```powershell
# 1. Verificar se server está rodando
.\test\scripts\check_server.ps1

# 2. Se não estiver, inicie
.\test\scripts\start_server.ps1

# 3. Verificar firewall (Windows)
# Adicionar exceção para porta 9527
New-NetFirewallRule -DisplayName "Backup DB Server" -Direction Inbound -LocalPort 9527 -Protocol TCP -Action Allow
```

### Erro: "Autenticação falhou"

**Causas possíveis:**
1. Server ID errado
2. Password errada
3. Credencial inativa no servidor

**Solução:**
```powershell
# No servidor:
# 1. Vá em "Configurações" → "Credenciais de Acesso"
# 2. Verifique se a credencial está "Ativa"
# 3. Anote Server ID e Password corretos
# 4. No cliente, use exatamente esses valores
```

### Erro: "Transferência de arquivo falhou"

**Causas possíveis:**
1. Arquivo não existe no servidor
2. Path não está em allowedBasePath
3. Sem permissão de escrita no destino

**Solução:**
```powershell
# 1. Verificar logs do servidor e cliente
# 2. No servidor, verificar se o arquivo existe em:
#    %APPDATA%/backup_database/backups/
# 3. No cliente, verificar permissões na pasta de destino
```

### Conexão cai durante transferência

**Causas possíveis:**
1. Timeout de heartbeat
2. Interrupção de rede
3. Server crash

**Solução:**
```powershell
# 1. Verificar logs para identificar causa
# 2. Se for timeout, aumentar valores em SocketConfig
# 3. Client tem auto-reconnect habilitado
```

---

## 📊 Cenários de Teste

### Cenário 1: Conexão Básica

```
1. Iniciar servidor
2. Iniciar cliente
3. Conectar cliente ao servidor
4. Verificar cliente aparece na lista do servidor
5. Desconectar cliente
6. Verificar cliente some da lista do servidor
```

### Cenário 2: Agendamentos Remotos

```
1. Conectar cliente ao servidor
2. Listar agendamentos remotos
3. Alterar tipo de backup de um agendamento
4. Verificar alteração foi aplicada no servidor
5. Executar agendamento remotamente
6. Verificar backup foi executado no servidor
```

### Cenário 3: Transferência de Arquivo

```
1. No servidor, ter um backup pronto em %APPDATA%/backups/
2. Conectar cliente ao servidor
3. No cliente, listar arquivos remotos
4. Selecionar arquivo para transferência
5. Escolher pasta de destino
6. Iniciar transferência
7. Acompanhar progresso
8. Verificar arquivo recebido intactamente (checksum)
```

### Cenário 4: Múltiplos Clientes

```
1. Iniciar servidor
2. Iniciar 3 clientes (3 terminais)
3. Conectar todos ao servidor
4. Verificar servidor mostra 3 clientes
5. Cada cliente listar agendamentos
6. Transferir arquivo para cliente 1
7. Transferir arquivo para cliente 2
8. Verificar transferências simultâneas funcionam
```

### Cenário 5: Reconexão Automática

```
1. Conectar cliente ao servidor
2. Matar servidor (Ctrl+C)
3. Verificar cliente detecta desconexão
4. Reiniciar servidor
5. Verificar cliente reconecta automaticamente
6. Verificar estado restaurado após reconexão
```

---

## 🧽 Limpeza

### Parar Todas as Instâncias

```powershell
# Matar todos os processos flutter
Get-Process | Where-Object {$_.ProcessName -like "flutter*"} | Stop-Process -Force

# Ou simplesmente Ctrl+C em cada terminal
```

### Restaurar .env Original

Os scripts restauram automaticamente o `.env` original ao sair, mas se algo der errado:

```powershell
# Se existir backup
if (Test-Path ".env.backup") {
    Copy-Item ".env.backup" ".env" -Force
    Remove-Item ".env.backup" -Force
}
```

### Limpar Arquivos Temporários

```powershell
# Remover arquivos criados pelos scripts
Remove-Item ".env.backup" -Force -ErrorAction SilentlyContinue
Remove-Item ".server.pid" -Force -ErrorAction SilentlyContinue
```

---

## 📚 Referências

- [Implementação Cliente-Servidor](docs/dev/implementacao_cliente_servidor.md)
- [Plano Detalhado](docs/dev/plano_cliente_servidor.md)
- [Testes de Integração](test/integration/)

---

## 🎯 Próximos Passos

Após testar com sucesso:

1. ✅ Testar em máquinas diferentes (LAN)
2. ✅ Testar com firewall ativo
3. ✅ Testar transferência de arquivos grandes (>1GB)
4. ✅ Testar com múltiplos clientes simultâneos
5. ✅ Testar reconexão após queda de rede
6. ✅ Criar suite de testes automatizada completa

---

**Documento criado em**: 02/02/2026
**Versão**: 1.0
**Status**: Pronto para uso
