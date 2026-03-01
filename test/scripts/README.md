# Test Scripts

Scripts Python para automacao de testes do servidor e cliente.

## Localizacao

Todos os scripts estao localizados em `test/scripts/` e devem ser executados a partir da raiz do projeto.

## Uso

Execute os scripts a partir da raiz do projeto:

```bash
# Verificar ambiente
python test/scripts/verify_env.py

# Iniciar servidor
python test/scripts/start_server.py

# Iniciar cliente
python test/scripts/start_client.py

# Iniciar ambos automaticamente
python test/scripts/start_both.py

# Verificar se servidor esta rodando
python test/scripts/check_server.py

# Parar todas as instancias
python test/scripts/stop_all.py
```

## Scripts Disponiveis

| Script | Proposito |
|--------|-----------|
| `verify_env.py` | Verifica configuracao do ambiente |
| `start_server.py` | Inicia app em modo servidor |
| `start_client.py` | Inicia app em modo cliente |
| `start_both.py` | Inicia server + client automaticamente |
| `check_server.py` | Verifica se server esta respondendo |
| `test_socket.py` | Testa configuracao de socket |
| `stop_all.py` | Para todas as instancias do Flutter |
| `find_logs.py` | Encontra e exibe logs recentes |
| `get_logs.py` | Coleta todos os logs para analise |
| `run_integration_tests.py` | Executa testes de integracao (Socket, File Transfer) |
| `run_ftp_integration_tests.py` | Executa testes de integracao FTP (upload, fallback, testConnection) |

## Documentacao

Os scripts acima sao usados para testes de integracao servidor/cliente. Execute a partir da raiz do projeto.
