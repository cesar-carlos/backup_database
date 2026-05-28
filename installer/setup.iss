#define MyAppName "Backup Database"
#define MyAppVersion "3.5.1"
#define MyAppPublisher "Backup Database"
#define MyAppURL "https://github.com/cesar-carlos/backup_database"
#define MyAppExeName "backup_database.exe"

[Setup]
AppId=A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
LicenseFile=..\LICENSE
OutputDir=dist
OutputBaseFilename=BackupDatabase-Setup-{#MyAppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
MinVersion=6.2
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Inno Setup: tasks vem checadas por default. Para desmarcar inicialmente
; use `Flags: unchecked`. Nao existe `Flags: checked` (foi um erro do
; commit ee94182 que so foi detectado no build 3.4.0).
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional Icons"
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opções de Inicialização"

[Dirs]
Name: "{commonappdata}\BackupDatabase\config"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{commonappdata}\BackupDatabase\config"; Flags: ignoreversion; DestName: ".env.example"
Source: "..\docs\install\installation_guide.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\path_setup.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\requirements.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "check_dependencies.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\nssm-2.24\win64\nssm.exe"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "install_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "uninstall_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "encoding_utils.ps1"; Flags: dontcopy
Source: "capture_update_context.ps1"; Flags: dontcopy
Source: "restore_update_state.ps1"; Flags: dontcopy
Source: "merge_env.ps1"; Flags: dontcopy

[Icons]
; Main icons for each mode (all will be created)
Name: "{group}\{#MyAppName} - Server Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; Comment: "Run Backup Database as Server"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{#MyAppName} - Client Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; Comment: "Run Backup Database as Client"; IconFilename: "{app}\{#MyAppExeName}"
; Utility icons
Name: "{group}\Verificar Dependências"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
; Service icons (ONLY for Server mode)
Name: "{group}\Instalar como Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\install_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Remover Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\uninstall_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Documentação"; Filename: "{app}\docs\installation_guide.md"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
; Desktop icon (one per mode — explicit --mode= flag avoids relying on
; {app}\.install_mode being present/valid at launch time).
; §audit-2026-05-28: o icone unico sem --mode= podia abrir como server
; em maquina instalada como cliente se o .install_mode sumisse.
Name: "{autodesktop}\{#MyAppName} (Server)"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Check: IsServerMode
Name: "{autodesktop}\{#MyAppName} (Client)"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Check: IsClientMode

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; Check: ShouldLaunchPostInstall

[UninstallDelete]
Name: "{commonappdata}\BackupDatabase\logs"; Type: filesandordirs
; §audit-2026-05-28: pasta {app} ficava com diretorio vazio em
; "C:\Program Files\Backup Database\" apos uninstall, causando ambiguidade
; em FindUninstaller (varremos unins000/001/002 justamente por causa
; disso). dirifempty so remove se estiver realmente vazia, entao binarios
; nao tocados pelo Inno (downloads, plugins externos) ficam preservados.
Name: "{app}"; Type: dirifempty

[Code]
var
  VCRedistPage: TOutputProgressWizardPage;
  VCRedistNeeded: Boolean;
  ModePage: TInputOptionWizardPage;
  SelectedMode: String;

function IsServiceInstalled(const ServiceName: String): Boolean; forward;
function StopService(const ServiceName: String): Boolean; forward;
function ShouldLaunchPostInstall(): Boolean; forward;
procedure RemoveLegacyStartupEntries(); forward;
procedure DeleteClientStartupTask(); forward;
procedure ConfigureClientStartupTask(const AppExePath: String); forward;
procedure InstallAndStartServiceFromInstaller(const AppExePath, AppDirectory, NssmPath: String); forward;
procedure RefreshWindowsIconCache(); forward;
procedure RemoveExistingDesktopShortcut(); forward;
procedure TouchDesktopShortcut(); forward;

function GetUpdateContextPath(): String;
begin
  Result := ExpandConstant('{commonappdata}\BackupDatabase\staging\updates\update_context.json');
end;

function RunTempPowerShellScript(const ScriptName, Parameters: String): Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
begin
  ExtractTemporaryFile('encoding_utils.ps1');
  ExtractTemporaryFile(ScriptName);
  ScriptPath := ExpandConstant('{tmp}\') + ScriptName;
  Result := Exec(
    'powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' + Parameters,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) and (ResultCode = 0);
end;

// Função auxiliar para encontrar o desinstalador em múltiplos caminhos
function FindUninstaller(): String;
var
  Paths: array of String;
  I: Integer;
  RegPath: String;
  SecondQuotePos: Integer;
begin
  // Lista de caminhos para verificar (em ordem de probabilidade).
  // Inno Setup pode gerar unins001/unins002 quando o instalador foi reaplicado
  // fora da ordem normal de upgrade; varremos as 3 variantes para nao errar.
  Paths := [
    ExpandConstant('C:\Program Files\{#MyAppName}\unins000.exe'),
    ExpandConstant('C:\Program Files\{#MyAppName}\unins001.exe'),
    ExpandConstant('C:\Program Files\{#MyAppName}\unins002.exe'),
    ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins000.exe'),
    ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins001.exe'),
    ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins002.exe'),
    ExpandConstant('{pf}\{#MyAppName}\unins000.exe'),
    ExpandConstant('{pf}\{#MyAppName}\unins001.exe'),
    ExpandConstant('{pf}\{#MyAppName}\unins002.exe'),
    ExpandConstant('{autopf}\{#MyAppName}\unins000.exe'),
    ExpandConstant('{autopf}\{#MyAppName}\unins001.exe'),
    ExpandConstant('{autopf}\{#MyAppName}\unins002.exe')
  ];

  // Tentar encontrar em cada caminho
  for I := 0 to GetArrayLength(Paths) - 1 do
  begin
    if FileExists(Paths[I]) then
    begin
      Result := Paths[I];
      Exit;
    end;
  end;

  // Fallback: buscar no registro do Windows
  if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D_is1', 'UninstallString', RegPath) then
  begin
    // Extrair apenas o caminho do executável (remover parâmetros se houver)
    if Pos('"', RegPath) = 1 then
    begin
      RegPath := Copy(RegPath, 2, Length(RegPath) - 1);
      SecondQuotePos := Pos('"', RegPath);
      if SecondQuotePos > 0 then
      begin
        RegPath := Copy(RegPath, 1, SecondQuotePos - 1);
      end;
    end;

    if FileExists(RegPath) then
    begin
      Result := RegPath;
      Exit;
    end;
  end;

  // Não encontrado
  Result := '';
end;

function IsAppRunning(const ExeName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  // Usar findstr para verificar se o processo está na lista
  // findstr retorna 0 se encontrar, 1 se não encontrar
  if Exec('cmd.exe', '/c tasklist | findstr /I "' + ExeName + '"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    // Se ResultCode = 0, o processo foi encontrado
    Result := (ResultCode = 0);
  end;
end;

function CloseApp(const ExeName: String): Boolean;
var
  ResultCode: Integer;
  Retries: Integer;
  MaxRetries: Integer;
begin
  Result := False;
  Retries := 0;
  MaxRetries := 10;
  
  // Primeira tentativa: fechar graciosamente (sem /F)
  Exec('taskkill.exe', '/IM ' + ExeName + ' /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Sleep(1500);
  
  // Verificar se foi fechado
  if not IsAppRunning(ExeName) then
  begin
    Result := True;
    Exit;
  end;
  
  // Se ainda estiver rodando, tentar forçar o fechamento
  while IsAppRunning(ExeName) and (Retries < MaxRetries) do
  begin
    Exec('taskkill.exe', '/IM ' + ExeName + ' /F /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
    Retries := Retries + 1;
    
    // Verificar se foi fechado após cada tentativa
    if not IsAppRunning(ExeName) then
    begin
      Result := True;
      Exit;
    end;
  end;
  
  // Verificação final
  Result := not IsAppRunning(ExeName);
end;

function InitializeSetup(): Boolean;
var
  AppExe: String;
  WaitCount: Integer;
  UninstallExe: String;
  UninstallPath: String;
  UpdateContextPath: String;
  ResultCode: Integer;
begin
  Result := True;
  VCRedistNeeded := False;
  UpdateContextPath := GetUpdateContextPath();

  // Parar o serviço do Windows primeiro para liberar nssm.exe e a pasta de instalação
  if IsServiceInstalled('BackupDatabaseService') then
  begin
    StopService('BackupDatabaseService');
    Sleep(2000);
  end;

  if WizardSilent() and FileExists(UpdateContextPath) then
  begin
    if RunTempPowerShellScript(
      'capture_update_context.ps1',
      '-ContextPath "' + UpdateContextPath + '" -ServiceName "BackupDatabaseService"'
    ) then
      Log('Captured update_context.json before uninstall')
    else
      Log('Warning: Failed to capture update_context.json before uninstall');
  end;

  // Fechar nssm.exe se estiver em uso (ex.: script "Instalar como Serviço" ainda aberto)
  if IsAppRunning('nssm.exe') then
  begin
    CloseApp('nssm.exe');
    Sleep(1500);
  end;
  
  // Verificar se existe uma instalação anterior e executar desinstalação silenciosa
  UninstallPath := FindUninstaller();

  if UninstallPath <> '' then
  begin
    // Fechar o aplicativo se estiver rodando antes de desinstalar
    AppExe := ExpandConstant('{#MyAppExeName}');
    if IsAppRunning(AppExe) then
    begin
      CloseApp(AppExe);
      Sleep(2000);
    end;

    // Executar desinstalação MUITO silenciosa da versão anterior
    // /VERYSILENT é mais agressivo que /SILENT - não mostra nada
    Exec(UninstallPath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Aguardar até que o processo de desinstalação termine completamente
    // Verificar se o arquivo de desinstalação ainda existe (indica que ainda está em processo)
    WaitCount := 0;
    while FileExists(UninstallPath) and (WaitCount < 30) do
    begin
      Sleep(500);
      WaitCount := WaitCount + 1;
    end;

    // Aguardar um pouco mais para garantir que todos os processos foram finalizados
    Sleep(2000);

    // Verificar se ainda há processos relacionados rodando
    if IsAppRunning(AppExe) then
    begin
      CloseApp(AppExe);
      Sleep(1000);
    end;
  end;
  
  // Fechar processos de desinstalação se estiverem rodando
  UninstallExe := 'unins000.exe';
  if IsAppRunning(UninstallExe) then
  begin
    CloseApp(UninstallExe);
    Sleep(2000);
  end;
  
  // Verificar se o aplicativo está em execução
  AppExe := ExpandConstant('{#MyAppExeName}');
  
  if IsAppRunning(AppExe) then
  begin
    // Se estiver em modo silencioso (atualização automática), fechar sem perguntar
    if WizardSilent() then
    begin
      // Modo silencioso: fechar automaticamente sem perguntar
      CloseApp(AppExe);
      
      // Aguardar até que o processo seja completamente finalizado
      WaitCount := 0;
      while IsAppRunning(AppExe) and (WaitCount < 30) do
      begin
        Sleep(500);
        WaitCount := WaitCount + 1;
      end;
    end
    else
    begin
      // Modo interativo: perguntar ao usuário
      if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' está em execução.' + #13#10 + #13#10 +
                'É necessário fechar o aplicativo para continuar com a instalação.' + #13#10 + #13#10 +
                'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
      begin
        // Tentar fechar o aplicativo
        CloseApp(AppExe);
        
        // Aguardar até que o processo seja completamente finalizado
        WaitCount := 0;
        while IsAppRunning(AppExe) and (WaitCount < 30) do
        begin
          Sleep(500);
          WaitCount := WaitCount + 1;
        end;
        
        // Se ainda estiver rodando após todas as tentativas, avisar mas continuar
        if IsAppRunning(AppExe) then
        begin
          if MsgBox('O aplicativo ainda parece estar em execução após tentativas de fechamento.' + #13#10 + #13#10 +
                    'A instalação pode falhar se o aplicativo não for fechado.' + #13#10 + #13#10 +
                    'Deseja continuar mesmo assim?', mbConfirmation, MB_YESNO) = IDNO then
          begin
            Result := False;
            Exit;
          end;
        end;
        
        // Se chegou aqui, o aplicativo foi fechado ou o usuário escolheu continuar
        // Continuar com a instalação
      end
      else
      begin
        // Usuário escolheu não fechar - não pode continuar
        Result := False;
        Exit;
      end;
    end;
  end;
  
  if not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') then
  begin
    VCRedistNeeded := True;
  end;
end;

procedure InitializeWizard();
begin
  // Create mode selection page
  ModePage := CreateInputOptionPage(wpLicense,
    'Select Installation Mode',
    'Choose how you want to use Backup Database',
    'Select the installation mode that best fits your needs:',
    True, False);

  // Add options (only Server and Client)
  ModePage.Add('(Recommended) Server Mode - Run as a dedicated backup server (allows remote connections)');
  ModePage.Add('Client Mode - Connect to a remote server and manage backups remotely');

  // Set default selection (Server mode - index 0)
  ModePage.SelectedValueIndex := 0;

  if VCRedistNeeded then
  begin
    VCRedistPage := CreateOutputProgressPage('Checking Dependencies', 'Installing Visual C++ Redistributables...');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  VCRedistPath: String;
  VCRedistErrorCode: Integer;
  ExecResult: Boolean;
  AppExe: String;
  UserChoice: Integer;
begin
  Result := '';

  // Reforco defensivo: NSSM pode ter reiniciado o servico entre
  // InitializeSetup e PrepareToInstall (ex.: usuario passou tempo no
  // wizard). Parar de novo antes de copiar arquivos garante que o .exe
  // sera substituido — atalho da area de trabalho passa a refletir o
  // icone novo no primeiro launch.
  if IsServiceInstalled('BackupDatabaseService') then
  begin
    StopService('BackupDatabaseService');
    Sleep(2000);
  end;

  // Verificar novamente se o aplicativo está rodando antes de instalar
  AppExe := ExpandConstant('{#MyAppExeName}');
  if IsAppRunning(AppExe) then
  begin
    // Tentar fechar novamente de forma mais agressiva
    Exec('taskkill.exe', '/IM ' + AppExe + ' /F /T', '', SW_HIDE, ewWaitUntilTerminated, VCRedistErrorCode);
    Sleep(2000);
    
    // Tentar novamente se ainda estiver rodando
    if IsAppRunning(AppExe) then
    begin
      Exec('taskkill.exe', '/IM ' + AppExe + ' /F /T', '', SW_HIDE, ewWaitUntilTerminated, VCRedistErrorCode);
      Sleep(2000);
    end;
    
    // Se ainda estiver rodando após todas as tentativas, registrar evidência
    // explícita no log do Inno Setup. Em modo silencioso (auto update)
    // abortamos. Em modo interativo pedimos confirmação ao usuário porque
    // continuar com o app aberto costuma deixar o .exe antigo no disco —
    // sintoma classico: atalho desktop continua com icone velho apos
    // instalar versao nova.
    if IsAppRunning(AppExe) then
    begin
      Log('WARNING: ' + AppExe + ' continua em execucao apos taskkill; '
        + 'arquivos abertos podem nao ser substituidos nesta instalacao.');
      if WizardSilent() then
      begin
        Result := 'O aplicativo ' + ExpandConstant('{#MyAppName}')
          + ' continua em execucao. A instalacao silenciosa nao pode garantir '
          + 'a substituicao completa dos binarios.';
        Exit;
      end
      else
      begin
        UserChoice := MsgBox(
          'O aplicativo ' + ExpandConstant('{#MyAppName}')
          + ' continua em execucao mesmo apos varias tentativas de fechamento.'#13#10#13#10
          + 'Continuar agora pode deixar o executavel atual no disco — o atalho '
          + 'da area de trabalho pode continuar mostrando o icone antigo ate que '
          + 'a maquina seja reiniciada.'#13#10#13#10
          + 'Deseja continuar mesmo assim? (Nao recomendado)',
          mbConfirmation,
          MB_YESNO or MB_DEFBUTTON2
        );
        if UserChoice = IDNO then
        begin
          Result := 'Instalacao cancelada pelo usuario: o aplicativo continua em '
            + 'execucao. Feche o ' + ExpandConstant('{#MyAppName}') + ' e tente novamente.';
          Exit;
        end;
        Log('WARNING: usuario optou por continuar com ' + AppExe + ' aberto; '
          + 'icone do atalho pode permanecer desatualizado ate o proximo logon.');
      end;
    end;
  end;

  if VCRedistNeeded then
  begin
    VCRedistPage.SetText('Instalando Visual C++ Redistributables 2015-2022 (x64)...', 'Aguarde...');
    VCRedistPage.SetProgress(0, 0);
    VCRedistPage.Show;
    
    VCRedistPath := ExpandConstant('{tmp}\vc_redist.x64.exe');
    
    if not FileExists(VCRedistPath) then
    begin
      Result := 'Visual C++ Redistributables não encontrado. Por favor, baixe e instale manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe';
      VCRedistPage.Hide;
      Exit;
    end;
    
    ExecResult := Exec(VCRedistPath, '/quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, VCRedistErrorCode);
    
    if not ExecResult or (VCRedistErrorCode <> 0) then
    begin
      Result := 'Erro ao instalar Visual C++ Redistributables. Código de erro: ' + IntToStr(VCRedistErrorCode);
      VCRedistPage.Hide;
      Exit;
    end;
    
    VCRedistPage.Hide;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;

  // Only store selected mode when leaving the mode page - do NOT use {app} here
  // because the user has not yet chosen the install path (Select Dir comes after)
  if CurPageID = ModePage.ID then
  begin
    case ModePage.SelectedValueIndex of
      0: SelectedMode := 'server';
      1: SelectedMode := 'client';
    else
      SelectedMode := 'server';
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ModeFile: TStringList;
  ModeFilePath: String;
  EnvExamplePath: String;
  EnvPath: String;
  LegacyEnvPath: String;
  MigratedBackupPath: String;
  UpdateContextPath: String;
  AppExePath: String;
  NssmPath: String;
begin
  // Remover o .lnk antigo da area de trabalho ANTES da secao [Icons] do Inno
  // gerar o novo. Sem isso, o Explorer pode preservar o icone cacheado mesmo
  // quando o .lnk e sobrescrito — sintoma reportado: icone velho do Flutter
  // sobrevive ao upgrade.
  if (CurStep = ssInstall) and WizardIsTaskSelected('desktopicon') then
  begin
    RemoveExistingDesktopShortcut();
  end;

  // Write .install_mode only after files are installed, when {app} is defined
  if CurStep = ssPostInstall then
  begin
    EnvExamplePath := ExpandConstant('{commonappdata}\BackupDatabase\config\.env.example');
    EnvPath := ExpandConstant('{commonappdata}\BackupDatabase\config\.env');
    LegacyEnvPath := ExpandConstant('{app}\.env');
    MigratedBackupPath := ExpandConstant('{commonappdata}\BackupDatabase\config\.env.migrated-from-appdir.bak');
    UpdateContextPath := GetUpdateContextPath();
    AppExePath := ExpandConstant('{app}\{#MyAppExeName}');
    NssmPath := ExpandConstant('{app}\tools\nssm.exe');

    // merge_env.ps1 retorna:
    //   0 = OK (merge feito ou no-op)
    //   2 = chaves criticas ausentes apos merge (auto-update ficara desabilitado)
    //   outro = falha generica
    // Loggamos a distincao para troubleshooting pos-install.
    if RunTempPowerShellScript(
      'merge_env.ps1',
      '-ExamplePath "' + EnvExamplePath + '" ' +
      '-TargetPath "' + EnvPath + '" ' +
      '-LegacyPath "' + LegacyEnvPath + '" ' +
      '-BackupPath "' + MigratedBackupPath + '"'
    ) then
      Log('Merged machine-scope .env with .env.example')
    else
      Log('Warning: Failed to merge machine-scope .env with .env.example ' +
          '(possivel chave critica ausente como AUTO_UPDATE_FEED_URL; ' +
          'auto-update ficara desabilitado ate corrigir ' + EnvPath + ')');

    if SelectedMode = '' then
      SelectedMode := 'server';
    ModeFilePath := ExpandConstant('{app}\.install_mode');
    ModeFile := TStringList.Create;
    try
      ModeFile.Add(SelectedMode);
      ModeFile.SaveToFile(ModeFilePath);
    finally
      ModeFile.Free;
    end;

    RemoveLegacyStartupEntries();

    if WizardIsTaskSelected('startup') then
    begin
      if SelectedMode = 'server' then
        InstallAndStartServiceFromInstaller(AppExePath, ExpandConstant('{app}'), NssmPath)
      else
        ConfigureClientStartupTask(AppExePath);
    end
    else
      DeleteClientStartupTask();

    if WizardSilent() and FileExists(UpdateContextPath) then
    begin
      if RunTempPowerShellScript(
        'restore_update_state.ps1',
        '-ContextPath "' + UpdateContextPath + '" ' +
        '-AppPath "' + AppExePath + '" ' +
        '-AppDirectory "' + ExpandConstant('{app}') + '" ' +
        '-NssmPath "' + NssmPath + '" ' +
        '-ServiceName "BackupDatabaseService"'
      ) then
        Log('Restored update operational state from update_context.json')
      else
        Log('Warning: Failed to restore update operational state from update_context.json');
    end;

    RefreshWindowsIconCache();
    TouchDesktopShortcut();
  end;
end;

// Icon helpers (RemoveExistingDesktopShortcut, TryTouchShortcutWith,
// TouchDesktopShortcut, RefreshWindowsIconCache) sao incluidos a partir
// de code/icons.iss para manter este arquivo focado na orquestracao
// macro. Veja ADR-015 para o racional do conjunto.
#include "code/icons.iss"

// Check if server mode was selected (used to conditionally create service icons)
function IsServerMode(): Boolean;
begin
  Result := (SelectedMode = 'server');
end;

function IsClientMode(): Boolean;
begin
  Result := (SelectedMode = 'client');
end;

function ShouldLaunchPostInstall(): Boolean;
begin
  Result := not ((SelectedMode = 'server') and WizardIsTaskSelected('startup'));
end;

procedure RemoveLegacyStartupEntries();
var
  ResultCode: Integer;
begin
  Exec('reg.exe', 'delete "HKLM\Software\Microsoft\Windows\CurrentVersion\Run" /v "{#MyAppName}" /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('reg.exe', 'delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "BackupDatabase" /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec('reg.exe', 'delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v "{#MyAppName}" /f', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure DeleteClientStartupTask();
var
  ResultCode: Integer;
begin
  Exec('schtasks.exe', '/Delete /TN "\BackupDatabase\MachineStartup" /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

procedure ConfigureClientStartupTask(const AppExePath: String);
var
  ResultCode: Integer;
  TaskRun: String;
begin
  DeleteClientStartupTask();
  // §audit-2026-05-28: passar --mode=client explicitamente. Antes a task
  // dependia 100% de {app}\.install_mode para resolver o modo; se o
  // arquivo sumisse/corrompesse o resolver caia em "server" (default),
  // abrindo o socket server em uma maquina instalada como cliente.
  TaskRun := '"\"' + AppExePath + '\" --mode=client --minimized --launch-origin=windows-startup"';
  Exec('schtasks.exe', '/Create /TN "\BackupDatabase\MachineStartup" /SC ONLOGON /TR ' + TaskRun + ' /F /RL LIMITED', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if ResultCode <> 0 then
    Log('Warning: failed to create client startup scheduled task, exit=' + IntToStr(ResultCode));
end;

procedure InstallAndStartServiceFromInstaller(const AppExePath, AppDirectory, NssmPath: String);
var
  ResultCode: Integer;
  ScriptPath: String;
  Args: String;
begin
  ScriptPath := ExpandConstant('{app}\tools\install_service.ps1');

  // Pre-condicoes: scripts e binarios necessarios. Sem isso o
  // install_service.ps1 falha tarde (ResultCode 1) e o atalho "Iniciar com o
  // Windows" silenciosamente nao registra o servico.
  if not FileExists(ScriptPath) then
  begin
    Log('ERROR: install_service.ps1 ausente em ' + ScriptPath
      + '; servico nao sera registrado.');
    if not WizardSilent() then
      MsgBox('Nao foi possivel encontrar o script de instalacao do servico:'
        + #13#10 + ScriptPath + #13#10 + #13#10
        + 'Reinstale o aplicativo ou execute manualmente.',
        mbError, MB_OK);
    Exit;
  end;
  if not FileExists(NssmPath) then
  begin
    Log('ERROR: nssm.exe ausente em ' + NssmPath
      + '; servico nao sera registrado.');
    if not WizardSilent() then
      MsgBox('Nao foi possivel encontrar nssm.exe em:' + #13#10 + NssmPath
        + #13#10 + #13#10
        + 'Reinstale o aplicativo ou copie nssm.exe para a pasta tools.',
        mbError, MB_OK);
    Exit;
  end;

  Args :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' +
    '-NonInteractive ' +
    '-AppPath "' + AppExePath + '" ' +
    '-AppDirectory "' + AppDirectory + '" ' +
    '-NssmPath "' + NssmPath + '"';
  if Exec('powershell.exe', Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
      Exec('sc.exe', 'start BackupDatabaseService', '', SW_HIDE, ewWaitUntilTerminated, ResultCode)
    else
      Log('Warning: install_service.ps1 failed, exit=' + IntToStr(ResultCode));
  end
  else
    Log('Warning: failed to launch install_service.ps1 from installer');
end;

function IsServiceInstalled(const ServiceName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec('sc.exe', 'query ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    Result := (ResultCode = 0);
  end;
end;

function RemoveService(const ServiceName: String): Boolean;
var
  ResultCode: Integer;
  Retries: Integer;
  MaxRetries: Integer;
begin
  Result := False;
  Retries := 0;
  MaxRetries := 5;
  
  if not IsServiceInstalled(ServiceName) then
  begin
    Result := True;
    Exit;
  end;
  
  while (Retries < MaxRetries) do
  begin
    Exec('sc.exe', 'stop ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(2000);
    
    Exec('sc.exe', 'delete ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    
    if ResultCode = 0 then
    begin
      Result := True;
      Sleep(1000);
      Exit;
    end;
    
    Retries := Retries + 1;
    Sleep(1000);
  end;
  
  Result := not IsServiceInstalled(ServiceName);
end;

function StopService(const ServiceName: String): Boolean;
var
  ResultCode: Integer;
  Retries: Integer;
  MaxRetries: Integer;
begin
  Result := False;
  Retries := 0;
  MaxRetries := 5;
  
  if not IsServiceInstalled(ServiceName) then
  begin
    Result := True;
    Exit;
  end;
  
  while (Retries < MaxRetries) do
  begin
    Exec('sc.exe', 'stop ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    
    if ResultCode = 0 then
    begin
      Sleep(2000);
      Result := True;
      Exit;
    end;
    
    Retries := Retries + 1;
    Sleep(1000);
  end;
  
  Result := False;
end;

function InitializeUninstall(): Boolean;
var
  AppExe: String;
  ServiceName: String;
begin
  Result := True;
  AppExe := ExpandConstant('{#MyAppExeName}');
  ServiceName := 'BackupDatabaseService';
  
  // Parar o serviço do Windows ANTES de qualquer outra ação
  if IsServiceInstalled(ServiceName) then
  begin
    StopService(ServiceName);
    Sleep(2000);
  end;
  
  // Verificar se o aplicativo está em execução durante a desinstalação
  if IsAppRunning(AppExe) then
  begin
    if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' está em execução.' + #13#10 + #13#10 +
              'É necessário fechar o aplicativo para continuar com a desinstalação.' + #13#10 + #13#10 +
              'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      if not CloseApp(AppExe) then
      begin
        MsgBox('Não foi possível fechar o aplicativo automaticamente.' + #13#10 + #13#10 +
               'Por favor, feche o aplicativo manualmente e tente novamente.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
      
      // Aguardar um pouco mais para garantir que o processo foi finalizado
      Sleep(1000);
      
      if IsAppRunning(AppExe) then
      begin
        MsgBox('O aplicativo ainda está em execução.' + #13#10 + #13#10 +
               'Por favor, feche o aplicativo manualmente e tente novamente.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
    end
    else
    begin
      Result := False;
      Exit;
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ServiceName: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    ServiceName := 'BackupDatabaseService';
    
    if IsServiceInstalled(ServiceName) then
    begin
      RemoveService(ServiceName);
    end;
  end;
end;
