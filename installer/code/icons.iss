; Icon and desktop shortcut helpers for setup.iss.
;
; Pertencem ao mesmo escopo Pascal de setup.iss (sao incluidos via
; `#include` na secao [Code]). Centralizam o fluxo de refresh de icone
; descrito em docs/adr/015-windows-icon-pipeline-and-shortcut-refresh.md:
;
;   - RefreshWindowsIconCache: `ie4uinit.exe -show` (limpa cache global)
;   - RemoveExistingDesktopShortcut: apaga .lnk legado antes do Inno gerar o novo
;   - TryTouchShortcutWith: helper privado para tentar PS com fallback
;   - TouchDesktopShortcut: atualiza LastWriteTime do .lnk (forca refresh local)
;
; Forwards correspondentes ficam em setup.iss para preservar a ordem
; de declaracao Pascal junto das demais procedures do instalador.

procedure RemoveExistingDesktopShortcut();
var
  ShortcutPath: String;
begin
  ShortcutPath := ExpandConstant('{autodesktop}\{#MyAppName}.lnk');
  if FileExists(ShortcutPath) then
  begin
    if DeleteFile(ShortcutPath) then
      Log('Removed legacy desktop shortcut before recreate: ' + ShortcutPath)
    else
      Log('Warning: failed to remove legacy desktop shortcut: ' + ShortcutPath);
  end;
end;

function TryTouchShortcutWith(const PsExe, ShortcutPath, PsCommand: String): Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(
    PsExe,
    '-NoProfile -ExecutionPolicy Bypass -Command "' + PsCommand + '"',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) and (ResultCode = 0);
end;

procedure TouchDesktopShortcut();
var
  ShortcutPath: String;
  PsCommand: String;
begin
  // Tocar o LastWriteTime do .lnk forca o Explorer a reavaliar o icone na
  // proxima atualizacao do desktop, complementando ie4uinit -show em
  // cenarios de cache mais agressivo.
  if not WizardIsTaskSelected('desktopicon') then Exit;
  ShortcutPath := ExpandConstant('{autodesktop}\{#MyAppName}.lnk');
  if not FileExists(ShortcutPath) then Exit;

  PsCommand := '(Get-Item -LiteralPath ''' + ShortcutPath + ''').LastWriteTime = Get-Date';

  // Tenta primeiro powershell.exe (Windows PowerShell 5.1, parte do baseline
  // do Windows 10/11). Se falhar — raro, mas pode ocorrer em SKUs reduzidos
  // ou ambientes corporativos com policy restritiva — tenta pwsh.exe
  // (PowerShell 7+) como fallback antes de desistir.
  if TryTouchShortcutWith('powershell.exe', ShortcutPath, PsCommand) then
  begin
    Log('Touched desktop shortcut to refresh icon cache (powershell.exe): ' + ShortcutPath);
    Exit;
  end;

  if TryTouchShortcutWith('pwsh.exe', ShortcutPath, PsCommand) then
  begin
    Log('Touched desktop shortcut to refresh icon cache (pwsh.exe fallback): ' + ShortcutPath);
    Exit;
  end;

  Log('Warning: failed to touch desktop shortcut, both powershell.exe and pwsh.exe unavailable: ' + ShortcutPath);
end;

procedure RefreshWindowsIconCache();
var
  ResultCode: Integer;
begin
  if Exec(
    ExpandConstant('{sys}\ie4uinit.exe'),
    '-show',
    '',
    SW_HIDE,
    ewWaitUntilTerminated,
    ResultCode
  ) then
    Log('Refreshed Windows icon cache (ie4uinit.exe -show)')
  else
    Log('Warning: failed to refresh Windows icon cache (ie4uinit.exe)');
end;
