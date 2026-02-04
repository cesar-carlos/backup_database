# Quick Reference - Server + Client Testing

Guia rápido de referência para testes de comunicação socket.

---

## 🚀 Comandos Rápidos

### Início Rápido
```powershell
# Verificar ambiente
.\test\scripts\verify_env.ps1

# Rodar ambos automaticamente
.\test\scripts\start_both.ps1

# Verificar se server está rodando
.\test\scripts\check_server.ps1
```

### Início Manual
```powershell
# Terminal 1 - Servidor
.\test\scripts\start_server.ps1

# Terminal 2 - Cliente
.\test\scripts\start_client.ps1
```

### Testes Automatizados
```powershell
# Testes de integração
.\test\scripts\run_integration_tests.ps1

# Ou manualmente
dart test test/integration/socket_integration_test.dart
dart test test/integration/file_transfer_integration_test.dart
```

### Controle
```powershell
# Parar todas as instâncias
.\test\scripts\stop_all.ps1

# Ver logs recentes
.\test\scripts\find_logs.ps1

# Coletar todos os logs
.\test\scripts\get_logs.ps1
```

---

## 📋 Checklist de Testes

### Testes Básicos ✅
- [ ] Server inicia sem erros
- [ ] Client inicia sem erros
- [ ] Client conecta ao servidor (localhost:9527)
- [ ] Server mostra cliente na lista
- [ ] Client desconecta sem erros
- [ ] Server remove cliente da lista

### Testes de Autenticação 🔐
- [ ] Client conecta com credenciais corretas
- [ ] Client rejeitado com senha errada
- [ ] Client rejeitado com server ID errado
- [ ] Server loga tentativas de conexão
- [ ] Credencial inativa rejeita conexão

### Testes de Agendamentos 📅
- [ ] Client lista agendamentos do servidor
- [ ] Client altera tipo de backup
- [ ] Client altera data de execução
- [ ] Client altera script pós-backup
- [ ] Client executa agendamento remotamente
- [ ] Server aplica alterações corretamente
- [ ] Server executa backup quando solicitado

### Testes de Transferência de Arquivos 📁
- [ ] Client lista arquivos disponíveis no servidor
- [ ] Client inicia transferência de arquivo
- [ ] Progresso de transferência atualiza em tempo real
- [ ] Arquivo recebido íntegro (checksum OK)
- [ ] Arquivo salvo na pasta correta
- [ ] Transferência de arquivo grande (>100MB) funciona
- [ ] Transferência interrompida é retomada

### Testes de Múltiplos Clientes 👥
- [ ] 3 clientes conectam simultaneamente
- [ ] Server mostra todos na lista
- [ ] Cada cliente opera independentemente
- [ ] Múltiplas transferências simultâneas funcionam
- [ ] Client desconecta sem afetar outros

### Testes de Reconexión 🔄
- [ ] Client detecta queda do servidor
- [ ] Client tenta reconexão automática
- [ ] Client reconecta quando server volta
- [ ] Estado restaurado após reconexão
- [ ] Transferências são retomadas

### Testes de Estresse ⚡
- [ ] 100 mensagens trocadas sem erro
- [ ] Transferência de arquivo 1GB funciona
- [ ] Server suporta 10 clientes simultâneos
- [ ] Uso de memória permanece estável
- [ ] Não há memory leaks após 1 hora

---

## 🔧 Configurações

### .env.server
```ini
SINGLE_INSTANCE_ENABLED=false
DEBUG_APP_MODE=server
SOCKET_SERVER_PORT=9527
```

### .env.client
```ini
SINGLE_INSTANCE_ENABLED=false
DEBUG_APP_MODE=client
```

---

## 📊 Portas e Endereços

| Componente | Host | Porta | Protocolo |
|-----------|------|-------|-----------|
| Socket Server | localhost | 9527 | TCP |
| IPC (single instance) | localhost | dinâmica | TCP |

---

## 🐛 Debugging

### Verificar Server
```powershell
.\test\scripts\check_server.ps1
```

**Saída esperada:**
```
✓ SUCESSO: Server está rodando e aceitando conexões
  - Host: localhost
  - Porta: 9527
```

### Ver Logs
```powershell
# Ver logs recentes
.\test\scripts\find_logs.ps1

# Coletar todos os logs
.\test\scripts\get_logs.ps1
```

### Testar Conexão Manual
```powershell
# Teste rápido de TCP
Test-NetConnection -ComputerName localhost -Port 9527
```

### Ver Processos
```powershell
# Ver processos rodando
Get-Process | Where-Object {$_.ProcessName -like "*flutter*"}

# Parar tudo
.\test\scripts\stop_all.ps1
```

---

## ⚠️ Problemas Comuns

| Problema | Solução |
|---------|---------|
| Single instance error | `SINGLE_INSTANCE_ENABLED=false` |
| Server não responde | Verificar com `check_server.ps1` |
| Autenticação falha | Verificar Server ID/Password no servidor |
| Transferência falha | Verificar permissões de pasta |
| Conexão cai | Verificar firewall/antivírus |

---

## 📚 Documentação

| Documento | Descrição |
|-----------|-----------|
| `TESTING_SERVER_CLIENT.md` | Guia completo de testes |
| `docs/dev/implementacao_cliente_servidor.md` | Implementação técnica |
| `docs/dev/plano_cliente_servidor.md` | Planejamento |

---

## 🎯 Fluxo de Teste Típico

```
1. .\test\scripts\verify_env.ps1
   └─> Verifica ambiente

2. .\test\scripts\start_server.ps1
   └─> Inicia servidor (Terminal 1)

3. .\test\scripts\check_server.ps1
   └─> Confirma servidor rodando

4. .\test\scripts\start_client.ps1
   └─> Inicia cliente (Terminal 2)

5. [Conectar na UI do cliente]
   └─> localhost:9527 + credenciais

6. [Testar funcionalidades]
   ├─> Listar agendamentos
   ├─> Alterar agendamento
   ├─> Transferir arquivo
   └─> Ver dashboard

7. .\stop_all.ps1
   └─> Parar tudo
```

---

## 🔗 Links Rápidos

- [Testes de Integração](test/integration/)
- [Testes Unitários](test/unit/)
- [Protocolo](lib/infrastructure/protocol/)
- [Socket Server](lib/infrastructure/socket/server/)
- [Socket Client](lib/infrastructure/socket/client/)

---

**Última atualização**: 02/02/2026
