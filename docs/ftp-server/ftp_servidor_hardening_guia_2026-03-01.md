# Guia de Hardening do Servidor FTP para Backup

Data: 2026-03-01  
Objetivo: Reduzir incidentes por configuração incorreta do servidor FTP.

## Requisitos Mínimos para Retomada de Upload

Para que o backup use retomada de upload (REST + SIZE + STOR):

- Servidor deve reportar `REST STREAM` no comando `FEAT`.
- Comando `SIZE` deve retornar tamanho do arquivo (não -1).
- Comandos `RNFR`/`RNTO` devem permitir renomear arquivos no diretório de destino.

## IIS FTP (Windows)

### Configuração para Retomada

1. **keepPartialUploads**  
   Permite que arquivos `.part` permaneçam no servidor após interrupção.  
   - `applicationHost.config` ou PowerShell:
   ```powershell
   Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/siteDefaults/ftpServer" -Name "keepPartialUploads" -Value "True" -PSPath "IIS:\"
   ```

2. **allowReplaceOnRename**  
   Permite que RNFR/RNTO sobrescreva arquivo existente (útil para promover `.part` para nome final).  
   - Verificar se o servidor aceita rename quando o destino já existe (comportamento varia).

3. **Modo passivo**  
   Recomendado para clientes atrás de firewall/NAT.  
   - Configurar intervalo de portas passivas no firewall.
   - Liberar portas no firewall (ex.: 50000-50100).

### Portas

- Controle: 21 (FTP) ou 990 (FTPS).
- Dados (passivo): intervalo configurado no IIS (ex.: 50000-50100).

### Permissões

- Usuário FTP deve ter permissão de escrita no diretório remoto.
- Usuário deve poder criar, renomear e excluir arquivos.

## Teste de Conexão

O aplicativo executa validação automática ao testar a conexão:

- Conectividade e autenticação
- Permissão de escrita (upload de arquivo de teste)
- Suporte a rename (RNFR/RNTO)
- Suporte a REST STREAM (retomada)

Se algum item falhar, avisos são exibidos na mensagem de sucesso do teste.

## Verificação de Integridade antes do Restore

Após baixar um backup do FTP, valide a integridade antes de restaurar:

1. Baixe o arquivo de backup e o sidecar `.sha256` (ex.: `backup.db` e `backup.db.sha256`).
2. Execute o utilitário de verificação na raiz do projeto:

   ```powershell
   dart run bin/verify_sha256.dart C:\Downloads\backup_2026-03-01.db
   ```

3. Se a saída for `OK - Integridade verificada`, o arquivo está íntegro e pode ser restaurado.
4. Se houver erro, não restaure — o arquivo pode estar corrompido. Baixe novamente.

O sidecar `.sha256` é gerado automaticamente pelo backup ao enviar para FTP.

## Troubleshooting

| Sintoma | Possível causa | Ação |
|---------|----------------|------|
| "Sem permissão de escrita" | Diretório somente leitura ou usuário sem permissão | Ajustar permissões NTFS/IIS |
| "Renomear arquivos não permitido" | RNFR/RNTO bloqueado ou `allowReplaceOnRename` desabilitado | Revisar configuração do servidor |
| "Não suporta retomada" | FEAT não reporta REST STREAM | Usar servidor compatível ou aceitar fallback (upload completo) |
| Timeout na conexão | Firewall bloqueando porta de controle ou dados | Liberar portas e modo passivo |
