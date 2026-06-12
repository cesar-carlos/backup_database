import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceElevationInstaller {
  WindowsServiceElevationInstaller({
    required ProcessService processService,
    required WindowsServiceStatusSupplier getStatus,
    WindowsServiceTimingConfig? timing,
  }) : _processService = processService,
       _getStatus = getStatus,
       _timing = timing ?? WindowsServiceTimingConfig.defaultConfig;

  final ProcessService _processService;
  final WindowsServiceStatusSupplier _getStatus;
  final WindowsServiceTimingConfig _timing;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const String _displayName = WindowsServiceConstants.displayName;
  static const String _description = WindowsServiceConstants.description;
  static const int _successExitCode = 0;
  static const String _programDataEnv = 'ProgramData';
  static const String _defaultProgramData = r'C:\ProgramData';
  static const String _logSubdir = 'logs';
  static const String _localSystemAccount = 'LocalSystem';
  static const String _logPath = WindowsServiceConstants.logPath;

  static const String _troubleshootingWithEnv =
      'Tente:\n'
      '1. Executar como Administrador\n'
      r'2. Verificar se existe C:\ProgramData\BackupDatabase\config\.env'
      '\n'
      '3. Verificar logs em $_logPath (service_stdout.log, service_stderr.log)\n'
      '4. Atualizar o status e tentar novamente';

  static const int _elevatedLogTailMaxChars = 2000;
  static const int _elevatedLogFilesToRead = 5;

  Future<rd.Result<void>> install({
    required String nssmPath,
    required String appPath,
    required String appDir,
    required String? serviceUser,
    required String? servicePassword,
  }) async {
    final programData =
        Platform.environment[_programDataEnv] ?? _defaultProgramData;
    final logPath = '$programData\\BackupDatabase\\$_logSubdir';
    final logDir = '$programData\\BackupDatabase';

    final installScriptDir = '$programData\\BackupDatabase\\install';
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = DateTime.now().microsecondsSinceEpoch.toRadixString(
      16,
    );
    final scriptPath = p.join(
      installScriptDir,
      'backup_db_install_${timestamp}_$randomSuffix.ps1',
    );
    final installLogPath =
        '$programData\\BackupDatabase\\logs\\install_elevated_${timestamp}_$randomSuffix.log';

    try {
      Directory(installScriptDir).createSync(recursive: true);
    } on Object catch (e) {
      return rd.Failure(
        ServerFailure(
          message:
              'Não foi possível criar diretório de scripts de instalação: $e',
        ),
      );
    }

    String safePath(String s) => s.replaceAll("'", "''");
    final scriptContent =
        '''
\$ErrorActionPreference = "Stop"
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  \$PSNativeCommandUseErrorActionPreference = \$false
}
\$selfScript = \$MyInvocation.MyCommand.Path
\$installLog = '${safePath(installLogPath)}'
\$nssmPath = '${safePath(nssmPath)}'
\$appPath = '${safePath(appPath)}'
\$appDir = '${safePath(appDir)}'
\$serviceUser = '${safePath(serviceUser ?? '')}'
\$servicePassword = '${safePath(servicePassword ?? '')}'
\$logPath = '${safePath(logPath)}'
\$logDir = '${safePath(logDir)}'

function Write-InstallLog { param(\$msg) Add-Content -Path \$installLog -Value \$msg }
function Fail { param(\$step,\$err) Write-InstallLog "ERRO em \$step`: \$err"; exit 1 }

function Restrict-Acl { param(\$path)
  try {
    if (Test-Path \$path) {
      icacls \$path /inheritance:r /grant:r 'NT AUTHORITY\\SYSTEM:(F)' 'BUILTIN\\Administrators:(F)' | Out-Null
    }
  } catch {}
}

function Set-NssmKeyWithRetry {
  param(
    [string]\$KeyName,
    [string[]]\$Values,
    [int]\$MaxAttempts = 3
  )
  \$lastErr = \$null
  for (\$attempt = 1; \$attempt -le \$MaxAttempts; \$attempt++) {
    \$r = & \$nssmPath set $_serviceName \$KeyName @Values 2>&1
    if (\$LASTEXITCODE -eq 0) { return }
    \$lastErr = \$r -join " "
    if (\$lastErr -notmatch "Can't open service") { Fail \$KeyName \$lastErr }
    Start-Sleep -Seconds 2
  }
  Fail \$KeyName "Can't open service apos \$MaxAttempts tentativas: \$lastErr"
}

if (-not (Test-Path \$logDir)) { New-Item -ItemType Directory -Path \$logDir -Force | Out-Null }
if (-not (Test-Path \$logPath)) { New-Item -ItemType Directory -Path \$logPath -Force | Out-Null }
Restrict-Acl \$installLog
Restrict-Acl \$selfScript

try {
  try {
    sc.exe query $_serviceName 2>\$null | Out-Null
    if (\$LASTEXITCODE -eq 0) {
      & \$nssmPath remove $_serviceName confirm 2>\$null | Out-Null
      Start-Sleep -Seconds 2
    }

    \$r = & \$nssmPath install $_serviceName \$appPath 2>&1
    if (\$LASTEXITCODE -ne 0) { Fail "install" (\$r -join " ") }

    Start-Sleep -Seconds 5

    Set-NssmKeyWithRetry -KeyName "AppParameters" -Values @("--mode=server --minimized --run-as-service")
    Set-NssmKeyWithRetry -KeyName "AppDirectory" -Values @(\$appDir)
    Set-NssmKeyWithRetry -KeyName "AppEnvironmentExtra" -Values @("SERVICE_MODE=server")
    Set-NssmKeyWithRetry -KeyName "AppStdout" -Values @("\$logPath\\service_stdout.log")
    Set-NssmKeyWithRetry -KeyName "AppStderr" -Values @("\$logPath\\service_stderr.log")
    & \$nssmPath set $_serviceName DisplayName "$_displayName" | Out-Null
    & \$nssmPath set $_serviceName Description "$_description" | Out-Null
    & \$nssmPath set $_serviceName Start SERVICE_AUTO_START | Out-Null
    & \$nssmPath set $_serviceName AppNoConsole 1 | Out-Null
    & \$nssmPath set $_serviceName AppExit Default Restart | Out-Null
    & \$nssmPath set $_serviceName AppExit 77 Exit | Out-Null
    & \$nssmPath set $_serviceName AppExit 78 Exit | Out-Null
    & \$nssmPath set $_serviceName AppRestartDelay 60000 | Out-Null
    if (\$serviceUser -ne '' -and \$servicePassword -ne '') {
      & \$nssmPath set $_serviceName ObjectName \$serviceUser \$servicePassword | Out-Null
    } else {
      & \$nssmPath set $_serviceName ObjectName $_localSystemAccount | Out-Null
    }

    exit 0
  } catch {
    Fail "geral" \$_.Exception.Message
  }
} finally {
  try { if (Test-Path \$selfScript) { Remove-Item -Force \$selfScript } } catch {}
}
''';

    File? scriptFile;
    try {
      scriptFile = File(scriptPath);
      await scriptFile.writeAsString(scriptContent);
    } on Object catch (e) {
      return rd.Failure(
        ServerFailure(
          message: 'Não foi possível criar script de instalação: $e',
        ),
      );
    }

    final scriptPathEscaped = scriptPath.replaceAll('"', '`"');
    final elevatedCommand =
        r'$p = Start-Process -FilePath "powershell.exe" '
        '-ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$scriptPathEscaped" '
        r'-Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $p.ExitCode';

    final result = await _processService.run(
      executable: 'powershell',
      arguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevatedCommand,
      ],
      timeout: _timing.elevatedInstallTimeout,
    );

    String? logContent;
    try {
      final logFile = File(installLogPath);
      if (await logFile.exists()) {
        logContent = await logFile.readAsString();
        await logFile.delete();
      }
    } on Object catch (_) {}
    try {
      if (await scriptFile.exists()) {
        await scriptFile.delete();
      }
    } on Object catch (_) {}

    return result.fold(
      (processResult) async {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        if (_wasUacCancelled(output)) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'A solicitação de permissões de Administrador foi '
                  'cancelada. Para instalar o serviço, confirme o prompt UAC.',
            ),
          );
        }

        if (processResult.exitCode != _successExitCode) {
          var detail = logContent != null && logContent.isNotEmpty
              ? logContent.trim()
              : (output.isNotEmpty ? output : '');
          if (detail.isEmpty) {
            detail = await _readLogsFromProgramData();
          }
          final finalDetail = detail.isNotEmpty ? detail : 'Sem detalhes';
          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao instalar serviço com elevação UAC '
                  '(exit ${processResult.exitCode}).\n\n$finalDetail',
            ),
          );
        }

        final postStatus = await _getStatus();
        return postStatus.fold(
          (status) {
            if (!status.isInstalled) {
              return const rd.Failure(
                ServerFailure(
                  message:
                      'O comando elevado foi executado, mas o serviço não está '
                      'registrado.\n\n$_troubleshootingWithEnv',
                ),
              );
            }
            return const rd.Success(unit);
          },
          rd.Failure.new,
        );
      },
      (failure) => Future.value(
        rd.Failure(
          ServerFailure(
            message:
                'Não foi possível solicitar elevação UAC para instalar '
                'o serviço: $failure',
          ),
        ),
      ),
    );
  }

  Future<String> _readLogsFromProgramData() async {
    final dir = Directory(_logPath);
    if (!await dir.exists()) {
      return 'Pasta de logs não encontrada: $_logPath';
    }

    final buffer = StringBuffer();
    try {
      final entities = dir.listSync();
      final files = entities.whereType<File>().toList();
      files.sort((a, b) {
        try {
          return b.statSync().modified.compareTo(a.statSync().modified);
        } on Object {
          return 0;
        }
      });

      for (final f in files.take(_elevatedLogFilesToRead)) {
        try {
          final content = await f.readAsString();
          if (content.trim().isNotEmpty) {
            buffer.writeln('--- ${f.path} ---');
            buffer.writeln(
              content.trim().length > _elevatedLogTailMaxChars
                  ? '${content.trim().substring(0, _elevatedLogTailMaxChars)}...'
                  : content.trim(),
            );
            buffer.writeln();
          }
        } on Object catch (_) {}
      }
    } on Object catch (e) {
      return 'Erro ao ler $_logPath: $e';
    }

    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : 'Nenhum log encontrado em $_logPath';
  }

  bool _wasUacCancelled(String output) {
    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('canceled by the user') ||
        normalizedOutput.contains('cancelada pelo usuário') ||
        normalizedOutput.contains('cancelado pelo usuário') ||
        normalizedOutput.contains('foi cancelada pelo usuário');
  }
}
