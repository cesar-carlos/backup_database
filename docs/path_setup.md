# Configuração do PATH do Sistema

Este documento explica quais diretórios você precisa adicionar ao PATH do Windows para que o sistema de backup encontre as ferramentas necessárias.

## 🔧 Ferramentas Necessárias

O sistema de backup precisa das seguintes ferramentas disponíveis no PATH:

### 1. **Sybase SQL Anywhere**
- `dbbackup.exe` - Para executar backups
- `dbisql.exe` - Para testar conexões

### 2. **SQL Server**
- `sqlcmd.exe` - Para executar backups e testar conexões

### 3. **PostgreSQL**
- `psql.exe` - Para testar conexões e executar scripts SQL
- `pg_basebackup.exe` - Para executar backups físicos completos
- `pg_verifybackup.exe` - Para verificar integridade dos backups

---

## 📍 Caminhos Padrão de Instalação

### Sybase SQL Anywhere

Os caminhos padrão de instalação variam conforme a versão:

#### Versão 16 (64-bit)
```
C:\Program Files\SQL Anywhere 16\Bin64
```

#### Versão 17 (64-bit)
```
C:\Program Files\SQL Anywhere 17\Bin64
```

#### Versão 12 (64-bit)
```
C:\Program Files\SQL Anywhere 12\Bin64
```

#### Versão 11 (64-bit)
```
C:\Program Files\SQL Anywhere 11\Bin64
```

**Nota**: Se você instalou em um caminho diferente, localize a pasta `Bin64` dentro da sua instalação.

---

### SQL Server

O `sqlcmd.exe` geralmente já está no PATH quando o SQL Server está instalado, mas pode estar em:

#### SQL Server 2019/2022
```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn
```

#### SQL Server 2017
```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn
```

#### SQL Server 2014
```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\120\Tools\Binn
```

#### SQL Server 2012
```
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\110\Tools\Binn
```

**Nota**: Se você instalou apenas as ferramentas de linha de comando do SQL Server, o caminho pode ser diferente.

---

### PostgreSQL

O PostgreSQL geralmente instala as ferramentas em:

#### PostgreSQL 16
```
C:\Program Files\PostgreSQL\16\bin
```

#### PostgreSQL 15
```
C:\Program Files\PostgreSQL\15\bin
```

#### PostgreSQL 14
```
C:\Program Files\PostgreSQL\14\bin
```

#### PostgreSQL 13
```
C:\Program Files\PostgreSQL\13\bin
```

**Nota**: Se você instalou em um caminho diferente, localize a pasta `bin` dentro da sua instalação do PostgreSQL.

---

## ✅ Como Adicionar ao PATH do Windows

### Método 1: Via Interface Gráfica (Recomendado)

1. **Abrir Configurações de Variáveis de Ambiente**
   - Pressione `Win + X` e selecione **Sistema**
   - Clique em **Configurações avançadas do sistema**
   - Na aba **Avançado**, clique em **Variáveis de Ambiente**

2. **Editar a Variável PATH**
   - Em **Variáveis do sistema**, encontre a variável `Path`
   - Clique em **Editar**
   - Clique em **Novo**
   - Adicione o caminho completo (ex: `C:\Program Files\SQL Anywhere 16\Bin64`)
   - Clique em **OK** em todas as janelas

3. **Reiniciar Terminais/Programas**
   - Feche e reabra qualquer terminal ou programa que precise usar essas ferramentas
   - O aplicativo de backup também precisa ser reiniciado para pegar as mudanças

### Método 2: Via Linha de Comando (Administrador)

Abra o **PowerShell** ou **CMD** como **Administrador** e execute:

#### Para Sybase SQL Anywhere 16:
```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") + ";C:\Program Files\SQL Anywhere 16\Bin64",
    "Machine"
)
```

#### Para SQL Server (ajuste o caminho conforme sua versão):
```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") + ";C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn",
    "Machine"
)
```

