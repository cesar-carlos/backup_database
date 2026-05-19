# Guia de Teste do Auto Update

## Pre-requisitos

1. Configurar o feed em:

```text
C:\ProgramData\BackupDatabase\config\.env
```

2. Garantir a variavel:

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
```

3. Ter uma release publicada no GitHub com um unico instalador `.exe`
4. Ter o sidecar correspondente `.exe.sha256` anexado na release

## Teste manual na UI

1. Execute uma versao antiga do app.
2. Abra `Configuracoes > Atualizacoes`.
3. Verifique:
   - status do updater
   - feed configurado
   - ultima verificacao
   - ultima falha, se houver
4. Clique em `Verificar atualizacoes`.

Se houver release mais nova:

- o app baixa o instalador
- valida `length` e `sha256`
- executa o instalador silencioso
- encerra o processo atual
- reabre a UI com os argumentos originais do processo atualizado

## Teste no Windows Service

1. Instale o app como servico.
2. Confirme que a conta do servico e `LocalSystem`.
3. Confirme que o arquivo de configuracao da maquina existe em `ProgramData`.
4. Publique uma release nova.
5. Aguarde a verificacao inicial ou periodica.
6. Verifique logs em:

```text
C:\ProgramData\BackupDatabase\logs\
```

O comportamento esperado e o mesmo da UI: download, validacao, instalacao silenciosa e troca de versao.
Depois da troca, o servico deve continuar instalado e voltar a rodar sem abrir UI.
Se o servico estiver configurado com conta customizada, o auto update silencioso deve ser bloqueado com mensagem operacional explicita e sem alterar o servico existente.

## Smoke E2E recomendado

1. Instale a versao N em uma VM Windows limpa.
2. Na UI:
   - execute um update para N+1
   - confirme que a UI fecha e reabre sozinha
   - confirme que `C:\ProgramData\BackupDatabase\staging\updates\update_context.json` foi consumido
3. No modo servico:
   - instale o servico via `tools\install_service.ps1`
   - confirme que a conta do servico e `LocalSystem`
   - confirme `nssm status BackupDatabaseService`
   - publique N+1 e aguarde o auto update
   - confirme que o servico segue registrado e volta para `RUNNING`
4. Cenário negativo:
   - reconfigure o servico com conta customizada
   - force uma nova verificacao
   - confirme que o updater bloqueia o handoff silencioso com mensagem previsivel
5. Em ambos os cenarios, valide:
   - `C:\ProgramData\BackupDatabase\staging\updates\auto_update_history.jsonl`
   - preservacao de `C:\ProgramData\BackupDatabase\config\.env`
   - ausencia de `auto_update.lock` orfao

## Validacoes do feed

Confira o `appcast.xml` publicado e valide:

- `sparkle:version`
- `sparkle:os="windows"`
- `length`
- `sha256`
- URL do instalador apontando para `BackupDatabase-Setup-<versao>.exe`

## Problemas comuns

### `AUTO_UPDATE_FEED_URL` ausente

- Edite `C:\ProgramData\BackupDatabase\config\.env`
- Reinicie a UI ou o servico

### `appcast.xml` sem hash

- Anexe o sidecar `.exe.sha256` na release correspondente
- Reexecute o workflow `update-appcast`

### Rollback de release ruim

- Adicione a versao em `scripts/appcast_policy.json`
- Faça push na `main` ou execute manualmente o workflow `update-appcast`
- Confirme que o `appcast.xml` publicado nao lista mais a versao bloqueada

### Nenhuma atualizacao detectada

- Confirme que a release nao e draft nem prerelease
- Confirme que a versao da release e maior que a instalada
- Confirme que existe exatamente um instalador `.exe`
