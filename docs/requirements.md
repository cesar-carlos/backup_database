# Requisitos do Sistema

Este documento lista todos os requisitos necessários para executar o **Backup Database**.

## Requisitos Mínimos

### Sistema Operacional

- **Windows 10** (64 bits) ou superior
- **Windows Server 2012 R2** (64 bits) ou superior
- **Arquitetura**: Apenas 64 bits (x64)

### Espaço em Disco

- **Mínimo**: 500 MB para instalação
- **Recomendado**: 2 GB para backups e logs

### Memória RAM

- **Mínimo**: 2 GB
- **Recomendado**: 4 GB ou mais

### Permissões

- **Administrador**: Necessário para instalação
- **Acesso ao sistema de arquivos**: Para criar backups
- **Acesso à rede**: Para FTP e Google Drive (se configurado)

---

## Dependências Obrigatórias

### 1. Visual C++ Redistributables

**O que é**: Bibliotecas necessárias para executar aplicativos Flutter no Windows.

**Versão**: Visual C++ Redistributables 2015-2022 (x64)

**Download**:

- Link direto: https://aka.ms/vs/17/release/vc_redist.x64.exe
- Ou baixe do site oficial da Microsoft

**Instalação**:

- O instalador do Backup Database tenta instalar automaticamente
- Se falhar, instale manualmente antes de executar o aplicativo

**Como verificar**:

1. Abra o **Painel de Controle** > **Programas e Recursos**
2. Procure por "Microsoft Visual C++ 2015-2022 Redistributable (x64)"
3. Se não encontrar, instale manualmente

---

## Dependências para Funcionalidades Específicas

### 2. SQL Server Command Line Tools (sqlcmd)

**O que é**: Ferramenta de linha de comando para executar backups do SQL Server.

**Quando é necessário**: Quando você precisa fazer backup de bancos SQL Server.

**Como obter**:

#### Opção 1: SQL Server já instalado

Se você já tem o SQL Server instalado, o `sqlcmd.exe` geralmente já está disponível no PATH.

**Caminhos comuns**:

- SQL Server 2019/2022: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn`
- SQL Server 2017: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn`
- SQL Server 2014: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\120\Tools\Binn`
- SQL Server 2012: `C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\110\Tools\Binn`

#### Opção 2: Instalar apenas as ferramentas

1. Baixe o **SQL Server Command Line Utilities**:
   - SQL Server 2019: https://go.microsoft.com/fwlink/?linkid=2230791
   - SQL Server 2017: https://go.microsoft.com/fwlink/?linkid=853016
2. Execute o instalador
3. Adicione o caminho de instalação ao PATH do sistema (veja [path_setup.md](path_setup.md))

**Como verificar**:

1. Abra o **Prompt de Comando** ou **PowerShell**
2. Execute: `sqlcmd -?`
3. Se aparecer a ajuda do comando, está instalado corretamente

---

### 3. Sybase SQL Anywhere

**O que é**: Ferramentas necessárias para executar backups do Sybase SQL Anywhere (ASA).

**Quando é necessário**: Quando você precisa fazer backup de bancos Sybase ASA.

**Ferramentas necessárias**:

- `dbbackup.exe` - Para executar backups
- `dbisql.exe` - Para testar conexões

**Versões suportadas**:

- Sybase SQL Anywhere 11, 12, 16, 17 (64 bits)

**Como obter**:

1. Instale o **Sybase SQL Anywhere** no servidor
2. Localize a pasta `Bin64` na instalação
3. Adicione o caminho ao PATH do sistema (veja [path_setup.md](path_setup.md))

**Caminhos comuns**:

- Versão 16: `C:\Program Files\SQL Anywhere 16\Bin64`
- Versão 17: `C:\Program Files\SQL Anywhere 17\Bin64`
- Versão 12: `C:\Program Files\SQL Anywhere 12\Bin64`
- Versão 11: `C:\Program Files\SQL Anywhere 11\Bin64`

**Como verificar**:

1. Abra o **Prompt de Comando** ou **PowerShell**
2. Execute: `dbbackup -?`
3. Se aparecer a ajuda do comando, está instalado corretamente

**Nota**: Você precisa ter uma licença válida do Sybase SQL Anywhere.

---

## Dependências Opcionais

### 4. .NET Framework

**O que é**: Algumas funcionalidades podem requerer .NET Framework.

**Versão**: .NET Framework 4.7.2 ou superior (geralmente já instalado no Windows 10/Server)

**Como verificar**:

1. Abra o **Painel de Controle** > **Programas e Recursos**
2. Procure por "Microsoft .NET Framework"
3. Se não encontrar, baixe do site da Microsoft

---

## Resumo de Verificação

### Checklist de Instalação

Antes de usar o Backup Database, verifique:

- [ ] Windows 10/Server 64 bits instalado
- [ ] Visual C++ Redistributables 2015-2022 (x64) instalado
- [ ] SQL Server Command Line Tools (sqlcmd) instalado e no PATH (se usar SQL Server)
- [ ] Sybase SQL Anywhere instalado e no PATH (se usar Sybase)
- [ ] Permissões de administrador para instalação
- [ ] Espaço em disco suficiente (mínimo 500 MB)

### Verificação Rápida via Linha de Comando

Abra o **Prompt de Comando** ou **PowerShell** e execute:

```cmd
REM Verificar Visual C++ Redistributables
reg query "HKLM\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" /v Version

REM Verificar sqlcmd (SQL Server)
sqlcmd -?

REM Verificar dbbackup (Sybase)
dbbackup -?
```

Se todos os comandos retornarem sem erro, as dependências estão instaladas corretamente.

---

## Problemas Comuns

### "O aplicativo não inicia"

**Possíveis causas**:

1. Visual C++ Redistributables não instalado
2. Arquivos corrompidos na instalação

**Solução**:

1. Instale o Visual C++ Redistributables manualmente
2. Reinstale o Backup Database

### "sqlcmd não é reconhecido como comando"

**Solução**:

1. Instale o SQL Server Command Line Tools
2. Adicione o caminho ao PATH do sistema
3. Reinicie o computador ou o aplicativo

### "dbbackup não é reconhecido como comando"

**Solução**:

1. Verifique se o Sybase SQL Anywhere está instalado
2. Localize a pasta `Bin64` na instalação
3. Adicione o caminho ao PATH do sistema
4. Reinicie o computador ou o aplicativo

### "Erro ao executar backup"

**Possíveis causas**:

1. Ferramentas não encontradas no PATH
2. Permissões insuficientes
3. Banco de dados não acessível

**Solução**:

1. Verifique se as ferramentas estão no PATH (veja [path_setup.md](path_setup.md))
2. Execute o aplicativo como administrador
3. Verifique as configurações de conexão do banco de dados

---

## Suporte

Se você encontrar problemas que não estão listados aqui:

1. Consulte os logs do aplicativo em: `C:\ProgramData\BackupDatabase\logs\`
2. Verifique a documentação completa em: `{app}\docs\`
3. Abra uma issue no repositório do projeto

---

**Última atualização**: Versão 1.0.0
