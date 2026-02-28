# Requisitos do Sistema - Backup Database

## Sistema Operacional

- **Windows**: 10 ou superior / Windows Server 2012 R2 ou superior
- **Arquitetura**: 64 bits apenas
- **Permissões**: Administrador para instalação

## Dependências Obrigatórias

- **Visual C++ Redistributables** (2015-2022 x64) — instalado automaticamente pelo instalador

## Dependências por Tipo de Banco

### SQL Server

- `sqlcmd` no PATH do sistema
- Consulte [path_setup.md](path_setup.md) para configurar

### Sybase SQL Anywhere (ASA)

- `dbbackup.exe` e `dbisql` no PATH do sistema
- Consulte [path_setup.md](path_setup.md) para configurar

## Verificação

Use o atalho **"Verificar Dependências"** no menu Iniciar (após instalação) ou execute:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\Backup Database\tools\check_dependencies.ps1"
```
