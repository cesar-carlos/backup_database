# Scripts de Manutenção do Banco de Dados

## migrate_database.dart

Script completo de migração que preserva todos os dados existentes.

### O que o script faz:

1. **Cria backup** do banco atual (`backup_database_backup.db`)
2. **Exporta dados** para JSON (`backup_export.json`)
3. **Remove banco antigo** com schema incorreto
4. **Cria novo banco** com schema correto (v24)
5. **Importa todos os dados** de volta
6. **Valida** que os dados foram importados corretamente

### Como usar:

```bash
# Execute o script
dart run scripts/migrate_database.dart
```

### O script irá:

✅ Preservar todos os dados:
- Configurações de SQL Server
- Configurações de Sybase
- Configurações de PostgreSQL
- Destinos de backup
- Agendamentos
- Vínculos Schedule-Destination
- Histórico de backups
- Logs de backup
- Configurações de email
- Destinatários de email
- Licenças

✅ Criar arquivos de segurança:
- `backup_database_backup.db` - Cópia do banco original
- `backup_export.json` - Dados em formato JSON

### Após a execução:

1. **Teste a aplicação** para garantir que tudo funciona
2. **Verifique os dados** nas telas de configuração
3. **Teste criar um agendamento** (o erro de trigger deve estar corrigido)
4. **Se tudo estiver OK**, você pode deletar os arquivos de backup:
   - `C:\Users\cesar\Documents\backup_database_backup.db`
   - `C:\Users\cesar\Documents\backup_export.json`

### Se algo der errado:

O script preserva o banco original como backup. Para restaurar:

```bash
# 1. Feche a aplicação
# 2. Navegue até a pasta de documentos
cd C:\Users\cesar\Documents

# 3. Delete o novo banco
del backup_database.db

# 4. Renomeie o backup
ren backup_database_backup.db backup_database.db

# 5. Inicie a aplicação novamente
```

### Logs do Script:

O script mostra o progresso em tempo real:
- 🔄 Processo em andamento
- ✅ Operação concluída
- ⚠️  Aviso (não crítico)
- ❌ Erro (operação falhou)

### Exemplo de saída esperada:

```
🔄 Iniciando migração do banco de dados...

📂 Banco atual: C:\Users\cesar\Documents\backup_database.db
💾 Backup será salvo em: C:\Users\cesar\Documents\backup_database_backup.db
📄 Export JSON em: C:\Users\cesar\Documents\backup_export.json

1️⃣  Criando backup do banco atual...
   ✅ Backup criado

2️⃣  Conectando ao banco existente...
3️⃣  Exportando dados...
   ✓ SQL Server configs: 2
   ✓ Sybase configs: 0
   ✓ PostgreSQL configs: 0
   ✓ Destinos: 1
   ✓ Agendamentos: 0
   ✅ Dados exportados

📊 Resumo dos dados exportados:
   • SQL Server configs: 2
   • Sybase configs: 0
   • PostgreSQL configs: 0
   • Destinos: 1
   • Agendamentos: 0
   • Histórico: 0

4️⃣  Fechando banco antigo...
   ✅ Banco fechado

5️⃣  Removendo banco antigo...
   ✅ Banco antigo removido

6️⃣  Criando novo banco com schema correto...
   ✅ Novo banco criado com schema v24

7️⃣  Importando dados...
   ✓ SQL Server configs: 2 importados
   ✓ Sybase configs: 0 importados
   ✓ PostgreSQL configs: 0 importados
   ✓ Destinos: 1 importados
   ✓ Email configs: 0 importados
   ✓ Email targets: 0 importados
   ✓ Licenças: 0 importadas
   ✓ Agendamentos: 0 importados
   ✓ Vínculos: 0 importados
   ✓ Histórico: 0 registros importados
   ✓ Logs: 0 registros importados
   ✅ Dados importados com sucesso

8️⃣  Validando dados...
   ✅ Dados validados

✅ MIGRAÇÃO CONCLUÍDA COM SUCESSO!

📌 Arquivos criados:
   • Backup: C:\Users\cesar\Documents\backup_database_backup.db
   • Export: C:\Users\cesar\Documents\backup_export.json

💡 Você pode deletar esses arquivos após confirmar que tudo funciona.
```

## check_database.dart

Script de diagnóstico que verifica o estado atual do banco sem fazer alterações.

### Como usar:

```bash
dart run scripts/check_database.dart
```

### O que verifica:

- Existência do banco de dados
- Versão do schema
- Todas as tabelas existentes
- Contagem de registros em cada tabela
- Triggers de validação
- Estrutura das tabelas

## Troubleshooting

### Erro: "Database is locked"

Se o script falhar com erro de "database is locked":

1. Feche completamente a aplicação
2. Verifique no Task Manager se não há processos do Flutter rodando
3. Execute o script novamente

### Erro: "permission denied"

Execute o terminal como administrador.

### Erro durante a importação

O script continua mesmo se alguns registros falharem na importação. Verifique os logs para ver quais registros tiveram problemas.

### Banco ficou vazio após migração

Isso não deveria acontecer, mas se acontecer:

1. Restaure o backup (veja instruções acima)
2. Execute novamente o script
3. Se persistir, abra uma issue com os logs completos

## Suporte

Em caso de problemas, forneça:
- Logs completos do script
- Conteúdo do arquivo `backup_export.json`
- Versão do Dart/Flutter (`dart --version`)
