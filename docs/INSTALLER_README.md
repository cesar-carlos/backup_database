# Instalador - Backup Database

## Visão Geral

Este documento descreve o processo de criação e distribuição do instalador do **Backup Database**.

O instalador foi criado usando **Inno Setup**, uma ferramenta gratuita e poderosa para criar instaladores Windows.

---

## Estrutura de Arquivos

```
installer/
├── setup.iss                    # Script principal do Inno Setup
├── check_dependencies.ps1      # Script de verificação de dependências
└── README.md                    # Documentação do instalador

docs/
├── INSTALLATION_GUIDE.md        # Guia de instalação para usuários
├── REQUIREMENTS.md              # Requisitos do sistema
└── PATH_SETUP.md               # Guia de configuração do PATH
```

---

## Funcionalidades do Instalador

### ✅ Instalação Automática

- Instala todos os arquivos necessários do aplicativo
- Cria atalhos no menu Iniciar e área de trabalho (opcional)
- Configura inicialização automática com Windows (opcional)
- Instala Visual C++ Redistributables automaticamente (se necessário)

### ✅ Verificação de Dependências

O instalador verifica automaticamente:

- **Visual C++ Redistributables**: Necessário para executar aplicativos Flutter
- **sqlcmd.exe**: Ferramenta do SQL Server (se usar SQL Server)
- **dbbackup.exe**: Ferramenta do Sybase (se usar Sybase)

**Nota**: Se alguma dependência não for encontrada, o instalador mostra um aviso, mas permite continuar a instalação.

### ✅ Documentação Incluída

O instalador inclui:

- **Guia de Instalação**: Passo a passo para instalar e configurar
- **Requisitos do Sistema**: Lista completa de dependências
- **Guia de Configuração do PATH**: Como configurar sqlcmd e dbbackup

### ✅ Ferramentas Auxiliares

- **Script de Verificação**: `check_dependencies.ps1` para verificar dependências após instalação
- Acessível via menu Iniciar: **"Verificar Dependências"**

---

## Como Criar o Instalador

### Pré-requisitos

1. **Inno Setup 6.0+** instalado
   - Download: https://jrsoftware.org/isdl.php

2. **Projeto Flutter compilado**:
   ```bash
   flutter build windows --release
   ```

3. **Arquivos necessários presentes**:
   - `build\windows\x64\runner\Release\*`
   - `LICENSE`
   - `assets\icons\icon-512-maskable.png`
   - `docs\*.md`

### Passos

1. **Abra o Inno Setup Compiler**

2. **Abra o arquivo** `installer\setup.iss`

3. **Compile o instalador**:
   - Menu: **Build > Compile** (ou `Ctrl+F9`)

4. **O instalador será criado em**:
   - `installer\dist\BackupDatabase-Setup-1.0.0.exe`

---

## Personalização

### Alterar Versão

Edite `installer\setup.iss`:

```iss
#define MyAppVersion "1.0.0"
```

### Alterar Nome do Aplicativo

```iss
#define MyAppName "Backup Database"
```

### Alterar Localização Padrão

```iss
DefaultDirName={autopf}\{#MyAppName}
```

### Adicionar/Remover Tarefas

Edite a seção `[Tasks]`:

```iss
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; ...
Name: "startup"; Description: "Iniciar com o Windows"; ...
```

---

## Visual C++ Redistributables

O instalador tenta instalar automaticamente o Visual C++ Redistributables.

### Configuração Automática

O script já está configurado para:
1. Verificar se o Visual C++ Redistributables está instalado
2. Se não estiver, tentar instalar de `{tmp}\vc_redist.x64.exe`

### Incluir no Instalador (Opcional)

Para incluir o Visual C++ Redistributables no instalador:

1. **Baixe o instalador**:
   - Link: https://aka.ms/vs/17/release/vc_redist.x64.exe
   - Salve em: `installer\dependencies\vc_redist.x64.exe`

