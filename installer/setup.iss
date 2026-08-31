#define MyAppName "Backup Database"
#define MyAppVersion "3.6.0"
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

[Tasks]
; Inno Setup: tasks vem checadas por default. Para desmarcar inicialmente
; use `Flags: unchecked`. Nao existe `Flags: checked` (foi um erro do
; commit ee94182 que so foi detectado no build 3.4.0).
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional Icons"
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opções de Inicialização"
Name: "openfirewall"; Description: "Liberar porta TCP 9527 no Firewall do Windows (clientes remotos)"; GroupDescription: "Rede"; Flags: unchecked; Check: IsServerMode

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
Name: "{group}\{#MyAppName} - Server Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; Comment: "Run Backup Database as Server"; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\{#MyAppName} - Client Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; Comment: "Run Backup Database as Client"; IconFilename: "{app}\{#MyAppExeName}"
; Utility icons
Name: "{group}\Verificar Dependências"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
; Service icons (ONLY for Server mode)
Name: "{group}\Instalar como Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\install_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Remover Serviço do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\uninstall_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Documentação"; Filename: "{app}\docs\installation_guide.md"
Name: "{group}\Troubleshooting do Serviço"; Filename: "{app}\docs\TROUBLESHOOTING_SERVICE.md"
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
procedure DeleteClientStartupTask(); forward;
procedure ConfigureClientStartupTask(const AppExePath: String); forward;
procedure InstallAndStartServiceFromInstaller(const AppExePath, AppDirectory, NssmPath: String); forward;
procedure RefreshWindowsIconCache(); forward;
procedure RemoveExistingDesktopShortcut(); forward;
procedure TouchDesktopShortcut(); forward;
procedure ConfigureRemoteSocketFirewall(); forward;
procedure DeleteRemoteSocketFirewall(); forward;

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

  ModeFilePath := ExpandConstant('{app}\.install_mode');
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

function InitializeSetup(): Boolean;
var
  AppExe: String;
  WaitCount: Integer;
  UpdateContextPath: String;
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
      Log('Warning: Failed to capture update_context.json before upgrade');
  end;

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
      if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' está em execução.' + #13#10 + #13#10 +
                'É necessário fechar o aplicativo para continuar com a instalação.' + #13#10 + #13#10 +
                'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
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
          if MsgBox('O aplicativo ainda parece estar em execução após tentativas de fechamento.' + #13#10 + #13#10 +
                    'A instalação pode falhar se o aplicativo não for fechado.' + #13#10 + #13#10 +
                    'Deseja continuar mesmo assim?', mbConfirmation, MB_YESNO) = IDNO then
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

procedure InitializeWizard();
begin
  ModePage := CreateInputOptionPage(wpLicense,
    'Select Installation Mode',
    'Choose how you want to use Backup Database',
    'Select the installation mode that best fits your needs:',
    True, False);

  ModePage.Add('(Recommended) Server Mode - Run as a dedicated backup server (allows remote connections)');
  ModePage.Add('Client Mode - Connect to a remote server and manage backups remotely');

  SelectedMode := ResolveSelectedMode();
  if SelectedMode = 'client' then
    ModePage.SelectedValueIndex := 1
  else
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
    StopService('BackupDatabaseService');

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
    
    ExecResult := Exec(VCRedistPath, '/quiet /norestart', '', SW_HIDE, ewWaitUntilTerminated, VCRedistErrorCode);

    if not ExecResult or not IsVCRedistSuccessExitCode(VCRedistErrorCode) then
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
  MergeExitCode: Integer;
  RestoreExitCode: Integer;
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
            'A chave AUTO_UPDATE_FEED_URL nao ficou preenchida em:' + #13#10 +
            EnvPath + #13#10#13#10 +
            'A instalacao continua, mas o auto-update ficara desabilitado ' +
            'ate corrigir o arquivo .env.',
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

    if WizardIsTaskSelected('openfirewall') then
      ConfigureRemoteSocketFirewall();

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
        MsgBox('O servico foi instalado, mas nao confirmou RUNNING no tempo de espera.'
          + #13#10 + #13#10
          + 'Verifique o status em Servicos do Windows ou reinstale o servico pelo aplicativo.',
          mbError, MB_OK);
    end
    else
    begin
      Log('Warning: install_service.ps1 failed, exit=' + IntToStr(ResultCode));
      if not WizardSilent() then
        MsgBox('Falha ao instalar o servico do Windows (codigo '
          + IntToStr(ResultCode) + ').'
          + #13#10 + #13#10
          + 'Consulte o log do instalador e tente novamente.',
          mbError, MB_OK);
    end;
  end
  else
  begin
    Log('Warning: failed to launch install_service.ps1 from installer');
    if not WizardSilent() then
      MsgBox('Nao foi possivel executar o script de instalacao do servico.',
        mbError, MB_OK);
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
    else if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' está em execução.' + #13#10 + #13#10 +
              'É necessário fechar o aplicativo para continuar com a desinstalação.' + #13#10 + #13#10 +
              'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      if not CloseApp(AppExe) then
      begin
        MsgBox('Não foi possível fechar o aplicativo automaticamente.' + #13#10 + #13#10 +
               'Por favor, feche o aplicativo manualmente e tente novamente.', mbError, MB_OK);
        Result := False;
      end
      else
      begin
        Sleep(1000);
        if IsAppRunning(AppExe) then
        begin
          MsgBox('O aplicativo ainda está em execução.' + #13#10 + #13#10 +
                 'Por favor, feche o aplicativo manualmente e tente novamente.', mbError, MB_OK);
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
         'Deseja tambem remover a configuracao da maquina em ' +
         ExpandConstant('{commonappdata}\BackupDatabase') +
         ' (incluindo .env, staging e locks)?' + #13#10#13#10 +
         'Escolha Nao para preservar a configuracao para uma reinstalacao.',
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
