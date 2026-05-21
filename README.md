# Backup Database

[![codecov](https://codecov.io/gh/cesar-carlos/backup_database/graph/badge.svg)](https://codecov.io/gh/cesar-carlos/backup_database)

Sistema de backup automatico para Windows com suporte a SQL Server, Sybase SQL
Anywhere, PostgreSQL e Firebird.

## Visao geral

O produto cobre:

- execucao local ou remota em modo `server` e `client`
- backups agendados com compressao, verificacao e retencao
- destinos locais e remotos
- notificacoes por e-mail
- instalacao opcional como servico do Windows

## Bancos suportados

- SQL Server via `sqlcmd`
- Sybase SQL Anywhere via `dbisql` e `dbbackup`
- PostgreSQL via `psql`, `pg_basebackup`, `pg_verifybackup`, `pg_dump` e `pg_restore`
- Firebird via `gbak`, `nbackup`, `gstat` e `isql`

Observacao: o suporte por banco nao depende apenas da UI; o codigo atual inclui
camadas de configuracao, repositorio, estrategia e execucao para os quatro
SGBDs.

## Destinos suportados

- pasta local
- FTP/FTPS
- Google Drive
- Dropbox
- Nextcloud/WebDAV

## Requisitos do sistema

- Windows 8 ou superior
- Windows Server 2012 ou superior
- arquitetura x64
- permissao de administrador para instalacao e configuracao do ambiente
- Visual C++ Redistributable 2015-2022 (x64), instalado automaticamente quando necessario

Dependencias por banco:

- SQL Server: `sqlcmd` no PATH
- Sybase SQL Anywhere: `dbisql` e `dbbackup` no PATH; `dbvalid` e `dbverify`
  sao recomendados
- PostgreSQL: `psql` e `pg_basebackup` no PATH; `pg_verifybackup` e
  recomendado para fluxos com verificacao
- Firebird: `gbak`, `nbackup`, `gstat` e `isql` no PATH

Alguns recursos dependem tambem da versao do Windows detectada em runtime,
como auto update, OAuth externo e integracoes visuais nativas.

## Instalacao

Baixe o instalador na pagina de releases:

- [Releases](https://github.com/cesar-carlos/backup_database/releases)

O instalador oferece dois modos:

- `Server Mode`: esta maquina executa backups e pode aceitar clientes remotos
- `Client Mode`: esta maquina conecta a um servidor remoto existente

Guias relacionados:

- [Guia de instalacao](docs/install/installation_guide.md)
- [Requisitos](docs/requirements.md)
- [Configuracao do PATH](docs/path_setup.md)

## Configuracao

### Ambiente de desenvolvimento

Para rodar o projeto com `flutter run`, use o `.env` na raiz do repositorio e
o `.env.example` como base.

Arquivos auxiliares:

- `.env`
- `.env.example`
- `.env.server`
- `.env.client`

Exemplos de variaveis uteis em desenvolvimento:

```env
SINGLE_INSTANCE_ENABLED=true
SINGLE_INSTANCE_LOCK_FALLBACK_MODE=fail_safe
UI_SCHEDULER_FALLBACK_MODE=fail_open
DEBUG_APP_MODE=server
FTP_IT_HOST=
FTP_IT_PORT=21
FTP_IT_USER=
FTP_IT_PASS=
FTP_IT_REMOTE_PATH=
```

### Maquina instalada

Na instalacao Windows, a configuracao ativa fica em:

```text
C:\ProgramData\BackupDatabase\config\.env
```

Esse arquivo tem precedencia sobre o `.env` empacotado no aplicativo.

Para auto update, a variavel principal e:

```env
AUTO_UPDATE_FEED_URL=https://raw.githubusercontent.com/cesar-carlos/backup_database/main/appcast.xml
```

Guias relacionados:

- [Auto update](docs/install/auto_update_setup.md)
- [Teste do auto update](docs/install/testing_auto_update.md)
- [Notificacoes por e-mail](docs/email/guia_funcionamento_notificacoes_email_smtp_oauth.md)

## Uso rapido

Fluxo minimo:

1. instalar a aplicacao
2. verificar dependencias externas
3. configurar uma conexao de banco
4. configurar um destino
5. criar um agendamento
6. executar um backup manual antes de confiar no agendamento

Para validar o ambiente apos a instalacao, use o atalho `Verificar
Dependencias` no menu Iniciar ou rode:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\Backup Database\tools\check_dependencies.ps1"
```

## Linha de comando

```bash
backup_database.exe --schedule-id=<schedule_id>
backup_database.exe --minimized
backup_database.exe --mode=server
backup_database.exe --mode=client
```

## Windows Service

O produto pode rodar como servico do Windows.

Fluxo recomendado:

1. instale o aplicativo
2. configure bancos, destinos e agendamentos
3. use o atalho `Instalar como Servico do Windows` criado pelo instalador
4. valide os logs em `C:\ProgramData\BackupDatabase\logs\`

Se precisar do fluxo manual, use como referencia os scripts em `installer/`,
principalmente `installer/install_service.ps1`. Ele configura parametros e
variaveis que nao aparecem em um `nssm install` minimo.

Observacoes importantes:

- o servico e configurado para `LocalSystem` por padrao
- nesta rodada, auto update silencioso em modo servico so e suportado para
  servicos em `LocalSystem`
- se voce trocar a conta do servico, o produto continua podendo operar, mas o
  auto update silencioso passa a exigir acao manual

## Estrutura de dados em ProgramData

```text
C:\ProgramData\BackupDatabase\
  config\
    .env
  logs\
  staging\
    updates\
  database.db
```

## Documentacao

- [Indice da pasta docs](docs/README.md)
- [ADRs](docs/adr/README.md)
- [Visao geral da arquitetura](docs/onboarding/architecture_overview.md)
- [Adicionar um novo SGBD](docs/onboarding/adicionar_sgbd.md)
- [Design system](docs/onboarding/design_system.md)

## Testes

Unitarios:

```bash
flutter test test/unit/ --reporter compact
```

Cobertura:

```bash
flutter test --coverage
python scripts/coverage.py
python scripts/coverage.py --fail-under 70
```

Integracao local:

```bash
python test/scripts/run_integration_tests.py
python test/scripts/run_ftp_integration_tests.py
```

No GitHub Actions:

- `Test` executa analise estatica e testes unitarios
- `Integration Tests (Self-Hosted)` cobre cenarios de integracao manual/workflow

## Build

Recomendado (sincroniza icones do exe/bandeja, versao e instalador):

```bash
python installer/build_installer.py
```

Manual:

```bash
dart run flutter_launcher_icons
flutter build windows --release
python installer/build_installer.py
```

Artefatos principais:

- `build/windows/x64/runner/Release/backup_database.exe`
- `installer/dist/BackupDatabase-Setup-<versao>.exe`
- `installer/dist/BackupDatabase-Setup-<versao>.exe.sha256`

Para publicar uma release:

- [Guia de release](docs/install/release_guide.md)

## Arquitetura

O projeto segue Clean Architecture com organizacao por camada.

Camadas principais:

- `domain`
- `application`
- `infrastructure`
- `presentation`
- `core`

Referencias:

- [ADR-004: ports genericos por SGBD](docs/adr/004-generic-hexagonal-ports-sgbds.md)
- [ADR-005: organizacao layer-first](docs/adr/005-layer-first-code-organization.md)

## Suporte

- [Issues](https://github.com/cesar-carlos/backup_database/issues)

## Licenca

Licenca MIT. Veja [LICENSE](LICENSE).
