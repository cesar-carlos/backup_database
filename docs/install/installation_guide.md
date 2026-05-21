# Guia de Instalacao - Backup Database

Este guia cobre a instalacao da aplicacao no Windows e a configuracao inicial
minima para colocar backups em funcionamento.

## Antes de instalar

Voce precisa de:

1. Windows 8 ou superior, ou Windows Server 2012 ou superior
2. Arquitetura x64
3. Permissao de administrador
4. Conexao com a internet para baixar dependencias, quando necessario

Para detalhes de requisitos e ferramentas por banco, consulte
`requirements.md`.

## Passo 1: baixar o instalador

Baixe `BackupDatabase-Setup-{versao}.exe` na pagina de releases do projeto:
<https://github.com/cesar-carlos/backup_database/releases>

## Passo 2: executar o instalador

1. Clique com o botao direito no arquivo `.exe`.
2. Escolha `Executar como administrador`.
3. Confirme o UAC quando solicitado.

## Passo 3: escolher o modo de instalacao

O instalador oferece dois modos:

- `Server Mode`
  Use quando esta maquina sera o ponto principal de execucao dos backups e pode
  aceitar clientes remotos.
- `Client Mode`
  Use quando esta maquina apenas vai conectar a um servidor remoto ja
  configurado.

Se voce vai operar localmente e quer a instalacao padrao, use `Server Mode`.

## Passo 4: revisar as opcoes do assistente

Durante a instalacao, revise principalmente:

- pasta de instalacao
- icone na area de trabalho
- inicializacao com o Windows
- instalacao automatica do Visual C++ Redistributable

Observacao: o instalador nao instala ferramentas especificas de bancos como
`sqlcmd`, `pg_basebackup`, `dbbackup` ou `gbak`. Essas dependencias devem ser
instaladas no sistema conforme os bancos usados.

## Passo 5: concluir e abrir o aplicativo

Ao final:

1. marque a opcao para abrir o app, se desejar
2. finalize o assistente
3. abra `Backup Database` pelo menu Iniciar se nao tiver iniciado automaticamente

## Icone antigo no atalho ou na barra de tarefas

Se, apos atualizar o app, o atalho ou a barra ainda mostrarem o icone antigo:

1. remova o atalho da area de trabalho e crie outro pelo menu Iniciar, ou
2. reinstale com o instalador mais recente, ou
3. reinicie o Explorer (`taskkill /f /im explorer.exe` e `start explorer`) ou execute `ie4uinit.exe -show` em um prompt elevado.

O Windows mantem cache de icones por caminho do executavel; isso e normal apos trocar a arte do `.exe`.

## Configuracao inicial recomendada

### 1. Verificar dependencias

Use o atalho `Verificar Dependencias` no menu Iniciar. Ele ajuda a validar se o
Windows encontra as ferramentas externas necessarias.

### 2. Configurar PATH, se necessario

Se alguma ferramenta estiver ausente, siga `path_setup.md`.

Resumo por banco:

- SQL Server: `sqlcmd`
- Sybase SQL Anywhere: `dbisql`, `dbbackup`
- PostgreSQL: `psql`, `pg_basebackup`, `pg_verifybackup`
- Firebird: `gbak`, `nbackup`, `gstat`, `isql`

### 3. Configurar o banco de dados no app

Depois da instalacao:

1. abra a secao de configuracoes do banco desejado
2. crie a conexao
3. teste a conexao
4. salve

### 4. Configurar destinos de backup

O produto suporta, entre outros:

- pasta local
- FTP/FTPS
- Google Drive
- Dropbox
- Nextcloud/WebDAV

### 5. Criar um agendamento

Depois de validar banco e destino:

1. abra `Agendamentos`
2. crie um novo agendamento
3. escolha o tipo de banco
4. associe a configuracao salva
5. defina recorrencia e destinos

## Instalacao como servico do Windows

No modo servidor, o instalador adiciona atalhos para instalar e remover o
servico do Windows.

Fluxo recomendado:

1. instale a aplicacao
2. configure bancos, destinos e agendamentos
3. execute o atalho `Instalar como Servico do Windows`
4. valide os logs em `C:\ProgramData\BackupDatabase\logs\`

Se preferir o fluxo manual com NSSM, use o `README.md` da raiz do repositorio
como referencia complementar.

## Auto update

O produto suporta atualizacao automatica quando `AUTO_UPDATE_FEED_URL` estiver
configurada no ambiente da maquina. Para detalhes operacionais:

- `auto_update_setup.md`
- `testing_auto_update.md`
- `release_guide.md`

## Problemas comuns

### O app nao encontra uma ferramenta CLI

Use `Verificar Dependencias` e configure o PATH com base em `path_setup.md`.

### O aplicativo instala, mas alguns recursos nao aparecem

Alguns recursos dependem da versao do Windows, do modo de instalacao
(`server`/`client`) e das ferramentas externas disponiveis.

### O antivirus bloqueia testes de conexao ou uploads

Adicione excecao para a pasta de instalacao e, se necessario, para
`backup_database.exe`.

### O aplicativo nao inicia apos instalar

Verifique:

- Visual C++ Redistributable
- logs em `C:\ProgramData\BackupDatabase\logs\`
- arquivo `.env` em `C:\ProgramData\BackupDatabase\config\`

## Proximos documentos

- `requirements.md`
- `path_setup.md`
- `../email/guia_funcionamento_notificacoes_email_smtp_oauth.md`
