# Configuracao de Atualizacao Automatica

Este documento descreve o fluxo atual de auto update no Windows.

## Resumo

O aplicativo nao usa mais `auto_updater`/WinSparkle para decidir ou instalar atualizacoes.

O runtime faz este pipeline:

1. Le `AUTO_UPDATE_FEED_URL`
2. Baixa e parseia `appcast.xml`
3. Seleciona a release Windows mais nova
4. Compara com a versao atual
5. Baixa o instalador `BackupDatabase-Setup-<versao>.exe`
6. Valida `length` e `sha256`
7. Executa o instalador com:

```text
/VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

## Configuracao da maquina

Em instalacoes Windows, a configuracao ativa fica em:

```text
C:\ProgramData\BackupDatabase\config\.env
```

Esse arquivo tem precedencia sobre o asset `.env` empacotado no app.

O asset `.env` continua existindo apenas como fallback para desenvolvimento local com `flutter run`.

## Variavel obrigatoria

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
```

## Formato do feed

Cada item do `appcast.xml` precisa ter:

- `sparkle:version`
- `sparkle:os="windows"`
- `url`
- `length`
- `sha256`

Exemplo:

```xml
<item>
  <title>Version 3.0.1</title>
  <pubDate>Sun, 19 Apr 2026 17:07:49 +0000</pubDate>
  <description>Automatic update via GitHub Release.</description>
  <enclosure
    url="https://github.com/cesar-carlos/backup_database/releases/download/v3.0.1/BackupDatabase-Setup-3.0.1.exe"
    sparkle:version="3.0.1"
    sparkle:os="windows"
    length="39020908"
    type="application/octet-stream"
    sha256="..."
  />
</item>
```

## Release e appcast

O feed nao e mais editado inline no workflow.

O fluxo oficial agora e:

1. Publicar a release no GitHub com o instalador `.exe`
2. O workflow `.github/workflows/update-appcast.yml` executa
3. O script `scripts/sync_appcast_from_releases.py` reconstrui o `appcast.xml` do zero
4. O script deduplica versoes, ordena por `published_at` e calcula `sha256`
5. O workflow faz commit do `appcast.xml` atualizado na `main`

## Observacoes

- O updater e Windows-only.
- UI e Windows Service usam o mesmo pipeline.
- A instalacao e forcada e silenciosa.
- Alterar `.env` dentro da pasta `{app}` nao muda o runtime da maquina instalada.
