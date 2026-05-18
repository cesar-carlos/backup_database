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

## Teste no Windows Service

1. Instale o app como servico.
2. Confirme que o arquivo de configuracao da maquina existe em `ProgramData`.
3. Publique uma release nova.
4. Aguarde a verificacao inicial ou periodica.
5. Verifique logs em:

```text
C:\ProgramData\BackupDatabase\logs\
```

O comportamento esperado e o mesmo da UI: download, validacao, instalacao silenciosa e troca de versao.

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

- Reexecute `python scripts/sync_appcast_from_releases.py`
- Publique novamente o resultado do workflow se necessario

### Nenhuma atualizacao detectada

- Confirme que a release nao e draft nem prerelease
- Confirme que a versao da release e maior que a instalada
- Confirme que existe exatamente um instalador `.exe`
