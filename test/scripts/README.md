# Test Scripts

Scripts PowerShell para automação de testes do servidor e cliente.

## Localização

Todos os scripts estão localizados em `test/scripts/` e devem ser executados a partir da raiz do projeto.

## Uso

Execute os scripts a partir da raiz do projeto:

```powershell
# Verificar ambiente
.\test\scripts\verify_env.ps1

# Iniciar servidor
.\test\scripts\start_server.ps1

# Iniciar cliente
.\test\scripts\start_client.ps1

# Iniciar ambos automaticamente
.\test\scripts\start_both.ps1

# Verificar se servidor está rodando
.\test\scripts\check_server.ps1

# Parar todas as instâncias
.\test\scripts\stop_all.ps1
```

## Scripts Disponíveis

| Script | Propósito |
|--------|-----------|
| `verify_env.ps1` | Verifica configuração do ambiente |
| `start_server.ps1` | Inicia app em modo servidor |
| `start_client.ps1` | Inicia app em modo cliente |
| `start_both.ps1` | Inicia server + client automaticamente |
| `check_server.ps1` | Verifica se server está respondendo |
| `test_socket.ps1` | Testa configuração de socket |
| `stop_all.ps1` | Para todas as instâncias do Flutter |
| `find_logs.ps1` | Encontra e exibe logs recentes |
| `get_logs.ps1` | Coleta todos os logs para análise |
| `run_integration_tests.ps1` | Executa testes de integração (Socket, File Transfer) |
| `run_ftp_integration_tests.ps1` | Executa testes de integração FTP (upload, fallback, testConnection) |

## Documentação

Os scripts acima são usados para testes de integração servidor/cliente. Execute a partir da raiz do projeto.
