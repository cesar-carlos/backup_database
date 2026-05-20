# Configuracao do PATH no Windows

Este guia explica como adicionar ao PATH as ferramentas externas usadas pelo
Backup Database. Sem isso, a aplicacao nao consegue localizar CLIs como
`sqlcmd`, `pg_basebackup`, `dbbackup` ou `gbak`.

## Quando voce precisa deste guia

Consulte este documento quando:

- o app informar que uma ferramenta nao foi encontrada no PATH
- o teste de conexao falhar por ausencia de executavel
- o script `check_dependencies.ps1` apontar ferramenta ausente

## Como editar o PATH

### Metodo 1: interface grafica

1. Abra `Sistema`.
2. Entre em `Configuracoes avancadas do sistema`.
3. Na aba `Avancado`, clique em `Variaveis de Ambiente`.
4. Em `Variaveis do sistema`, edite `Path`.
5. Adicione a pasta da ferramenta, nao o executavel individual.
6. Confirme as janelas e reabra o terminal ou o aplicativo.

### Metodo 2: PowerShell (administrador)

```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") +
        ";C:\Caminho\Da\Ferramenta",
    "Machine"
)
```

### Metodo 3: CMD (administrador)

```cmd
setx /M PATH "%PATH%;C:\Caminho\Da\Ferramenta"
```

## Caminhos comuns por banco

### SQL Server

Ferramenta minima: `sqlcmd`

Caminhos comuns:

```text
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn
C:\Program Files\Microsoft SQL Server Client SDK\ODBC\170\Tools\Binn
```

### Sybase SQL Anywhere

Ferramentas principais: `dbisql`, `dbbackup`

Caminhos comuns:

```text
C:\Program Files\SAP\SQL Anywhere 17\Bin64
C:\Program Files\SAP\SQL Anywhere 16\Bin64
C:\Program Files\SQL Anywhere 12\Bin64
C:\Program Files\SQL Anywhere 11\Bin64
```

### PostgreSQL

Ferramentas principais: `psql`, `pg_basebackup`, `pg_verifybackup`

Caminhos comuns:

```text
C:\Program Files\PostgreSQL\16\bin
C:\Program Files\PostgreSQL\15\bin
C:\Program Files\PostgreSQL\14\bin
```

### Firebird

Ferramentas principais: `gbak`, `nbackup`, `gstat`, `isql`

Caminhos comuns:

```text
C:\Program Files\Firebird\Firebird_5_0
C:\Program Files\Firebird\Firebird_4_0
C:\Program Files\Firebird\Firebird_3_0
C:\Program Files\Firebird\Firebird_2_5\bin
```

Observacao: em algumas instalacoes o executavel fica na raiz da pasta do
produto; em outras, dentro de `bin`. Adicione exatamente a pasta onde os
executaveis estao.

## Como localizar a pasta certa

1. Abra o Explorador de Arquivos.
2. Procure pelo executavel que o app esta reclamando, por exemplo
   `pg_basebackup.exe` ou `gbak.exe`.
3. Copie o caminho da pasta que contem esse arquivo.
4. Adicione essa pasta ao PATH.

## Verificacao apos a mudanca

Feche e reabra o terminal. Em seguida rode o comando correspondente:

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

Se o comando responder com ajuda ou versao, o PATH esta correto.

## Problemas comuns

### O terminal ainda nao reconhece a ferramenta

- Reabra o terminal por completo.
- Reabra o Backup Database.
- Confirme que voce adicionou a pasta, nao o arquivo `.exe`.
- Verifique se o executavel realmente existe naquele diretorio.

### Acesso negado ao editar o PATH

- Rode PowerShell ou CMD como administrador.
- Ou use a interface grafica com uma conta que tenha privilegios.

### Mais de uma versao instalada

- Prefira manter no PATH a versao que corresponde ao ambiente em uso.
- Se necessario, teste o executavel pelo caminho completo antes de alterar o
  PATH global.

## Variaveis de ambiente do aplicativo

O PATH resolve a descoberta das ferramentas CLI. Alem disso, o aplicativo le
variaveis opcionais do proprio processo ou do arquivo `.env`.

Exemplos:

- `BACKUP_DATABASE_MAX_PARALLEL_UPLOADS`
- `BACKUP_DATABASE_PG_LOG_USE_SLOT`
- `BACKUP_DATABASE_PG_LOG_TIMEOUT_SECONDS`
- `AUTO_UPDATE_FEED_URL`

Para detalhes de comportamento PostgreSQL, consulte
[`analise_implementacao_postgresql.md`](analise_implementacao_postgresql.md).

## Referencias rapidas

- [`requirements.md`](requirements.md)
- [`install/installation_guide.md`](install/installation_guide.md)
- [`analise_implementacao_postgresql.md`](analise_implementacao_postgresql.md)
- [`analise_implementacao_sybase.md`](analise_implementacao_sybase.md)
