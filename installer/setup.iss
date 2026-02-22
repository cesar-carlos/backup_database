#define MyAppName "Backup Database"
#define MyAppVersion "2.2.2"
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
MinVersion=6.3
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop icon"; GroupDescription: "Additional Icons"
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "Opcoes de Inicializacao"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{app}"; Flags: ignoreversion; DestName: ".env.example"
Source: "..\docs\install\installation_guide.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\path_setup.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "check_dependencies.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\nssm-2.24\win64\nssm.exe"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "dependencies\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "install_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion
Source: "uninstall_service.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion

[Icons]
; Main icons for each mode (all will be created)
Name: "{group}\{#MyAppName} - Server Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; Comment: "Run Backup Database as Server"
Name: "{group}\{#MyAppName} - Client Mode"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=client"; Comment: "Run Backup Database as Client"
; Utility icons
Name: "{group}\Verificar DependÃªncias"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
; Service icons (ONLY for Server mode)
Name: "{group}\Instalar como ServiÃ§o do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\install_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\Remover ServiÃ§o do Windows"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\uninstall_service.ps1"""; IconFilename: "{app}\{#MyAppExeName}"; Check: IsServerMode
Name: "{group}\DocumentaÃ§Ã£o"; Filename: "{app}\docs\installation_guide.md"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
; Desktop icon (default to server)
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--mode=server"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Parameters: "--mode=server"; Flags: nowait postinstall skipifsilent

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#MyAppName}"; ValueData: """{app}\{#MyAppExeName}"" --minimized"; Flags: uninsdeletevalue; Tasks: startup

[UninstallDelete]
Name: "{commonappdata}\BackupDatabase\logs"; Type: filesandordirs

[Code]
var
  VCRedistPage: TOutputProgressWizardPage;
  VCRedistNeeded: Boolean;
  ModePage: TInputOptionWizardPage;
  SelectedMode: String;

function IsServiceInstalled(const ServiceName: String): Boolean; forward;
function StopService(const ServiceName: String): Boolean; forward;

// FunÃ§Ã£o auxiliar para encontrar o desinstalador em mÃºltiplos caminhos
function FindUninstaller(): String;
var
  Paths: array of String;
  I: Integer;
  RegPath: String;
  SecondQuotePos: Integer;
begin
  // Lista de caminhos para verificar (em ordem de probabilidade)
  Paths := [
    ExpandConstant('C:\Program Files\{#MyAppName}\unins000.exe'),
    ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins000.exe'),
    ExpandConstant('{pf}\{#MyAppName}\unins000.exe'),
    ExpandConstant('{autopf}\{#MyAppName}\unins000.exe')
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
    // Extrair apenas o caminho do executÃ¡vel (remover parÃ¢metros se houver)
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

  // NÃ£o encontrado
  Result := '';
end;

function IsAppRunning(const ExeName: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := False;
  // Usar findstr para verificar se o processo estÃ¡ na lista
  // findstr retorna 0 se encontrar, 1 se nÃ£o encontrar
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
  
  // Se ainda estiver rodando, tentar forÃ§ar o fechamento
  while IsAppRunning(ExeName) and (Retries < MaxRetries) do
  begin
    Exec('taskkill.exe', '/IM ' + ExeName + ' /F /T', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
    Sleep(1000);
    Retries := Retries + 1;
    
    // Verificar se foi fechado apÃ³s cada tentativa
    if not IsAppRunning(ExeName) then
    begin
      Result := True;
      Exit;
    end;
  end;
  
  // VerificaÃ§Ã£o final
  Result := not IsAppRunning(ExeName);
end;

function InitializeSetup(): Boolean;
var
  AppExe: String;
  WaitCount: Integer;
  UninstallExe: String;
  UninstallPath: String;
  ResultCode: Integer;
  SecondQuotePos: Integer;
begin
  Result := True;
  VCRedistNeeded := False;

  // Parar o serviÃ§o do Windows primeiro para liberar nssm.exe e a pasta de instalaÃ§Ã£o
  if IsServiceInstalled('BackupDatabaseService') then
  begin
    StopService('BackupDatabaseService');
    Sleep(2000);
  end;

  // Fechar nssm.exe se estiver em uso (ex.: script "Instalar como ServiÃ§o" ainda aberto)
  if IsAppRunning('nssm.exe') then
  begin
    CloseApp('nssm.exe');
    Sleep(1500);
  end;
  
  // Verificar se existe uma instalaÃ§Ã£o anterior e executar desinstalaÃ§Ã£o silenciosa
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

    // Executar desinstalaÃ§Ã£o MUITO silenciosa da versÃ£o anterior
    // /VERYSILENT Ã© mais agressivo que /SILENT - nÃ£o mostra nada
    Exec(UninstallPath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);

    // Aguardar atÃ© que o processo de desinstalaÃ§Ã£o termine completamente
    // Verificar se o arquivo de desinstalaÃ§Ã£o ainda existe (indica que ainda estÃ¡ em processo)
    WaitCount := 0;
    while FileExists(UninstallPath) and (WaitCount < 30) do
    begin
      Sleep(500);
      WaitCount := WaitCount + 1;
    end;

    // Aguardar um pouco mais para garantir que todos os processos foram finalizados
    Sleep(2000);

    // Verificar se ainda hÃ¡ processos relacionados rodando
    if IsAppRunning(AppExe) then
    begin
      CloseApp(AppExe);
      Sleep(1000);
    end;
  end;
  
  // Fechar processos de desinstalaÃ§Ã£o se estiverem rodando
  UninstallExe := 'unins000.exe';
  if IsAppRunning(UninstallExe) then
  begin
    CloseApp(UninstallExe);
    Sleep(2000);
  end;
  
  // Verificar se o aplicativo estÃ¡ em execuÃ§Ã£o
  AppExe := ExpandConstant('{#MyAppExeName}');
  
  if IsAppRunning(AppExe) then
  begin
    // Se estiver em modo silencioso (atualizaÃ§Ã£o automÃ¡tica), fechar sem perguntar
    if WizardSilent() then
    begin
      // Modo silencioso: fechar automaticamente sem perguntar
      CloseApp(AppExe);
      
      // Aguardar atÃ© que o processo seja completamente finalizado
      WaitCount := 0;
      while IsAppRunning(AppExe) and (WaitCount < 30) do
      begin
        Sleep(500);
        WaitCount := WaitCount + 1;
      end;
    end
    else
    begin
      // Modo interativo: perguntar ao usuÃ¡rio
      if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' estÃ¡ em execuÃ§Ã£o.' + #13#10 + #13#10 +
                'Ã‰ necessÃ¡rio fechar o aplicativo para continuar com a instalaÃ§Ã£o.' + #13#10 + #13#10 +
                'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
      begin
        // Tentar fechar o aplicativo
        CloseApp(AppExe);
        
        // Aguardar atÃ© que o processo seja completamente finalizado
        WaitCount := 0;
        while IsAppRunning(AppExe) and (WaitCount < 30) do
        begin
          Sleep(500);
          WaitCount := WaitCount + 1;
        end;
        
        // Se ainda estiver rodando apÃ³s todas as tentativas, avisar mas continuar
        if IsAppRunning(AppExe) then
        begin
          if MsgBox('O aplicativo ainda parece estar em execuÃ§Ã£o apÃ³s tentativas de fechamento.' + #13#10 + #13#10 +
                    'A instalaÃ§Ã£o pode falhar se o aplicativo nÃ£o for fechado.' + #13#10 + #13#10 +
                    'Deseja continuar mesmo assim?', mbConfirmation, MB_YESNO) = IDNO then
          begin
            Result := False;
            Exit;
          end;
        end;
        
        // Se chegou aqui, o aplicativo foi fechado ou o usuÃ¡rio escolheu continuar
        // Continuar com a instalaÃ§Ã£o
      end
      else
      begin
        // UsuÃ¡rio escolheu nÃ£o fechar - nÃ£o pode continuar
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
begin
  Result := '';
  
  // Verificar novamente se o aplicativo estÃ¡ rodando antes de instalar
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
    
    // Se ainda estiver rodando apÃ³s todas as tentativas, apenas avisar
    // mas tentar continuar (alguns arquivos podem ser substituÃ­dos mesmo assim)
    if IsAppRunning(AppExe) then
    begin
      // NÃ£o bloquear completamente - apenas avisar
      // O Windows pode conseguir substituir alguns arquivos mesmo com o processo rodando
      // Result := 'O aplicativo ' + ExpandConstant('{#MyAppName}') + ' ainda estÃ¡ em execuÃ§Ã£o. Alguns arquivos podem nÃ£o ser atualizados.';
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
      Result := 'Visual C++ Redistributables nÃ£o encontrado. Por favor, baixe e instale manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe';
      VCRedistPage.Hide;
      Exit;
    end;
    
    ExecResult := Exec(VCRedistPath, '/quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, VCRedistErrorCode);
    
    if not ExecResult or (VCRedistErrorCode <> 0) then
    begin
      Result := 'Erro ao instalar Visual C++ Redistributables. CÃ³digo de erro: ' + IntToStr(VCRedistErrorCode);
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
begin
  // Write .install_mode only after files are installed, when {app} is defined
  if CurStep = ssPostInstall then
  begin
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
  end;
end;

// Check if server mode was selected (used to conditionally create service icons)
function IsServerMode(): Boolean;
begin
  Result := (SelectedMode = 'server');
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
  
  // Parar o serviÃ§o do Windows ANTES de qualquer outra aÃ§Ã£o
  if IsServiceInstalled(ServiceName) then
  begin
    StopService(ServiceName);
    Sleep(2000);
  end;
  
  // Verificar se o aplicativo estÃ¡ em execuÃ§Ã£o durante a desinstalaÃ§Ã£o
  if IsAppRunning(AppExe) then
  begin
    if MsgBox('O aplicativo ' + ExpandConstant('{#MyAppName}') + ' estÃ¡ em execuÃ§Ã£o.' + #13#10 + #13#10 +
              'Ã‰ necessÃ¡rio fechar o aplicativo para continuar com a desinstalaÃ§Ã£o.' + #13#10 + #13#10 +
              'Deseja fechar o aplicativo agora?', mbConfirmation, MB_YESNO) = IDYES then
    begin
      if not CloseApp(AppExe) then
      begin
        MsgBox('NÃ£o foi possÃ­vel fechar o aplicativo automaticamente.' + #13#10 + #13#10 +
               'Por favor, feche o aplicativo manualmente e tente novamente.', mbError, MB_OK);
        Result := False;
        Exit;
      end;
      
      // Aguardar um pouco mais para garantir que o processo foi finalizado
      Sleep(1000);
      
      if IsAppRunning(AppExe) then
      begin
        MsgBox('O aplicativo ainda estÃ¡ em execuÃ§Ã£o.' + #13#10 + #13#10 +
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

