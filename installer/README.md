# Instalador - Backup Database

Este diretório contém os arquivos necessários para criar o instalador do Backup Database.

## Arquivos

- `setup.iss` - Script principal do Inno Setup para criar o instalador
- `check_dependencies.ps1` - Script PowerShell para verificar dependências do sistema
- `README.md` - Este arquivo

## Pré-requisitos para Criar o Instalador

### 1. Inno Setup

Baixe e instale o **Inno Setup** (versão 6.0 ou superior):

- Download: https://jrsoftware.org/isdl.php
- Versão recomendada: Inno Setup 6.2.2 ou superior

### 2. Compilação do Projeto

Antes de criar o instalador, você precisa compilar o projeto Flutter:

```bash
# Compilar para Windows (Release)
flutter build windows --release
```

Isso criará os arquivos em: `build\windows\x64\runner\Release\`

### 3. Arquivos Necessários

Certifique-se de que os seguintes arquivos existem:

- `build\windows\x64\runner\Release\backup_database.exe` - Executável principal
- `build\windows\x64\runner\Release\*` - Todos os arquivos necessários
- `LICENSE` - Arquivo de licença
- `.env.example` - Arquivo de exemplo de variáveis de ambiente
- `assets\icons\icon-512-maskable.png` - Ícone do aplicativo
- `docs\installation_guide.md` - Guia de instalação
- `docs\requirements.md` - Requisitos do sistema
- `docs\path_setup.md` - Guia de configuração do PATH

## Como Criar o Instalador

### Passo 1: Sincronizar Versão (Obrigatório)

Antes de compilar o instalador, **sempre** sincronize a versão do `pubspec.yaml` com o `setup.iss`:

```powershell
# Execute na raiz do projeto
powershell -ExecutionPolicy Bypass -File installer\update_version.ps1
```

Este script:

- Lê a versão do `pubspec.yaml`
- Atualiza automaticamente o `#define MyAppVersion` no `setup.iss` (versão completa: `1.0.1+2`)
- Atualiza automaticamente o `APP_VERSION` no `.env` (versão sem build: `1.0.1`)
- Garante que todas as versões estejam sempre sincronizadas

### Passo 2: Compilar o Instalador

#### Método 1: Via Interface do Inno Setup

1. Abra o **Inno Setup Compiler**
2. Abra o arquivo `installer\setup.iss`
3. Clique em **Build > Compile** (ou pressione `Ctrl+F9`)
4. O instalador será criado em: `installer\dist\BackupDatabase-Setup-{versão}.exe`

#### Método 2: Via Linha de Comando

```bash
# Navegue até a pasta do Inno Setup
cd "C:\Program Files (x86)\Inno Setup 6"

# Compile o script
ISCC.exe "D:\Developer\Flutter\backup_database\installer\setup.iss"
```

O instalador será criado em: `installer\dist\BackupDatabase-Setup-{versão}.exe`

### Método 3: Script Automatizado (Recomendado)

Use o script `build_installer.ps1` que faz tudo automaticamente:

```powershell
# Execute na raiz do projeto
powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
```

Este script:

1. Sincroniza a versão do `pubspec.yaml` com o `setup.iss`
2. Verifica o build do Flutter (`backup_database.exe`)
3. Baixa `vc_redist.x64.exe` automaticamente se ausente
4. Compila o instalador usando Inno Setup
5. Informa onde o instalador foi criado

## Estrutura do Instalador

O instalador criado inclui:

- **Aplicativo**: Todos os arquivos necessários do Flutter
- **Documentação**: Guias de instalação e requisitos
- **Script de Verificação**: Inclui script PowerShell para verificar dependências manualmente (opcional)
- **Instalação de Dependências**: Tenta instalar Visual C++ Redistributables automaticamente
- **Atalhos**: Cria atalhos no menu Iniciar e área de trabalho (opcional)
- **Inicialização Automática**: Opção para iniciar com o Windows (opcional)

## Personalização

### Alterar Versão

**IMPORTANTE**: A versão é sincronizada automaticamente do `pubspec.yaml`.

Para alterar a versão:

1. Edite o `pubspec.yaml` na raiz do projeto:

   ```yaml
   version: 1.0.2
   ```

2. Execute o script de sincronização:

   ```powershell
   powershell -ExecutionPolicy Bypass -File installer\update_version.ps1
   ```

3. Ou use o script automatizado que faz tudo:
   ```powershell
   powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
   ```

**NÃO edite manualmente** o `#define MyAppVersion` no `setup.iss`, pois será sobrescrito pelo script.

### Alterar Nome do Aplicativo

Edite `setup.iss` e altere:

```iss
#define MyAppName "Backup Database"
```

### Alterar Localização de Instalação

Edite `setup.iss` e altere:

```iss
DefaultDirName={autopf}\{#MyAppName}
```

### Adicionar/Remover Tarefas

Edite a seção `[Tasks]` em `setup.iss`:

```iss
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opções de Inicialização"; Flags: unchecked
```

## Visual C++ Redistributables

O `build_installer.ps1` baixa automaticamente o `vc_redist.x64.exe` se não existir em `installer\dependencies\`. O instalador inclui e executa o VC++ Redistributables quando necessário no sistema de destino.

Se o download automático falhar (ex.: sem internet), baixe manualmente de https://aka.ms/vs/17/release/vc_redist.x64.exe e salve em `installer\dependencies\vc_redist.x64.exe`.

## Testando o Instalador

Antes de distribuir:

1. **Teste em uma máquina limpa** (VM recomendada)
2. **Verifique todas as dependências** após instalação
3. **Teste a execução** do aplicativo
4. **Teste a desinstalação**
5. **Verifique os logs** em `C:\ProgramData\BackupDatabase\logs\`

## Distribuição

Após criar o instalador:

1. **Teste o instalador** em uma máquina limpa
2. **Verifique o tamanho** do arquivo (deve ser ~50-100 MB)
3. **Assine digitalmente** (opcional, mas recomendado)
4. **Faça upload** para a página de releases
5. **Atualize o appcast.xml** com a nova versão (se usar auto-update)

## Assinatura Digital (Opcional)

Para assinar o instalador digitalmente:

1. Obtenha um certificado de código (Code Signing Certificate)
2. Configure no Inno Setup:
   - **Tools > Configure Sign Tools**
   - Adicione o caminho para `signtool.exe`
3. Adicione no `setup.iss`:

```iss
[Setup]
SignTool=signtool
SignedUninstaller=yes
```

## Suporte

Para problemas ou dúvidas:

1. Consulte a documentação do Inno Setup: https://jrsoftware.org/ishelp/
2. Verifique os logs de compilação
3. Teste em uma VM limpa

---

**Última atualização**: Versão 2.2.7