2. **Adicione no `setup.iss`**:

```iss
[Files]
Source: "installer\dependencies\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; BeforeInstall: InstallVCRedist
```

3. **Adicione a função**:

```iss
[Code]
procedure InstallVCRedist();
var
  ResultCode: Integer;
begin
  if not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') then
  begin
    Exec(ExpandConstant('{tmp}\vc_redist.x64.exe'), '/quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, ResultCode);
  end;
end;
```

---

## Testando o Instalador

### Checklist de Testes

- [ ] **Instalação em máquina limpa** (VM recomendada)
- [ ] **Verificação de dependências** funciona corretamente
- [ ] **Instalação do Visual C++** funciona (se necessário)
- [ ] **Atalhos** são criados corretamente
- [ ] **Inicialização automática** funciona (se selecionado)
- [ ] **Aplicativo inicia** após instalação
- [ ] **Desinstalação** remove tudo corretamente
- [ ] **Logs** são criados em `C:\ProgramData\BackupDatabase\logs\`

### Ambiente de Teste Recomendado

- **Windows 10/11** (64 bits) limpo
- **Sem** Visual C++ Redistributables instalado (para testar instalação automática)
- **Sem** sqlcmd e dbbackup no PATH (para testar avisos)

---

## Distribuição

### Antes de Distribuir

1. ✅ **Teste o instalador** em máquina limpa
2. ✅ **Verifique o tamanho** do arquivo (~50-100 MB)
3. ✅ **Teste a desinstalação**
4. ✅ **Verifique os logs** após instalação

### Opções de Distribuição

1. **GitHub Releases**:
   - Faça upload do `BackupDatabase-Setup-1.0.0.exe`
   - Adicione notas de release com changelog

2. **Site próprio**:
   - Faça upload para seu servidor
   - Forneça link de download

3. **Assinatura Digital** (recomendado):
   - Obtenha certificado de código
   - Configure no Inno Setup
   - Assine o instalador antes de distribuir

### Assinatura Digital

Para assinar o instalador:

1. **Obtenha certificado** (Code Signing Certificate)

2. **Configure no Inno Setup**:
   - **Tools > Configure Sign Tools**
   - Adicione: `signtool.exe`

3. **Adicione no `setup.iss`**:

```iss
[Setup]
SignTool=signtool
SignedUninstaller=yes
```

---

## Solução de Problemas

### Erro: "Arquivo não encontrado"

**Causa**: Arquivos do projeto não foram compilados.

**Solução**:
1. Execute `flutter build windows --release`
2. Verifique se os arquivos existem em `build\windows\x64\runner\Release\`

### Erro: "Visual C++ Redistributables falhou"

**Causa**: Instalador do Visual C++ não encontrado ou corrompido.

**Solução**:
1. Baixe manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe
2. Inclua no instalador (veja seção acima)
3. Ou instale manualmente antes de executar o Backup Database

### Erro: "Permissões insuficientes"

**Causa**: Instalador não executado como administrador.

**Solução**:
1. Execute o instalador como administrador
2. Configure no `setup.iss`: `PrivilegesRequired=admin`

### Instalador muito grande

**Causa**: Incluindo arquivos desnecessários.

**Solução**:
1. Revise a seção `[Files]` no `setup.iss`
2. Remova arquivos de debug ou desenvolvimento
3. Use compressão: `Compression=lzma`

---

## Recursos Adicionais

- **Documentação do Inno Setup**: https://jrsoftware.org/ishelp/
- **Exemplos de Scripts**: https://github.com/jrsoftware/issrc/tree/main/Examples
- **Fórum do Inno Setup**: https://groups.google.com/g/innosetup

---

## Suporte

Para problemas ou dúvidas sobre o instalador:

1. Consulte a documentação do Inno Setup
2. Verifique os logs de compilação
3. Teste em uma VM limpa
4. Abra uma issue no repositório do projeto

---

**Última atualização**: Versão 1.0.0

