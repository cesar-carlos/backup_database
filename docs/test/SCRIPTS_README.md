# Scripts de Teste - Server + Client

Coleção de scripts PowerShell para facilitar testes de comunicação socket entre servidor e cliente do Backup Database.

---

## 📋 Scripts Disponíveis

### 🛠️ Configuração e Verificação

| Script | Propósito |
|--------|-----------|
| `verify_env.ps1` | Verifica se ambiente está configurado corretamente |
| `check_server.ps1` | Verifica se server está respondendo na porta 9527 |
| `test_socket.ps1` | Testa configuração de socket |

### 🚀 Inicialização

| Script | Propósito |
|--------|-----------|
| `start_server.ps1` | Inicia app em **modo servidor** |
| `start_client.ps1` | Inicia app em **modo cliente** |
| `start_both.ps1` | Inicia **ambos automaticamente** |

### 🧪 Testes

| Script | Propósito |
|--------|-----------|
| `run_integration_tests.ps1` | Executa todos os testes de integração |

### 📝 Logs e Debugging

| Script | Propósito |
|--------|-----------|
| `find_logs.ps1` | Busca e exibe logs recentes |
| `get_logs.ps1` | Coleta todos os logs para análise |

### 🛑 Controle

| Script | Propósito |
|--------|-----------|
| `stop_all.ps1` | Para todas as instâncias rodando |

---

## 🎯 Uso Rápido

### Teste Completo Automatizado

```powershell
# 1. Verificar ambiente
.\test\scripts\verify_env.ps1

# 2. Rodar server + client
.\test\scripts\start_both.ps1

# 3. Testar integração (quando finalizado)
.\test\scripts\stop_all.ps1
.\run_integration_tests.ps1
```

### Teste Manual (Dois Terminais)

**Terminal 1:**
```powershell
.\test\scripts\start_server.ps1
```

**Terminal 2:**
```powershell
.\test\scripts\start_client.ps1
```

---

## 📖 Documentação Detalhada

- **[TESTING_SERVER_CLIENT.md](TESTING_SERVER_CLIENT.md)** - Guia completo de testes
- **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** - Referência rápida

---

## ⚙️ Pré-requisitos

- Windows PowerShell 5.1+
- Flutter instalado e configurado
- Dois terminais (para modo manual)

---

## 📂 Arquivos de Configuração

Os scripts usam estes arquivos de configuração:

- `.env.server` - Configurações do servidor
- `.env.client` - Configurações do cliente
- `.env` - Configuração ativa (alterado pelos scripts)

**Importante:** `SINGLE_INSTANCE_ENABLED=false` é necessário em ambos os arquivos para permitir múltiplas instâncias.

---

## 🔧 Como Funcionam

### Fluxo dos Scripts de Inicialização

```
1. Backup do .env atual → .env.backup
2. Copia .env.server ou .env.client → .env
3. Inicia: flutter run -d windows
4. Ao sair (Ctrl+C): restaura .env.backup
```

### Scripts Automáticos vs Manuais

| Aspecto | Automático (`start_both`) | Manual (dois terminais) |
|---------|--------------------------|------------------------|
| Controle | Server em background | Ambos em foreground |
| Debug | Mais difícil ver logs server | Mais fácil debugar |
| Simplicidade | Um comando | Dois terminais |

**Recomendação:**
- Use **automático** para testes rápidos
- Use **manual** para debug detalhado

---

## 🐛 Troubleshooting

### Erro: "Já existe uma instância rodando"

**Causa:** `SINGLE_INSTANCE_ENABLED=true`

**Solução:**
```powershell
# Edite .env.server e .env.client
# Mude para:
SINGLE_INSTANCE_ENABLED=false
```

### Erro: "Server não está respondendo"

**Solução:**
```powershell
# 1. Verificar se server está rodando
.\test\scripts\check_server.ps1

# 2. Se não estiver, inicie
.\test\scripts\start_server.ps1
```

### Erro: "Autenticação falhou"

**Solução:**
1. No servidor: "Configurações" → "Credenciais de Acesso"
2. Anote Server ID e Password da credencial ativa
3. No cliente: use exatamente esses valores

---

## 📊 Checklist de Testes

### Básico
- [ ] Server inicia sem erros
- [ ] Client inicia sem erros
- [ ] Client conecta ao servidor
- [ ] Server mostra cliente na lista

### Intermédio
- [ ] Listar agendamentos remotos
- [ ] Alterar agendamento
- [ ] Transferir arquivo
- [ ] Ver métricas no dashboard

### Avançado
- [ ] Múltiplos clientes simultâneos
- [ ] Reconexão automática
- [ ] Transferência de arquivo grande (>1GB)

---

## 🎓 Exemplos de Uso

### Exemplo 1: Teste Básico de Conexão

```powershell
# Terminal 1
.\test\scripts\start_server.ps1

# Terminal 2
.\test\scripts\start_client.ps1

# Na UI do cliente, conectar em localhost:9527
```

### Exemplo 2: Teste de Transferência

```powershell
# Terminal 1
.\test\scripts\start_server.ps1

# Terminal 2
.\test\scripts\start_client.ps1

# No cliente:
# 1. Conectar ao servidor
# 2. Ir para "Transferir Backups"
# 3. Listar arquivos
# 4. Selecionar arquivo
# 5. Transferir
```

### Exemplo 3: Debug com Logs

```powershell
# Rodar testes
.\test\scripts\start_both.ps1

# Depois, coletar logs
.\test\scripts\get_logs.ps1

# Ver logs
.\test\scripts\find_logs.ps1
```

---

## 🔄 Workflow Típico

```
Desenvolvimento
    ↓
.\test\scripts\verify_env.ps1 (verificar ambiente)
    ↓
.\test\scripts\start_server.ps1 (terminal 1)
    ↓
.\test\scripts\start_client.ps1 (terminal 2)
    ↓
[Testar funcionalidades na UI]
    ↓
.\test\scripts\stop_all.ps1 (limpar)
    ↓
.\run_integration_tests.ps1 (testes automatizados)
    ↓
Corrigir bugs se necessário
    ↓
Repetir
```

---

## 📚 Referências

### Código

- `lib/infrastructure/socket/server/` - Socket server
- `lib/infrastructure/socket/client/` - Socket client
- `lib/infrastructure/protocol/` - Protocolo binário

### Testes

- `test/integration/socket_integration_test.dart`
- `test/integration/file_transfer_integration_test.dart`
- `test/unit/infrastructure/socket/`

### Documentação

- `docs/dev/implementacao_cliente_servidor.md`
- `docs/dev/plano_cliente_servidor.md`

---

## 🤝 Contribuindo

Ao adicionar novos testes ou funcionalidades:

1. Atualize este README
2. Adicione scripts se necessário
3. Atualize `QUICK_REFERENCE.md`
4. Adicione testes em `test/integration/`

---

## 📝 Notas

- Scripts sempre restauram o `.env` original ao sair
- Arquivos temporários (`.env.backup`, `.server.pid`) são limpos automaticamente
- Logs são salvos em `%APPDATA%\backup_database\`

---

**Última atualização**: 02/02/2026
**Versão**: 1.0
**Status**: Pronto para uso
