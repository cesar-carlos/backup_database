#define MyAppName "Backup Database"
#define MyAppVersion "2.0.0"
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
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "OpÃƒÂ§ÃƒÂµes de InicializaÃƒÂ§ÃƒÂ£o"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\LICENSE"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\.env.example"; DestDir: "{app}"; Flags: ignoreversion; DestName: ".env.example"
Source: "..\docs\installation_guide.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "..\docs\path_setup.md"; DestDir: "{app}\docs"; Flags: ignoreversion
Source: "check_dependencies.ps1"; DestDir: "{app}\tools"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Verificar DependÃƒÂªncias"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\DocumentaÃƒÂ§ÃƒÂ£o"; Filename: "{app}\docs\installation_guide.md"
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
  
  // Verificar se existe uma instalaÃ§Ã£o anterior e executar desinstalaÃ§Ã£o silenciosa
  // Tentar mÃºltiplos caminhos possÃ­veis (na ordem mais provÃ¡vel primeiro)
  UninstallPath := ExpandConstant('C:\Program Files\{#MyAppName}\unins000.exe');
  if not FileExists(UninstallPath) then
  begin
    UninstallPath := ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins000.exe');
  end;
  if not FileExists(UninstallPath) then
  begin
    UninstallPath := ExpandConstant('{pf}\{#MyAppName}\unins000.exe');
  end;
  if not FileExists(UninstallPath) then
  begin
    UninstallPath := ExpandConstant('{autopf}\{#MyAppName}\unins000.exe');
  end;
  
  // Fechar o aplicativo se estiver rodando antes de desinstalar
  AppExe := ExpandConstant('{#MyAppExeName}');
  if IsAppRunning(AppExe) then
  begin
    CloseApp(AppExe);
    Sleep(2000);
  end;
  
  // Tentar executar desinstalaÃ§Ã£o se o arquivo existir
  if FileExists(UninstallPath) then
  begin
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
  end
  else
  begin
    // Se nÃ£o encontrou o arquivo, tentar executar diretamente nos caminhos mais comuns
    // mesmo sem verificar existÃªncia (pode ser que a verificaÃ§Ã£o esteja falhando)
     UninstallPath := ExpandConstant('C:\Program Files\{#MyAppName}\unins000.exe');
     if Exec(UninstallPath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
     begin
       Sleep(2000);
     end
     else
     begin
       UninstallPath := ExpandConstant('C:\Program Files (x86)\{#MyAppName}\unins000.exe');
       if Exec(UninstallPath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
       begin
         Sleep(2000);
       end
       else
       begin
         // Se nÃ£o encontrou pelo caminho, tentar procurar pelo registro do Windows
         // Verificar se hÃ¡ uma chave de registro indicando instalaÃ§Ã£o anterior
         if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D_is1', 'UninstallString', UninstallPath) then
         begin
           // Extrair apenas o caminho do executÃ¡vel (remover parÃ¢metros se houver)
           // Se comeÃ§ar com aspas, remover as aspas e pegar atÃ© o prÃ³ximo espaÃ§o ou fim
           if Pos('"', UninstallPath) = 1 then
           begin
             // Remover primeira aspas
             UninstallPath := Copy(UninstallPath, 2, Length(UninstallPath) - 1);
             // Encontrar a prÃ³xima aspas
             SecondQuotePos := Pos('"', UninstallPath);
             if SecondQuotePos > 0 then
             begin
               // Extrair atÃ© a segunda aspas
               UninstallPath := Copy(UninstallPath, 1, SecondQuotePos - 1);
             end;
           end;
           
           if FileExists(UninstallPath) then
           begin
             Exec(UninstallPath, '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
             Sleep(2000);
           end;
         end;
       end;
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
  if VCRedistNeeded then
  begin
    VCRedistPage := CreateOutputProgressPage('Verificando DependÃƒÂªncias', 'Instalando Visual C++ Redistributables...');
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
      Result := 'Visual C++ Redistributables nÃƒÂ£o encontrado. Por favor, baixe e instale manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe';
      VCRedistPage.Hide;
      Exit;
    end;
    
    ExecResult := Exec(VCRedistPath, '/quiet /norestart', '', SW_SHOW, ewWaitUntilTerminated, VCRedistErrorCode);
    
    if not ExecResult or (VCRedistErrorCode <> 0) then
    begin
      Result := 'Erro ao instalar Visual C++ Redistributables. CÃƒÂ³digo de erro: ' + IntToStr(VCRedistErrorCode);
      VCRedistPage.Hide;
      Exit;
    end;
    
    VCRedistPage.Hide;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
end;

function InitializeUninstall(): Boolean;
var
  AppExe: String;
begin
  Result := True;
  AppExe := ExpandConstant('{#MyAppExeName}');
  
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

