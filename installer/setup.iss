#define MyAppName "Backup Database"
#define MyAppVersion "1.0.1+2"
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
LicenseFile=..\LICENSE
OutputDir=dist
OutputBaseFilename=BackupDatabase-Setup-{#MyAppVersion}
SetupIconFile=..\assets\icons\favicon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64
ArchitecturesAllowed=x64
MinVersion=10.0

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opções de Inicialização"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{app}"; Flags: ignoreversion; DestName: ".env.example"
Source: "..\docs\installation_guide.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\requirements.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\path_setup.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "check_dependencies.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Verificar Dependências"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\Documentação"; Filename: "{app}\docs\installation_guide.md"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Internet Explorer\Quick Launch\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: quicklaunchicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"" --minimized"; Flags: uninsdeletevalue; Tasks: startup

[Code]
var
  VCRedistPage: TOutputProgressWizardPage;
  VCRedistNeeded: Boolean;

function InitializeSetup(): Boolean;
begin
  Result := True;
  VCRedistNeeded := False;
  
  if not RegKeyExists(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64') then
  begin
    VCRedistNeeded := True;
  end;
end;

procedure InitializeWizard();
begin
  if VCRedistNeeded then
  begin
    VCRedistPage := CreateOutputProgressPage('Verificando Dependências', 'Instalando Visual C++ Redistributables...');
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  VCRedistPath: String;
  VCRedistErrorCode: Integer;
  ExecResult: Boolean;
begin
  Result := '';
  
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
var
  SqlCmdFound, SybaseFound: Boolean;
  ResultCode: Integer;
  MissingDeps: String;
begin
  Result := True;
  
  if CurPageID = wpReady then
  begin
    SqlCmdFound := False;
    SybaseFound := False;
    
    if Exec('cmd.exe', '/c sqlcmd -?', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      if ResultCode = 0 then
        SqlCmdFound := True;
    end;
    
    if Exec('cmd.exe', '/c dbbackup -?', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    begin
      if ResultCode = 0 then
        SybaseFound := True;
    end;
    
    if not SqlCmdFound or not SybaseFound then
    begin
      MissingDeps := 'ATENÇÃO: Algumas dependências não foram encontradas no sistema:' + #13#10 + #13#10;
      
      if not SqlCmdFound then
        MissingDeps := MissingDeps + '- sqlcmd.exe (SQL Server Command Line Tools)' + #13#10;
      
      if not SybaseFound then
        MissingDeps := MissingDeps + '- dbbackup.exe (Sybase SQL Anywhere)' + #13#10;
      
      MissingDeps := MissingDeps + #13#10 +
        'O aplicativo pode não funcionar corretamente sem essas ferramentas.' + #13#10 + #13#10 +
        'Deseja continuar com a instalação mesmo assim?';
      
      if MsgBox(MissingDeps, mbConfirmation, MB_YESNO) = IDNO then
      begin
        Result := False;
      end;
    end;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
end;

