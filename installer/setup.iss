#define MyAppName "Backup Database"
#define MyAppVersion "1.0.14"
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
CloseApplications=yes
CloseApplicationsFilter=*.exe

[Languages]
Name: "portuguese"; MessagesFile: "compiler:Languages\Portuguese.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "quicklaunchicon"; Description: "{cm:CreateQuickLaunchIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked; OnlyBelowVersion: 6.1
Name: "startup"; Description: "Iniciar com o Windows"; GroupDescription: "OpÃ§Ãµes de InicializaÃ§Ã£o"; Flags: unchecked

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
Name: "{group}\Verificar DependÃªncias"; Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -File ""{app}\tools\check_dependencies.ps1"""; IconFilename: "{app}\{#MyAppExeName}"
Name: "{group}\DocumentaÃ§Ã£o"; Filename: "{app}\docs\installation_guide.md"
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
  ResultCode: Integer;
  SecondQuotePos: Integer;
begin
  Result := True;
  VCRedistNeeded := False;
  
  // Verificar se existe uma instalação anterior e executar desinstalação silenciosa
  // Tentar múltiplos caminhos possíveis (na ordem mais provável primeiro)
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
  
  // Tentar executar desinstalação se o arquivo existir
  if FileExists(UninstallPath) then
  begin
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
  end
  else
  begin
    // Se não encontrou o arquivo, tentar executar diretamente nos caminhos mais comuns
    // mesmo sem verificar existência (pode ser que a verificação esteja falhando)
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
         // Se não encontrou pelo caminho, tentar procurar pelo registro do Windows
         // Verificar se há uma chave de registro indicando instalação anterior
         if RegQueryStringValue(HKEY_LOCAL_MACHINE, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5D_is1', 'UninstallString', UninstallPath) then
         begin
           // Extrair apenas o caminho do executável (remover parâmetros se houver)
           // Se começar com aspas, remover as aspas e pegar até o próximo espaço ou fim
           if Pos('"', UninstallPath) = 1 then
           begin
             // Remover primeira aspas
             UninstallPath := Copy(UninstallPath, 2, Length(UninstallPath) - 1);
             // Encontrar a próxima aspas
             SecondQuotePos := Pos('"', UninstallPath);
             if SecondQuotePos > 0 then
             begin
               // Extrair até a segunda aspas
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
  if VCRedistNeeded then
  begin
    VCRedistPage := CreateOutputProgressPage('Verificando DependÃªncias', 'Instalando Visual C++ Redistributables...');
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
    
    // Se ainda estiver rodando após todas as tentativas, apenas avisar
    // mas tentar continuar (alguns arquivos podem ser substituídos mesmo assim)
    if IsAppRunning(AppExe) then
    begin
      // Não bloquear completamente - apenas avisar
      // O Windows pode conseguir substituir alguns arquivos mesmo com o processo rodando
      // Result := 'O aplicativo ' + ExpandConstant('{#MyAppName}') + ' ainda está em execução. Alguns arquivos podem não ser atualizados.';
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
      MissingDeps := 'ATENÃ‡ÃƒO: Algumas dependÃªncias nÃ£o foram encontradas no sistema:' + #13#10 + #13#10;
      
      if not SqlCmdFound then
        MissingDeps := MissingDeps + '- sqlcmd.exe (SQL Server Command Line Tools)' + #13#10;
      
      if not SybaseFound then
        MissingDeps := MissingDeps + '- dbbackup.exe (Sybase SQL Anywhere)' + #13#10;
      
      MissingDeps := MissingDeps + #13#10 +
        'O aplicativo pode nÃ£o funcionar corretamente sem essas ferramentas.' + #13#10 + #13#10 +
        'Deseja continuar com a instalaÃ§Ã£o mesmo assim?';
      
      if MsgBox(MissingDeps, mbConfirmation, MB_YESNO) = IDNO then
      begin
        Result := False;
      end;
    end;
  end;
end;

function InitializeUninstall(): Boolean;
var
  AppExe: String;
begin
  Result := True;
  AppExe := ExpandConstant('{#MyAppExeName}');
  
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

