#define MyAppName "Backup Database"
#define MyAppVersion "3.6.3"
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
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
brazilianportuguese.ModePageTitle=Selecione o modo de instalação
brazilianportuguese.ModePageSubtitle=Escolha como deseja usar o Backup Database
brazilianportuguese.ModePageDescription=Selecione o modo que melhor atende às suas necessidades:
brazilianportuguese.ModeServer=(Recomendado) Modo servidor — executa como servidor de backup dedicado (aceita conexões remotas)
brazilianportuguese.ModeClient=Modo cliente — conecta a um servidor remoto e gerencia os backups à distância
brazilianportuguese.DesktopIcon=Criar um ícone na área de trabalho
brazilianportuguese.DesktopIconGroup=Ícones adicionais
brazilianportuguese.StartupTask=Iniciar com o Windows
brazilianportuguese.StartupGroup=Opções de inicialização
brazilianportuguese.FirewallTask=Liberar a porta TCP 9527 no Firewall do Windows (clientes remotos)
brazilianportuguese.FirewallGroup=Rede
brazilianportuguese.LaunchApp=Iniciar {#MyAppName}
brazilianportuguese.VcPageTitle=Verificando dependências
brazilianportuguese.VcPageDescription=Instalando o Visual C++ Redistributable...
brazilianportuguese.VcProgress=Instalando o Visual C++ Redistributable 2015-2022 (x64)...
brazilianportuguese.VcWait=Aguarde...
brazilianportuguese.AppRunningClosePrompt=O aplicativo %1 está em execução.%n%nÉ necessário fechar o aplicativo para continuar com a instalação.%n%nDeseja fechar o aplicativo agora?
brazilianportuguese.AppStillRunningContinuePrompt=O aplicativo ainda parece estar em execução após tentativas de fechamento.%n%nA instalação pode falhar se o aplicativo não for fechado.%n%nDeseja continuar mesmo assim?
brazilianportuguese.AppStillRunningSilent=O aplicativo %1 continua em execucao. A instalacao silenciosa nao pode garantir a substituicao completa dos binarios.
brazilianportuguese.AppStillRunningRiskPrompt=O aplicativo %1 continua em execucao mesmo apos varias tentativas de fechamento.%n%nContinuar agora pode deixar o executavel atual no disco — o atalho da area de trabalho pode continuar mostrando o icone antigo ate que a maquina seja reiniciada.%n%nDeseja continuar mesmo assim? (Nao recomendado)
brazilianportuguese.InstallCancelledAppRunning=Instalacao cancelada pelo usuario: o aplicativo continua em execucao. Feche o %1 e tente novamente.
brazilianportuguese.VcRedistMissing=Visual C++ Redistributables não encontrado. Por favor, baixe e instale manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe
brazilianportuguese.VcRedistFailed=Erro ao instalar Visual C++ Redistributables. Código de erro: %1
brazilianportuguese.EnvFeedUrlMissing=A chave AUTO_UPDATE_FEED_URL nao ficou preenchida em:%n%1%n%nA instalacao continua, mas o auto-update ficara desabilitado ate corrigir o arquivo .env.
brazilianportuguese.ServiceScriptMissing=Nao foi possivel encontrar o script de instalacao do servico:%n%1%n%nReinstale o aplicativo ou execute manualmente.
brazilianportuguese.NssmMissing=Nao foi possivel encontrar nssm.exe em:%n%1%n%nReinstale o aplicativo ou copie nssm.exe para a pasta tools.
brazilianportuguese.ServiceNotRunning=O servico foi instalado, mas nao confirmou RUNNING no tempo de espera.%n%nVerifique o status em Servicos do Windows ou reinstale o servico pelo aplicativo.
brazilianportuguese.ServiceInstallFailed=Falha ao instalar o servico do Windows (codigo %1).%n%nConsulte o log do instalador e tente novamente.
brazilianportuguese.ServiceScriptLaunchFailed=Nao foi possivel executar o script de instalacao do servico.
brazilianportuguese.AppRunningUninstallPrompt=O aplicativo %1 está em execução.%n%nÉ necessário fechar o aplicativo para continuar com a desinstalação.%n%nDeseja fechar o aplicativo agora?
brazilianportuguese.AppCloseFailed=Não foi possível fechar o aplicativo automaticamente.%n%nPor favor, feche o aplicativo manualmente e tente novamente.
brazilianportuguese.AppStillRunningUninstall=O aplicativo ainda está em execução.%n%nPor favor, feche o aplicativo manualmente e tente novamente.
brazilianportuguese.UninstallRemoveConfig=Deseja tambem remover os dados da maquina em %1 (banco de dados, segredos, logs, .env, staging e locks)?%n%nEscolha Nao para preservar a configuracao para uma reinstalacao.
brazilianportuguese.ShortcutServerMode={#MyAppName} - Modo servidor
brazilianportuguese.ShortcutClientMode={#MyAppName} - Modo cliente
brazilianportuguese.ShortcutUninstall=Desinstalar {#MyAppName}
english.ModePageTitle=Select installation mode
english.ModePageSubtitle=Choose how you want to use Backup Database
english.ModePageDescription=Select the installation mode that best fits your needs:
english.ModeServer=(Recommended) Server mode — run as a dedicated backup server (allows remote connections)
english.ModeClient=Client mode — connect to a remote server and manage backups remotely
english.DesktopIcon=Create a desktop icon
english.DesktopIconGroup=Additional icons
english.StartupTask=Start with Windows
english.StartupGroup=Startup options
english.FirewallTask=Allow TCP port 9527 in Windows Firewall (remote clients)
english.FirewallGroup=Network
english.LaunchApp=Launch {#MyAppName}
english.VcPageTitle=Checking dependencies
english.VcPageDescription=Installing the Visual C++ Redistributable...
english.VcProgress=Installing the Visual C++ Redistributable 2015-2022 (x64)...
english.VcWait=Please wait...
english.AppRunningClosePrompt=%1 is running.%n%nThe application must be closed before the installation can continue.%n%nClose it now?
english.AppStillRunningContinuePrompt=The application still appears to be running after attempts to close it.%n%nThe installation may fail if the application is not closed.%n%nContinue anyway?
english.AppStillRunningSilent=%1 is still running. The silent installation cannot guarantee that all binaries will be replaced.
english.AppStillRunningRiskPrompt=%1 is still running after several attempts to close it.%n%nContinuing now may leave the current executable on disk — the desktop shortcut may keep showing the old icon until the computer is restarted.%n%nContinue anyway? (Not recommended)
english.InstallCancelledAppRunning=Installation cancelled: the application is still running. Close %1 and try again.
english.VcRedistMissing=Visual C++ Redistributable was not found. Download and install it manually: https://aka.ms/vs/17/release/vc_redist.x64.exe
english.VcRedistFailed=Failed to install the Visual C++ Redistributable. Error code: %1
english.EnvFeedUrlMissing=AUTO_UPDATE_FEED_URL was left empty in:%n%1%n%nInstallation will continue, but auto-update stays disabled until the .env file is corrected.
english.ServiceScriptMissing=The service installation script was not found:%n%1%n%nReinstall the application or run the script manually.
english.NssmMissing=nssm.exe was not found at:%n%1%n%nReinstall the application or copy nssm.exe into the tools folder.
english.ServiceNotRunning=The service was installed, but it did not confirm RUNNING within the wait time.%n%nCheck Services in Windows or reinstall the service from the application.
english.ServiceInstallFailed=Failed to install the Windows service (code %1).%n%nCheck the installer log and try again.
english.ServiceScriptLaunchFailed=The service installation script could not be started.
english.AppRunningUninstallPrompt=%1 is running.%n%nThe application must be closed before uninstall can continue.%n%nClose it now?
english.AppCloseFailed=The application could not be closed automatically.%n%nClose it manually and try again.
english.AppStillRunningUninstall=The application is still running.%n%nClose it manually and try again.
english.UninstallRemoveConfig=Also remove machine data in %1 (database, secrets, logs, .env, staging, and locks)?%n%nChoose No to keep this configuration for a reinstall.
english.ShortcutServerMode={#MyAppName} - Server Mode
english.ShortcutClientMode={#MyAppName} - Client Mode
english.ShortcutUninstall=Uninstall {#MyAppName}

[Tasks]
; Inno Setup: tasks vem checadas por default. Para desmarcar inicialmente
; use `Flags: unchecked`. Nao existe `Flags: checked` (foi um erro do
; commit ee94182 que so foi detectado no build 3.4.0).
Name: "desktopicon"; Description: "{cm:DesktopIcon}"; GroupDescription: "{cm:DesktopIconGroup}"
Name: "startup"; Description: "{cm:StartupTask}"; GroupDescription: "{cm:StartupGroup}"
Name: "openfirewall"; Description: "{cm:FirewallTask}"; GroupDescription: "{cm:FirewallGroup}"; Flags: unchecked; Check: IsServerMode

[Dirs]
Name: "{commonappdata}\BackupDatabase\config"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{commonappdata}\BackupDatabase\config"; Flags: ignoreversion; DestName: ".env.example"
Source: "..\docs\install\installation_guide.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\path_setup.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\requirements.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "TROUBLESHOOTING_SERVICE.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "check_dependencies.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\nssm-2.24\win64\nssm.exe"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "install_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "service_utils.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "uninstall_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "encoding_utils.ps1"; Flags: dontcopy
Source: "capture_update_context.ps1"; Flags: dontcopy
Source: "restore_update_state.ps1"; Flags: dontcopy
Source: "merge_env.ps1"; Flags: dontcopy
Source: "read_json_app_mode.ps1"; Flags: dontcopy
Source: "service_utils.ps1"; Flags: dontcopy

[Icons]
; Main icons for each mode (all will be created)
Name: "{group}\{cm:ShortcutServerMode}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; Comment: "Run Backup Database as Server"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:ShortcutClientMode}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; Comment: "Run Backup Database as Client"; IconFilename: "{app}\{#MyAppExeName}"
; Utility icons
Name: "{group}\Verificar Dependências"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
; Service icons (ONLY for Server mode)
Name: "{group}\Instalar como Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\install_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Remover Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\uninstall_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Documentação"; Filename: "{app}\docs\installation_guide.md"
Name: "{group}\Troubleshooting do Serviço"; Filename: "{app}\docs\TROUBLESHOOTING_SERVICE.md"
Name: "{group}\{cm:ShortcutUninstall}"; Filename: "{uninstallexe}"
; Desktop icon (one per mode — explicit --mode= flag avoids relying on
; {app}\.install_mode being present/valid at launch time).
; §audit-2026-05-28: o icone unico sem --mode= podia abrir como server
; em maquina instalada como cliente se o .install_mode sumisse.
Name: "{autodesktop}\{#MyAppName} (Server)"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Check: IsServerMode
Name: "{autodesktop}\{#MyAppName} (Client)"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; IconFilename: "{app}\{#MyAppExeName}"; Tasks: desktopicon; Check: IsClientMode

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchApp}"; Flags: nowait postinstall skipifsilent; Check: ShouldLaunchPostInstall

[UninstallDelete]
Name: "{commonappdata}\BackupDatabase\logs"; Type: filesandordirs; Check: ShouldRemoveMachineConfig
Name: "{commonappdata}\BackupDatabase"; Type: filesandordirs; Check: ShouldRemoveMachineConfig
; dirifempty so remove se estiver realmente vazia, entao binarios
; nao tocados pelo Inno (downloads, plugins externos) ficam preservados.
Name: "{app}"; Type: dirifempty

[Code]
var
  VCRedistPage: TOutputProgressWizardPage;
  VCRedistNeeded: Boolean;
  ModePage: TInputOptionWizardPage;
  SelectedMode: String;
  RemoveMachineConfig: Boolean;

function IsServiceInstalled(const ServiceName: String): Boolean; forward;
function WaitForServiceStopped(const ServiceName: String): Boolean; forward;
function WaitForServiceRemoved(const ServiceName: String): Boolean; forward;
function StopService(const ServiceName: String): Boolean; forward;
function ShouldRemoveMachineConfig(): Boolean; forward;
function RunTempPowerShellScriptEx(const ScriptName, Parameters: String; var ExitCode: Integer): Boolean; forward;
function ShouldLaunchPostInstall(): Boolean; forward;
function NormalizeInstallMode(const Raw: String): String; forward;
function ResolveSelectedMode(): String; forward;
function ReadUpdateContextAppMode(): String; forward;
function IsVCRedistInstalled(): Boolean; forward;
function IsVCRedistSuccessExitCode(const ExitCode: Integer): Boolean; forward;
procedure RemoveLegacyStartupEntries(); forward;
procedure SaveSelectedUiLocale(); forward;
procedure DeleteClientStartupTask(); forward;
procedure ConfigureClientStartupTask(const AppExePath: String); forward;
procedure InstallAndStartServiceFromInstaller(const AppExePath, AppDirectory, NssmPath: String); forward;
procedure RefreshWindowsIconCache(); forward;
procedure RemoveExistingDesktopShortcut(); forward;
procedure TouchDesktopShortcut(); forward;
procedure ConfigureRemoteSocketFirewall(); forward;
procedure DeleteRemoteSocketFirewall(); forward;
procedure RemoveLegacyEnglishStartMenuShortcuts(); forward;
function ExpandCustomMessage(const Name: String): String; forward;
function ExpandCustomMessage1(const Name, Arg1: String): String; forward;
function IsInstalledAppRunning(const AppExePath: String): Boolean; forward;
procedure TaskkillInstalledApp(const AppExePath: String); forward;

function ExpandCustomMessage(const Name: String): String;
var
  Message: String;
begin
  Message := CustomMessage(Name);
  StringChangeEx(Message, '%n', #13#10, True);
  Result := Message;
end;

function ExpandCustomMessage1(const Name, Arg1: String): String;
begin
  Result := FmtMessage(ExpandCustomMessage(Name), [Arg1]);
end;

function GetUpdateContextPath(): String;
begin
  Result := ExpandConstant('{commonappdata}\BackupDatabase\staging\updates\update_context.json');
end;

function RunTempPowerShellScriptEx(const ScriptName, Parameters: String; var ExitCode: Integer): Boolean;
var
  ScriptPath: String;
begin
  ExtractTemporaryFile('encoding_utils.ps1');
  ExtractTemporaryFile('service_utils.ps1');
  ExtractTemporaryFile(ScriptName);
  ScriptPath := ExpandConstant('{tmp}\') + ScriptName;
  Result := Exec(
    'powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' + Parameters,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ExitCode
  );
end;

function RunTempPowerShellScript(const ScriptName, Parameters: String): Boolean;
var
  ExitCode: Integer;
begin
  Result := RunTempPowerShellScriptEx(ScriptName, Parameters, ExitCode) and (ExitCode = 0);
end;

function NormalizeInstallMode(const Raw: String): String;
var
  Value: String;
begin
  Value := LowerCase(Trim(Raw));
  if Value = 'client' then
    Result := 'client'
  else if Value = 'server' then
    Result := 'server'
  else
    Result := '';
end;

function ReadUpdateContextAppMode(): String;
var
  OutputPath: String;
  Lines: TArrayOfString;
  ExitCode: Integer;
begin
  Result := '';
  if not FileExists(GetUpdateContextPath()) then
    Exit;
  OutputPath := ExpandConstant('{tmp}\update_context_app_mode.txt');
  if FileExists(OutputPath) then
    DeleteFile(OutputPath);
  if not RunTempPowerShellScriptEx(
    'read_json_app_mode.ps1',
    '-ContextPath "' + GetUpdateContextPath() + '" -OutputPath "' + OutputPath + '"',
    ExitCode
  ) then
    Exit;
  if (ExitCode = 0) and FileExists(OutputPath) then
  begin
    if LoadStringsFromFile(OutputPath, Lines) and (GetArrayLength(Lines) > 0) then
      Result := Trim(Lines[0]);
  end;
end;

function GetInstallModeFilePath(): String;
var
  AppDir: String;
begin
  // {app} is not initialized during InitializeWizard. Expanding it here
  // aborts Setup with: Internal error: An attempt was made to expand the
  // 'app' constant before it was initialized.
  AppDir := ExpandConstant('{autopf}\{#MyAppName}');
  if WizardForm.PrevAppDir <> '' then
    AppDir := WizardForm.PrevAppDir
  else if WizardForm.DirEdit.Text <> '' then
    AppDir := WizardForm.DirEdit.Text;
  Result := AddBackslash(AppDir) + '.install_mode';
end;

function ResolveSelectedMode(): String;
var
  ParamMode: String;
  ContextMode: String;
  FileMode: String;
  ModeFile: TStringList;
  ModeFilePath: String;
begin
  ParamMode := NormalizeInstallMode(ExpandConstant('{param:MODE}'));
  if ParamMode <> '' then
  begin
    Result := ParamMode;
    Log('Resolved install mode from /MODE=' + ParamMode);
    Exit;
  end;

  ContextMode := NormalizeInstallMode(ReadUpdateContextAppMode());
  if ContextMode <> '' then
  begin
    Result := ContextMode;
    Log('Resolved install mode from update_context.json: ' + ContextMode);
    Exit;
  end;

  ModeFilePath := GetInstallModeFilePath();
  if FileExists(ModeFilePath) then
  begin
    ModeFile := TStringList.Create;
    try
      ModeFile.LoadFromFile(ModeFilePath);
      if ModeFile.Count > 0 then
        FileMode := NormalizeInstallMode(ModeFile.Strings[0]);
    finally
      ModeFile.Free;
    end;
    if FileMode <> '' then
    begin
      Result := FileMode;
      Log('Resolved install mode from .install_mode: ' + FileMode);
      Exit;
    end;
  end;

  Result := 'server';
  Log('Resolved install mode using default: server');
end;

function IsVCRedistInstalled(): Boolean;
var
  Installed: Cardinal;
begin
  Result := False;
  if RegQueryDWordValue(
    HKEY_LOCAL_MACHINE,
    'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
    'Installed',
    Installed
  ) then
    Result := (Installed = 1);
end;

function IsVCRedistSuccessExitCode(const ExitCode: Integer): Boolean;
begin
  Result :=
    (ExitCode = 0) or
    (ExitCode = 1638) or
    (ExitCode = 3010) or
    (ExitCode = 1641);
end;

function IsAppRunning(const ExeName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  if Exec(
    'cmd.exe',
    '/c tasklist /NH /FI "IMAGENAME eq ' + ExeName +
      '" | findstr /I /C:"' + ExeName + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    Result := (ResultCode = 0);
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

function IsInstalledAppRunning(const AppExePath: String): Boolean;
var
  ResultCode: Integer;
  Command: String;
  ExeName: String;
  QuotedPath: String;
begin
  Result := False;
  ExeName := ExpandConstant('{#MyAppExeName}');
  QuotedPath := AppExePath;
  StringChangeEx(QuotedPath, '''', '''''', True);
  Command :=
    '-NoProfile -ExecutionPolicy Bypass -Command "' +
    '$hit = Get-CimInstance Win32_Process | ' +
    'Where-Object { $_.Name -eq ''' + ExeName +
    ''' -and $_.ExecutablePath -ieq ''' + QuotedPath +
    ''' } | Select-Object -First 1; ' +
    'if ($null -eq $hit) { exit 1 } else { exit 0 }"';
  if Exec(
    'powershell.exe',
    Command,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    Result := (ResultCode = 0)
  else
    Log('Warning: failed to query installed app process for ' + AppExePath);
end;

procedure TaskkillInstalledApp(const AppExePath: String);
var
  ResultCode: Integer;
  Command: String;
  ExeName: String;
  QuotedPath: String;
begin
  ExeName := ExpandConstant('{#MyAppExeName}');
  QuotedPath := AppExePath;
  StringChangeEx(QuotedPath, '''', '''''', True);
  Command :=
    '-NoProfile -ExecutionPolicy Bypass -Command "' +
    'Get-CimInstance Win32_Process | ' +
    'Where-Object { $_.Name -eq ''' + ExeName +
    ''' -and $_.ExecutablePath -ieq ''' + QuotedPath +
    ''' } | ForEach-Object { & taskkill.exe /PID $_.ProcessId /F /T }"';
  Exec(
    'powershell.exe',
    Command,
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
end;

function InitializeSetup(): Boolean;
var
  AppExe: String;
  WaitCount: Integer;
  UpdateContextPath: String;
  StartCode: Integer;
begin
  Result := True;
  VCRedistNeeded := False;
  UpdateContextPath := GetUpdateContextPath();

  if IsServiceInstalled('BackupDatabaseService') then
    StopService('BackupDatabaseService');

  if WizardSilent() and FileExists(UpdateContextPath) then
  begin
    if RunTempPowerShellScript(
      'capture_update_context.ps1',
      '-ContextPath "' + UpdateContextPath + '" -ServiceName "BackupDatabaseService"'
    ) then
      Log('Captured update_context.json before upgrade')
    else
    begin
      Log('Warning: Failed to capture update_context.json before upgrade');
      if IsServiceInstalled('BackupDatabaseService') then
        Exec('sc.exe', 'start BackupDatabaseService', '', SW_HIDE,
          ewWaitUntilTerminated, StartCode);
      Result := False;
      Exit;
    end;
  end;

  // {app} ainda nao e conhecido de forma confiavel em InitializeSetup
  // (o diretorio de instalacao pode mudar no assistente). O fechamento
  // aqui continua por nome de imagem via CloseApp/taskkill /IM.
  // PrepareToInstall, com {app} definido, encerra so o executavel instalado.
  AppExe := ExpandConstant('{#MyAppExeName}');

  if IsAppRunning(AppExe) then
  begin
    if WizardSilent() then
    begin
      CloseApp(AppExe);
      WaitCount := 0;
      while IsAppRunning(AppExe) and (WaitCount < 30) do
      begin
        Sleep(500);
        WaitCount := WaitCount + 1;
      end;
    end
    else
    begin
      if MsgBox(
           ExpandCustomMessage1(
             'AppRunningClosePrompt',
             ExpandConstant('{#MyAppName}')
           ),
           mbConfirmation,
           MB_YESNO
         ) = IDYES then
      begin
        CloseApp(AppExe);

        WaitCount := 0;
        while IsAppRunning(AppExe) and (WaitCount < 30) do
        begin
          Sleep(500);
          WaitCount := WaitCount + 1;
        end;

        if IsAppRunning(AppExe) then
        begin
          if MsgBox(
               ExpandCustomMessage('AppStillRunningContinuePrompt'),
               mbConfirmation,
               MB_YESNO
             ) = IDNO then
          begin
            Result := False;
            Exit;
          end;
        end;
      end
      else
      begin
        Result := False;
        Exit;
      end;
    end;
  end;

  VCRedistNeeded := not IsVCRedistInstalled();
end;

procedure SaveSelectedUiLocale();
var
  LocalePath: String;
  LocaleCode: String;
begin
  LocalePath := ExpandConstant('{commonappdata}\BackupDatabase\config\ui_locale');
  if WizardSilent() and FileExists(LocalePath) then
  begin
    Log('Silent install keeps existing ui_locale');
    Exit;
  end;
  if ActiveLanguage = 'english' then
    LocaleCode := 'en'
  else
    LocaleCode := 'pt';
  ForceDirectories(ExpandConstant('{commonappdata}\BackupDatabase\config'));
  if not SaveStringToFile(LocalePath, LocaleCode, False) then
    Log('Warning: failed to save ui_locale');
end;

procedure InitializeWizard();
begin
  ModePage := CreateInputOptionPage(wpLicense,
    CustomMessage('ModePageTitle'),
    CustomMessage('ModePageSubtitle'),
    CustomMessage('ModePageDescription'),
    True, False);

  ModePage.Add(CustomMessage('ModeServer'));
  ModePage.Add(CustomMessage('ModeClient'));

  SelectedMode := ResolveSelectedMode();
  if SelectedMode = 'client' then
    ModePage.SelectedValueIndex := 1
  else
    ModePage.SelectedValueIndex := 0;

  if VCRedistNeeded then
  begin
    VCRedistPage := CreateOutputProgressPage(
      CustomMessage('VcPageTitle'),
      CustomMessage('VcPageDescription'));
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  VCRedistPath: String;
  VCRedistErrorCode: Integer;
  ExecResult: Boolean;
  AppExePath: String;
  UserChoice: Integer;
begin
  Result := '';

  // Reforco defensivo: NSSM pode ter reiniciado o servico entre
  // InitializeSetup e PrepareToInstall (ex.: usuario passou tempo no
  // wizard). Parar de novo antes de copiar arquivos garante que o .exe
  // sera substituido — atalho da area de trabalho passa a refletir o
  // icone novo no primeiro launch.
  if IsServiceInstalled('BackupDatabaseService') then
    StopService('BackupDatabaseService');

  // {app} ja esta definido. taskkill mira somente esse caminho
  // (ExecutablePath), nao qualquer backup_database.exe da maquina.
  AppExePath := ExpandConstant('{app}\{#MyAppExeName}');
  if IsInstalledAppRunning(AppExePath) then
  begin
    TaskkillInstalledApp(AppExePath);
    Sleep(2000);

    if IsInstalledAppRunning(AppExePath) then
    begin
      TaskkillInstalledApp(AppExePath);
      Sleep(2000);
    end;

    // Se ainda estiver rodando após todas as tentativas, registrar evidência
    // explícita no log do Inno Setup. Em modo silencioso (auto update)
    // abortamos. Em modo interativo pedimos confirmação ao usuário porque
    // continuar com o app aberto costuma deixar o .exe antigo no disco —
    // sintoma classico: atalho desktop continua com icone velho apos
    // instalar versao nova.
    if IsInstalledAppRunning(AppExePath) then
    begin
      Log('WARNING: ' + AppExePath + ' continua em execucao apos taskkill; '
        + 'arquivos abertos podem nao ser substituidos nesta instalacao.');
      if WizardSilent() then
      begin
        Result := ExpandCustomMessage1(
          'AppStillRunningSilent',
          ExpandConstant('{#MyAppName}')
        );
        Exit;
      end
      else
      begin
        UserChoice := MsgBox(
          ExpandCustomMessage1(
            'AppStillRunningRiskPrompt',
            ExpandConstant('{#MyAppName}')
          ),
          mbConfirmation,
          MB_YESNO or MB_DEFBUTTON2
        );
        if UserChoice = IDNO then
        begin
          Result := ExpandCustomMessage1(
            'InstallCancelledAppRunning',
            ExpandConstant('{#MyAppName}')
          );
          Exit;
        end;
        Log('WARNING: usuario optou por continuar com ' + AppExePath + ' aberto; '
          + 'icone do atalho pode permanecer desatualizado ate o proximo logon.');
      end;
    end;
  end;

  if VCRedistNeeded then
  begin
    VCRedistPage.SetText(CustomMessage('VcProgress'), CustomMessage('VcWait'));
    VCRedistPage.SetProgress(0, 0);
    VCRedistPage.Show;

    VCRedistPath := ExpandConstant('{tmp}\vc_redist.x64.exe');

    if not FileExists(VCRedistPath) then
    begin
      Result := ExpandCustomMessage('VcRedistMissing');
      VCRedistPage.Hide;
      Exit;
    end;

    ExecResult := Exec(VCRedistPath, '/quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, VCRedistErrorCode);

    if not ExecResult or not IsVCRedistSuccessExitCode(VCRedistErrorCode) then
    begin
      Result := ExpandCustomMessage1('VcRedistFailed', IntToStr(VCRedistErrorCode));
      VCRedistPage.Hide;
      Exit;
    end;

    if (VCRedistErrorCode = 3010) or (VCRedistErrorCode = 1641) then
    begin
      NeedsRestart := True;
      Log(
        'VC++ redistributable exit ' + IntToStr(VCRedistErrorCode) +
        ' requires restart'
      );
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
  MergeExitCode: Integer;
  RestoreExitCode: Integer;
begin
  // ssInstall corre antes de [Icons]. Apaga atalhos antigos da area de
  // trabalho mesmo quando a task desktopicon nao esta marcada, e os nomes
  // em ingles do Menu Iniciar antes do Inno recriar os atalhos do idioma.
  if CurStep = ssInstall then
  begin
    RemoveExistingDesktopShortcut();
    RemoveLegacyEnglishStartMenuShortcuts();
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
    //   2 = chaves criticas ausentes apos merge (AUTO_UPDATE_FEED_URL)
    //   outro = falha generica
    if RunTempPowerShellScriptEx(
      'merge_env.ps1',
      '-ExamplePath "' + EnvExamplePath + '" ' +
      '-TargetPath "' + EnvPath + '" ' +
      '-LegacyPath "' + LegacyEnvPath + '" ' +
      '-BackupPath "' + MigratedBackupPath + '"',
      MergeExitCode
    ) then
    begin
      if MergeExitCode = 0 then
        Log('Merged machine-scope .env with .env.example')
      else if MergeExitCode = 2 then
      begin
        Log(
          'Warning: merge_env.ps1 exit 2 — chave critica ausente ' +
          '(AUTO_UPDATE_FEED_URL); auto-update ficara desabilitado ate ' +
          'corrigir ' + EnvPath
        );
        if WizardSilent() then
          Log('Warning: instalacao silenciosa segue apos merge_env.ps1 exit 2')
        else
          MsgBox(
            ExpandCustomMessage1('EnvFeedUrlMissing', EnvPath),
            mbError,
            MB_OK
          );
      end
      else
        Log('Warning: merge_env.ps1 failed, exit=' + IntToStr(MergeExitCode));
    end
    else
      Log('Warning: failed to launch merge_env.ps1 from installer');

    if SelectedMode = '' then
      SelectedMode := ResolveSelectedMode();
    ModeFilePath := ExpandConstant('{app}\.install_mode');
    ModeFile := TStringList.Create;
    try
      ModeFile.Add(SelectedMode);
      ModeFile.SaveToFile(ModeFilePath);
    finally
      ModeFile.Free;
    end;

    SaveSelectedUiLocale();

    RemoveLegacyStartupEntries();

    if WizardSilent() and FileExists(UpdateContextPath) then
      Log(
        'Silent update: skipping startup task/service install; ' +
        'restore_update_state owns operational state'
      )
    else if WizardIsTaskSelected('startup') then
    begin
      if SelectedMode = 'server' then
        InstallAndStartServiceFromInstaller(AppExePath, ExpandConstant('{app}'), NssmPath)
      else
        ConfigureClientStartupTask(AppExePath);
    end
    else
      DeleteClientStartupTask();

    if not (WizardSilent() and FileExists(UpdateContextPath)) then
    begin
      if SelectedMode = 'server' then
      begin
        DeleteClientStartupTask();
        if (not WizardIsTaskSelected('startup')) and
           IsServiceInstalled('BackupDatabaseService') then
          Exec('sc.exe', 'start BackupDatabaseService', '', SW_HIDE,
            ewWaitUntilTerminated, RestoreExitCode);
      end
      else if IsServiceInstalled('BackupDatabaseService') then
        Exec(
          'sc.exe',
          'config BackupDatabaseService start= disabled',
          '',
          SW_HIDE,
          ewWaitUntilTerminated,
          RestoreExitCode
        );
    end;

    if (SelectedMode = 'server') and WizardIsTaskSelected('openfirewall') then
      ConfigureRemoteSocketFirewall()
    else
      DeleteRemoteSocketFirewall();

    if WizardSilent() and FileExists(UpdateContextPath) then
    begin
      if RunTempPowerShellScriptEx(
        'restore_update_state.ps1',
        '-ContextPath "' + UpdateContextPath + '" ' +
        '-AppPath "' + AppExePath + '" ' +
        '-AppDirectory "' + ExpandConstant('{app}') + '" ' +
        '-NssmPath "' + NssmPath + '" ' +
        '-ServiceName "BackupDatabaseService"',
        RestoreExitCode
      ) then
      begin
        if RestoreExitCode = 0 then
          Log('Restored update operational state from update_context.json')
        else if RestoreExitCode = 2 then
          Log(
            'Warning: restore_update_state.ps1 exit 2 — servico restaurado ' +
            'mas RUNNING nao confirmado no timeout de polling; ' +
            'update_context.json preservado para retry'
          )
        else
          Log(
            'Warning: restore_update_state.ps1 failed, exit=' +
            IntToStr(RestoreExitCode)
          );
      end
      else
        Log('Warning: failed to launch restore_update_state.ps1 from installer');
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

function ShouldRemoveMachineConfig(): Boolean;
begin
  Result := RemoveMachineConfig;
end;

procedure ConfigureRemoteSocketFirewall();
var
  ResultCode: Integer;
begin
  Exec(
    'netsh.exe',
    'advfirewall firewall delete rule name="Backup Database Remote Socket"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
  if Exec(
    'netsh.exe',
    'advfirewall firewall add rule name="Backup Database Remote Socket" dir=in action=allow protocol=TCP localport=9527 profile=any',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
  begin
    if ResultCode = 0 then
      Log('Firewall rule added for TCP 9527 (Backup Database Remote Socket)')
    else
      Log('Warning: failed to add firewall rule for TCP 9527, exit=' + IntToStr(ResultCode));
  end
  else
    Log('Warning: failed to launch netsh to add firewall rule for TCP 9527');
end;

procedure DeleteRemoteSocketFirewall();
var
  ResultCode: Integer;
begin
  Exec(
    'netsh.exe',
    'advfirewall firewall delete rule name="Backup Database Remote Socket"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  );
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
      MsgBox(
        ExpandCustomMessage1('ServiceScriptMissing', ScriptPath),
        mbError,
        MB_OK
      );
    Exit;
  end;
  if not FileExists(NssmPath) then
  begin
    Log('ERROR: nssm.exe ausente em ' + NssmPath
      + '; servico nao sera registrado.');
    if not WizardSilent() then
      MsgBox(
        ExpandCustomMessage1('NssmMissing', NssmPath),
        mbError,
        MB_OK
      );
    Exit;
  end;

  Args :=
    '-NoProfile -ExecutionPolicy Bypass -File "' + ScriptPath + '" ' +
    '-NonInteractive ' +
    '-StartAfterInstall ' +
    '-AppPath "' + AppExePath + '" ' +
    '-AppDirectory "' + AppDirectory + '" ' +
    '-NssmPath "' + NssmPath + '"';
  if Exec('powershell.exe', Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
      Log('BackupDatabaseService installed and RUNNING confirmed')
    else if ResultCode = 2 then
    begin
      Log('Warning: BackupDatabaseService installed but did not reach RUNNING within polling timeout');
      if not WizardSilent() then
        MsgBox(ExpandCustomMessage('ServiceNotRunning'), mbError, MB_OK);
    end
    else
    begin
      Log('Warning: install_service.ps1 failed, exit=' + IntToStr(ResultCode));
      if not WizardSilent() then
        MsgBox(
          ExpandCustomMessage1('ServiceInstallFailed', IntToStr(ResultCode)),
          mbError,
          MB_OK
        );
    end;
  end
  else
  begin
    Log('Warning: failed to launch install_service.ps1 from installer');
    if not WizardSilent() then
      MsgBox(ExpandCustomMessage('ServiceScriptLaunchFailed'), mbError, MB_OK);
  end;
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
begin
  Result := False;
  if not IsServiceInstalled(ServiceName) then
  begin
    Result := True;
    Exit;
  end;

  Exec('sc.exe', 'stop ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  WaitForServiceStopped(ServiceName);

  Exec('sc.exe', 'delete ' + ServiceName, '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Result := WaitForServiceRemoved(ServiceName);
  if not Result then
    Result := not IsServiceInstalled(ServiceName);
end;

function WaitForServiceStopped(const ServiceName: String): Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
  Args: String;
begin
  Result := False;
  ExtractTemporaryFile('service_utils.ps1');
  ScriptPath := ExpandConstant('{tmp}\service_utils.ps1');
  Args :=
    '-NoProfile -ExecutionPolicy Bypass -Command ". ''' + ScriptPath +
    '''; if (Wait-ServiceStopped -ServiceName ''' + ServiceName +
    ''') { exit 0 } else { exit 1 }"';
  if Exec('powershell.exe', Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
    begin
      Log('Service ' + ServiceName + ' STOPPED confirmed');
      Result := True;
    end
    else
      Log(
        'Warning: Service ' + ServiceName +
        ' did not reach STOPPED within polling timeout'
      );
  end
  else
    Log('Warning: failed to launch Wait-ServiceStopped for ' + ServiceName);
end;

function WaitForServiceRemoved(const ServiceName: String): Boolean;
var
  ResultCode: Integer;
  ScriptPath: String;
  Args: String;
begin
  Result := False;
  ExtractTemporaryFile('service_utils.ps1');
  ScriptPath := ExpandConstant('{tmp}\service_utils.ps1');
  Args :=
    '-NoProfile -ExecutionPolicy Bypass -Command ". ''' + ScriptPath +
    '''; if (Wait-ServiceRemoved -ServiceName ''' + ServiceName +
    ''') { exit 0 } else { exit 1 }"';
  if Exec('powershell.exe', Args, '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
  begin
    if ResultCode = 0 then
    begin
      Log('Service ' + ServiceName + ' removed from SCM');
      Result := True;
    end
    else
      Log(
        'Warning: Service ' + ServiceName +
        ' still marked for deletion within polling timeout'
      );
  end
  else
    Log('Warning: failed to launch Wait-ServiceRemoved for ' + ServiceName);
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
    
    if (ResultCode = 0) or (ResultCode = 1062) then
    begin
      Result := WaitForServiceStopped(ServiceName);
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
  RemoveMachineConfig := False;
  AppExe := ExpandConstant('{#MyAppExeName}');
  ServiceName := 'BackupDatabaseService';

  if IsServiceInstalled(ServiceName) then
    StopService(ServiceName);

  if IsAppRunning(AppExe) then
  begin
    if UninstallSilent then
    begin
      CloseApp(AppExe);
      if IsAppRunning(AppExe) then
      begin
        Log('Uninstall silent: ' + AppExe + ' still running after CloseApp');
        Result := False;
      end;
    end
    else if MsgBox(
              ExpandCustomMessage1(
                'AppRunningUninstallPrompt',
                ExpandConstant('{#MyAppName}')
              ),
              mbConfirmation,
              MB_YESNO
            ) = IDYES then
    begin
      if not CloseApp(AppExe) then
      begin
        MsgBox(ExpandCustomMessage('AppCloseFailed'), mbError, MB_OK);
        Result := False;
      end
      else
      begin
        Sleep(1000);
        if IsAppRunning(AppExe) then
        begin
          MsgBox(ExpandCustomMessage('AppStillRunningUninstall'), mbError, MB_OK);
          Result := False;
        end;
      end;
    end
    else
      Result := False;
  end;

  if Result and (not UninstallSilent) then
  begin
    if MsgBox(
         ExpandCustomMessage1(
           'UninstallRemoveConfig',
           ExpandConstant('{commonappdata}\BackupDatabase')
         ),
         mbConfirmation,
         MB_YESNO or MB_DEFBUTTON2
       ) = IDYES then
      RemoveMachineConfig := True;
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
      RemoveService(ServiceName);

    DeleteClientStartupTask();
    DeleteRemoteSocketFirewall();
  end;
end;
