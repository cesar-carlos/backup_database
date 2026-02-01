# FASE 0 – Plano de testes da migration v14

Objetivo: validar que a migração do banco de dados da versão 13 para a 14 (tabelas cliente-servidor) funciona corretamente em cenários reais.

## O que a migration v14 faz

- Cria as tabelas: `server_credentials_table`, `connection_logs_table`, `server_connections_table`, `file_transfers_table`.
- Cria índices: `idx_server_credentials_active`, `idx_connection_logs_timestamp`, `idx_file_transfers_schedule`.
- Não altera nem remove tabelas/colunas existentes; apenas adiciona novas estruturas.

## Localização do banco no app

- Caminho típico (Windows): `%USERPROFILE%\Documents\backup_database.db`
- Ou: pasta “Documentos” do usuário + `backup_database.db`
- O app usa `getApplicationDocumentsDirectory()` + `backup_database.db`.

---

## Teste 1 – Migration manual com backup do banco

Objetivo: garantir que, a partir de um backup do banco (v13 ou anterior), o app sobe para v14 sem erro e as novas tabelas existem.

### Pré-requisitos

- Ter um **backup** do arquivo `backup_database.db` de uma instalação em v13 (ou anterior), ou
- Uma cópia do banco atual que você vai “rebaixar” para v13 só para testar o upgrade (opcional, ver Observação).

### Passos

1. **Fechar o Backup Database** (e o serviço do Windows, se estiver instalado).
2. **Backup do banco atual**
   - Copiar `backup_database.db` para um local seguro (ex.: `backup_database_backup_YYYYMMDD.db`).
3. **Cenário A – Você tem um banco v13 (instalação antiga)**
   - Colocar o `backup_database.db` v13 na pasta de Documentos (substituindo o atual, se existir).
   - Iniciar o aplicativo.
   - Verificar: o app abre sem exceções e a interface carrega.
   - Verificar no SQLite que a migration rodou (ver “Verificação do schema” abaixo).
4. **Cenário B – Só tem banco atual (já v14)**
   - Usar o backup do passo 2.
   - Opcional: em outro PC/máquina virtual com instalação antiga (v13), copiar de lá o `backup_database.db` e repetir o Cenário A.
5. **Restaurar**
   - Se precisar voltar ao estado anterior: fechar o app, restaurar o backup sobre `backup_database.db` e reabrir.

### Verificação do schema (após abrir o app)

Com o app fechado, abrir o mesmo arquivo `backup_database.db` com um cliente SQLite (DB Browser for SQLite, DBeaver, ou `sqlite3`):

```sql
-- Versão do schema (deve ser 14)
PRAGMA user_version;

-- Tabelas novas da v14 (devem existir)
SELECT name FROM sqlite_master
WHERE type = 'table'
  AND name IN (
    'server_credentials_table',
    'connection_logs_table',
    'server_connections_table',
    'file_transfers_table'
  )
ORDER BY name;
```

- `PRAGMA user_version` deve retornar **14**.
- A consulta deve retornar as **quatro** tabelas listadas.

---

## Teste 2 – Migration com dados existentes

Objetivo: garantir que, após o upgrade para v14, os dados já existentes (agendamentos, configs, histórico, etc.) continuam acessíveis e a UI não quebra.

### Pré-requisitos

- Banco com dados reais: agendamentos, configs de banco (Sybase/SQL Server/PostgreSQL), destinos, histórico de backup, etc.

### Passos

1. **Backup**
   - Fechar o app e fazer cópia de segurança de `backup_database.db`.
2. **Garantir que o banco está em v14**
   - Se o banco já for v14: só abrir o app.
   - Se for v13: abrir o app uma vez para rodar a migration e fechar.
3. **Verificar dados na UI**
   - Aba **Agendamentos**: listar e abrir um agendamento existente.
   - Aba **Configurações** (ou equivalente): configs de banco e destinos.
   - Aba **Histórico** (se houver): listar execuções.
   - **Server Settings** (credenciais do servidor, conexões, log): abrir e listar (podem estar vazios; o importante é não dar erro).
4. **Verificar no SQLite (opcional)**
   - Contar linhas em tabelas antigas (ex.: `schedules_table`, `backup_history_table`, `sybase_configs`, etc.) antes e depois da migration; os números devem ser iguais.
   - Inserir um registro em uma das novas tabelas (ex.: `server_credentials_table`) e reler pela UI (Server Settings) para confirmar que leitura/escrita das novas tabelas funciona.

### Critério de sucesso

- App inicia sem erro.
- Todas as telas/abas acima abrem sem exceção.
- Dados existentes continuam visíveis e consistentes.
- Novas funcionalidades (credenciais do servidor, conexões salvas, log de conexões, transferências) podem ser usadas normalmente após a migration.

---

## Resumo dos critérios de aceitação (FASE 0)

- [ ] **Teste 1**: Migration manual com backup do banco (v13 → v14) concluída sem erro; `user_version = 14` e quatro tabelas v14 presentes.
- [ ] **Teste 2**: Migration com dados existentes; UI e dados antigos intactos; novas tabelas utilizáveis pela aplicação.

---

## Observação – Como obter um banco v13 para teste

Se não tiver uma instalação antiga:

1. Fazer backup do `backup_database.db` atual.
2. Abrir o backup com SQLite e executar: `PRAGMA user_version = 13;` (e salvar). Isso simula um banco “pré-v14”.
3. Remover manualmente as tabelas v14 se existirem (`server_credentials_table`, `connection_logs_table`, `server_connections_table`, `file_transfers_table`) e os índices v14.
4. Colocar esse arquivo como `backup_database.db` na pasta de Documentos e iniciar o app para testar o caminho de upgrade v13 → v14.

Ou usar um banco v13 exportado de outra máquina/versão antiga do app, se disponível.
