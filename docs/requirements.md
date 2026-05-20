# Requisitos do Sistema - Backup Database

## Escopo

Este documento cobre os requisitos operacionais para instalar e executar o
Backup Database no Windows. Para o passo a passo de instalacao, consulte
[`install/installation_guide.md`](install/installation_guide.md).

## Sistema operacional

- Windows 8 ou superior
- Windows Server 2012 ou superior
- Arquitetura x64
- Permissoes de administrador para instalar, atualizar e configurar o PATH do
  sistema

Observacao: alguns recursos dependem da versao do Windows detectada em runtime.
Exemplos: auto update, OAuth em browser externo e integracoes visuais nativas
do Windows.

## Dependencias obrigatorias do aplicativo

- Visual C++ Redistributable 2015-2022 (x64)
  O instalador tenta instalar automaticamente quando necessario.

## Dependencias por tipo de banco

### SQL Server

- `sqlcmd` disponivel no PATH do Windows
- Credenciais com permissao para o tipo de backup configurado

### Sybase SQL Anywhere

- `dbisql` e `dbbackup` disponiveis no PATH do Windows
- `dbvalid` e `dbverify` sao recomendados para verificacao e diagnostico

### PostgreSQL

- `psql` e `pg_basebackup` disponiveis no PATH do Windows
- `pg_verifybackup` e recomendado quando o fluxo usa verificacao de backup
- Para backup de WAL/log, o ambiente pode exigir configuracao adicional de
  replicacao e slots, conforme o fluxo descrito em
  `docs/analise_implementacao_postgresql.md`

### Firebird

- `gbak`, `nbackup`, `gstat` e `isql` disponiveis no PATH do Windows
- Firebird 2.5, 3.0 e 4.0 sao suportados no produto atual
- Para cenarios remotos ou com criptografia/WireCrypt, valide tambem a
  compatibilidade entre cliente CLI e servidor

## Modos de instalacao

O instalador oferece dois modos:

- `server`: executa a aplicacao como servidor principal e habilita fluxos de
  conexao remota entre cliente e servidor
- `client`: usa um servidor remoto ja existente para administrar backups

## Verificacao rapida

Depois da instalacao, use o atalho `Verificar Dependencias` no menu Iniciar ou
rode manualmente:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\Backup Database\tools\check_dependencies.ps1"
```

Tambem e valido testar cada familia de ferramenta diretamente:

```powershell
sqlcmd -?
dbisql -?
dbbackup -?
psql --version
pg_basebackup --version
pg_verifybackup --version
gbak -?
nbackup -?
gstat -?
isql -?
```

## Referencias

- [`path_setup.md`](path_setup.md)
- [`install/installation_guide.md`](install/installation_guide.md)
- [`analise_implementacao_postgresql.md`](analise_implementacao_postgresql.md)
- [`analise_implementacao_sybase.md`](analise_implementacao_sybase.md)