#### Para PostgreSQL (ajuste o caminho conforme sua versão):
```powershell
[Environment]::SetEnvironmentVariable(
    "Path",
    [Environment]::GetEnvironmentVariable("Path", "Machine") + ";C:\Program Files\PostgreSQL\16\bin",
    "Machine"
)
```

**Nota**: Após executar via linha de comando, você ainda precisará reiniciar os programas.

---

## 🔍 Como Verificar se Está Configurado Corretamente

### Verificar via Linha de Comando

1. Abra um **novo** Prompt de Comando ou PowerShell
2. Execute os seguintes comandos:

#### Verificar dbbackup (Sybase):
```cmd
dbbackup -?
```

Se aparecer a ajuda do `dbbackup`, está configurado corretamente.

#### Verificar dbisql (Sybase):
```cmd
dbisql -?
```

Se aparecer a ajuda do `dbisql`, está configurado corretamente.

#### Verificar sqlcmd (SQL Server):
```cmd
sqlcmd -?
```

Se aparecer a ajuda do `sqlcmd`, está configurado corretamente.

#### Verificar psql (PostgreSQL):
```cmd
psql --version
```

Se aparecer a versão do PostgreSQL, está configurado corretamente.

#### Verificar pg_basebackup (PostgreSQL):
```cmd
pg_basebackup --version
```

Se aparecer a versão do pg_basebackup, está configurado corretamente.

### Via Interface do Aplicativo

1. No aplicativo de backup, vá em **Configurações > Sybase**
2. Crie uma nova configuração ou edite uma existente
3. Clique em **Testar Conexão**
4. Se funcionar, o PATH está configurado corretamente

---

## ⚠️ Problemas Comuns

### "dbbackup não é reconhecido como comando"

**Solução**:
1. Verifique se o Sybase SQL Anywhere está instalado
2. Localize a pasta `Bin64` na instalação
3. Adicione o caminho completo ao PATH
4. Reinicie o aplicativo de backup

### "sqlcmd não é reconhecido como comando"

**Solução**:
1. Instale as **Ferramentas de Linha de Comando do SQL Server** se não estiverem instaladas
2. Ou localize o caminho onde `sqlcmd.exe` está instalado
3. Adicione o caminho ao PATH
4. Reinicie o aplicativo de backup

### "psql não é reconhecido como comando" ou "'psql' não reconhecido como um comando interno"

**Solução**:
1. Verifique se o PostgreSQL está instalado
2. Localize a pasta `bin` na instalação do PostgreSQL
3. Adicione o caminho completo ao PATH (ex: `C:\Program Files\PostgreSQL\16\bin`)
4. Reinicie o aplicativo de backup
5. Se ainda não funcionar, reinicie o computador para garantir que o PATH seja recarregado

### Mudanças no PATH não foram aplicadas

**Solução**:
- Feche **TODOS** os terminais e programas que possam estar usando o PATH
- Reinicie o computador (recomendado para garantir que tudo seja recarregado)
- Ou apenas reinicie o aplicativo de backup

---

## 📝 Exemplo Completo

Se você tem:
- **Sybase SQL Anywhere 16** instalado em `C:\Program Files\SQL Anywhere 16\Bin64`
- **SQL Server 2019** instalado
- **PostgreSQL 16** instalado

Adicione os seguintes caminhos ao PATH:

```
C:\Program Files\SQL Anywhere 16\Bin64
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn
C:\Program Files\PostgreSQL\16\bin
```

---

## 🆘 Ainda com Problemas?

Se mesmo após configurar o PATH os problemas persistirem:

1. Verifique se as ferramentas realmente existem nos caminhos informados
2. Verifique se você tem permissões de administrador
3. Tente executar os comandos diretamente com o caminho completo:
   ```
   "C:\Program Files\SQL Anywhere 16\Bin64\dbbackup.exe" -?
   ```
4. Consulte os logs do aplicativo em `C:\ProgramData\BackupDatabase\logs\`

