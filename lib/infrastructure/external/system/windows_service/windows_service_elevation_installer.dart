import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceElevationInstaller {
  WindowsServiceElevationInstaller({
    required this._processService,
    required this._getStatus,
    WindowsServiceTimingConfig? timing,
  }) : _timing = timing ?? WindowsServiceTimingConfig.defaultConfig;

  final ProcessService _processService;
  final WindowsServiceStatusSupplier _getStatus;
  final WindowsServiceTimingConfig _timing;

  void Function(bool waiting)? onElevationWaitChanged;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const String _localSystemAccount = 'LocalSystem';
  static const int _successExitCode = 0;
  static const int _scriptTimeoutExitCode = 124;
  static const int _elevatedLogTailMaxChars = 2000;
  static const int _elevatedLogFilesToRead = 5;

  static String get _logPath => WindowsServiceConstants.logPath;

  static String get _troubleshootingWithEnv =>
      'Tente:\n'
      '1. Executar como Administrador\n'
      '2. Verificar se existe ${WindowsServiceConstants.configPath}\\.env\n'
      '3. Verificar logs em $_logPath (service_stdout.log, service_stderr.log)\n'
      '4. Atualizar o status e tentar novamente';

  Future<rd.Result<void>> install({
    required String nssmPath,
    required String appPath,
    required String appDir,
    required String? serviceUser,
    required String? servicePassword,
  }) async {
    final logPath = WindowsServiceConstants.logPath;
    final configPath = WindowsServiceConstants.configPath;
    final logDir = Directory(logPath).parent.path;

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = DateTime.now().microsecondsSinceEpoch.toRadixString(
      16,
    );
    final scriptPath = p.join(
      Directory.systemTemp.path,
      'backup_db_install_${timestamp}_$randomSuffix.ps1',
    );
    final installLogPath = p.join(
      Directory.systemTemp.path,
      'backup_db_install_${timestamp}_$randomSuffix.log',
    );

    final lockedPassword = servicePassword != null && servicePassword.isNotEmpty
        ? servicePassword
        : null;
    final plan = NssmConfigPlan.build(appDir: appDir, logPath: logPath);
    final planSets = plan.toElevatedPowerShellSets();
    final scriptTimeoutMs = _timing.elevatedInstallTimeout.inMilliseconds;

    File? passwordFile;
    try {
      if (lockedPassword != null) {
        final created = await _createLockedPasswordFile(lockedPassword);
        final createFailure = created.exceptionOrNull();
        if (createFailure != null) {
          final failure = createFailure is Failure
              ? createFailure
              : ServerFailure(message: createFailure.toString());
          return rd.Failure(failure);
        }
        passwordFile = created.getOrNull();
      }

      final scriptContent = buildElevatedInstallScript(
        nssmPath: nssmPath,
        appPath: appPath,
        appDir: appDir,
        logPath: logPath,
        logDir: logDir,
        configPath: configPath,
        installLogPath: installLogPath,
        serviceUser: serviceUser,
        passwordFilePath: passwordFile?.path,
        planSets: planSets,
      );

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

      await _restrictScriptAcl(scriptPath);

      final scriptPathEscaped = scriptPath.replaceAll('"', '`"');
      final elevatedCommand =
          r'$p = Start-Process -FilePath "powershell.exe" '
          '-ArgumentList "-NoProfile","-ExecutionPolicy","Bypass","-File","$scriptPathEscaped" '
          '-Verb RunAs -WindowStyle Hidden -PassThru; '
          r'if ($null -eq $p) { exit 1223 }; '
          'if (-not \$p.WaitForExit($scriptTimeoutMs)) { '
          r'try { $p.Kill() } catch {}; exit 124 }; '
          r'exit $p.ExitCode';

      final launchTimeout =
          _timing.uacPromptTimeout + _timing.elevatedInstallTimeout;

      onElevationWaitChanged?.call(true);
      rd.Result<ProcessResult> result;
      try {
        result = await _processService.run(
          executable: 'powershell',
          arguments: [
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-Command',
            elevatedCommand,
          ],
          timeout: launchTimeout,
        );
      } finally {
        onElevationWaitChanged?.call(false);
      }

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

          if (_wasUacCancelled(output) || processResult.exitCode == 1223) {
            return const rd.Failure(
              ValidationFailure(
                message:
                    'A solicitação de permissões de Administrador foi '
                    'cancelada. Para instalar o serviço, confirme o prompt UAC.',
              ),
            );
          }

          final timedOut = processResult.exitCode == _scriptTimeoutExitCode;
          if (processResult.exitCode != _successExitCode) {
            if (timedOut) {
              await _rollbackPartialInstall(nssmPath);
            }
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
                return rd.Failure(
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
        (failure) async {
          await _rollbackPartialInstall(nssmPath);
          return rd.Failure(
            ServerFailure(
              message:
                  'Não foi possível solicitar elevação UAC para instalar '
                  'o serviço: ${failureUserMessage(failure)}',
            ),
          );
        },
      );
    } finally {
      await _deleteQuietly(passwordFile);
    }
  }

  @visibleForTesting
  static String buildElevatedInstallScript({
    required String nssmPath,
    required String appPath,
    required String appDir,
    required String logPath,
    required String logDir,
    required String configPath,
    required String installLogPath,
    required String? serviceUser,
    required String? passwordFilePath,
    required String planSets,
  }) {
    String safePath(String value) => value.replaceAll("'", "''");
    final passwordFile = passwordFilePath == null
        ? ''
        : safePath(passwordFilePath);
    return '''
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
\$passwordFile = '$passwordFile'
\$logPath = '${safePath(logPath)}'
\$logDir = '${safePath(logDir)}'
\$configPath = '${safePath(configPath)}'

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

function Set-NssmKeyOptional {
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
    if (\$lastErr -notmatch "Can't open service") {
      Write-InstallLog "AVISO \$KeyName`: \$lastErr"
      return
    }
    Start-Sleep -Seconds 2
  }
  Write-InstallLog "AVISO \$KeyName`: Can't open service apos \$MaxAttempts tentativas: \$lastErr"
}

function Set-ServiceAccountFromFile {
  param([string]\$User, [string]\$SecretFile)
  if (-not (Test-Path -LiteralPath \$SecretFile)) {
    Fail "ObjectName" "arquivo de senha ausente"
  }
  \$servicePassword = [System.IO.File]::ReadAllText(\$SecretFile)
  if (-not ('BackupDbServiceConfig' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class BackupDbServiceConfig {
  [DllImport("advapi32.dll", EntryPoint="OpenSCManagerW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr OpenSCManager(string machine, string database, uint access);

  [DllImport("advapi32.dll", EntryPoint="OpenServiceW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr OpenService(IntPtr scm, string name, uint access);

  [DllImport("advapi32.dll", EntryPoint="ChangeServiceConfigW", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool ChangeServiceConfig(
    IntPtr service,
    uint serviceType,
    uint startType,
    uint errorControl,
    string binaryPath,
    string loadOrderGroup,
    IntPtr tagId,
    string dependencies,
    string startName,
    string password,
    string displayName);

  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern bool CloseServiceHandle(IntPtr handle);
}
'@
  }
  \$scm = [BackupDbServiceConfig]::OpenSCManager(\$null, \$null, 1)
  if (\$scm -eq [IntPtr]::Zero) {
    Fail "ObjectName" ("OpenSCManager " + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
  }
  try {
    \$svc = [BackupDbServiceConfig]::OpenService(\$scm, "$_serviceName", 2)
    if (\$svc -eq [IntPtr]::Zero) {
      Fail "ObjectName" ("OpenService " + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
    try {
      \$noChange = [uint32]::MaxValue
      \$ok = [BackupDbServiceConfig]::ChangeServiceConfig(
        \$svc, \$noChange, \$noChange, \$noChange,
        \$null, \$null, [IntPtr]::Zero, \$null,
        \$User, \$servicePassword, \$null)
      if (-not \$ok) {
        Fail "ObjectName" ("ChangeServiceConfig " + [System.Runtime.InteropServices.Marshal]::GetLastWin32Error())
      }
    } finally {
      [BackupDbServiceConfig]::CloseServiceHandle(\$svc) | Out-Null
      \$servicePassword = \$null
    }
  } finally {
    [BackupDbServiceConfig]::CloseServiceHandle(\$scm) | Out-Null
  }
}

if (-not (Test-Path \$logDir)) { New-Item -ItemType Directory -Path \$logDir -Force | Out-Null }
if (-not (Test-Path \$logPath)) { New-Item -ItemType Directory -Path \$logPath -Force | Out-Null }
if (-not (Test-Path \$configPath)) { New-Item -ItemType Directory -Path \$configPath -Force | Out-Null }
Restrict-Acl \$installLog
Restrict-Acl \$selfScript
Restrict-Acl \$logPath
Restrict-Acl \$configPath

\$envDest = Join-Path \$configPath '.env'
if (-not (Test-Path \$envDest)) {
  \$envCandidates = @(
    (Join-Path \$appDir '.env'),
    (Join-Path \$appDir '.env.example'),
    (Join-Path \$configPath '.env.example')
  )
  foreach (\$candidate in \$envCandidates) {
    if (Test-Path \$candidate) {
      Copy-Item -Path \$candidate -Destination \$envDest -Force
      Write-InstallLog "Copiado \$candidate -> \$envDest"
      break
    }
  }
}

try {
  try {
    sc.exe query $_serviceName 2>\$null | Out-Null
    if (\$LASTEXITCODE -eq 0) {
      sc.exe stop $_serviceName 2>\$null | Out-Null
      Start-Sleep -Seconds 2
      & \$nssmPath remove $_serviceName confirm 2>\$null | Out-Null
      Start-Sleep -Seconds 2
    }

    \$r = & \$nssmPath install $_serviceName \$appPath 2>&1
    if (\$LASTEXITCODE -ne 0) { Fail "install" (\$r -join " ") }

    Start-Sleep -Seconds 5

$planSets
    if (\$serviceUser -ne '' -and \$passwordFile -ne '') {
      Set-ServiceAccountFromFile -User \$serviceUser -PasswordFile \$passwordFile
    } else {
      Set-NssmKeyOptional -KeyName "ObjectName" -Values @("$_localSystemAccount")
    }

    exit 0
  } catch {
    Fail "geral" \$_.Exception.Message
  }
} finally {
  if (\$passwordFile -ne '') {
    try { if (Test-Path -LiteralPath \$passwordFile) { Remove-Item -LiteralPath \$passwordFile -Force } } catch {}
  }
  try { if (Test-Path \$selfScript) { Remove-Item -Force \$selfScript } } catch {}
}
''';
  }

  Future<rd.Result<File>> _createLockedPasswordFile(String password) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomSuffix = DateTime.now().microsecondsSinceEpoch.toRadixString(
      16,
    );
    final path = p.join(
      Directory.systemTemp.path,
      'backup_db_svc_pwd_${timestamp}_$randomSuffix.txt',
    );
    final file = File(path);
    try {
      await file.writeAsString('', flush: true);
    } on Object catch (e) {
      return rd.Failure(
        ServerFailure(
          message:
              'Não foi possível criar o arquivo temporário da senha '
              'do serviço: $e',
        ),
      );
    }
    final restricted = await _restrictPasswordFileAcl(path);
    if (!restricted) {
      await _deleteQuietly(file);
      return const rd.Failure(
        ServerFailure(
          message:
              'Não foi possível restringir o acesso ao arquivo '
              'temporário da senha do serviço.',
        ),
      );
    }
    try {
      await file.writeAsString(password, flush: true);
    } on Object catch (e) {
      await _deleteQuietly(file);
      return rd.Failure(
        ServerFailure(
          message:
              'Não foi possível gravar a senha do serviço no arquivo '
              'temporário: $e',
        ),
      );
    }
    return rd.Success(file);
  }

  Future<bool> _restrictPasswordFileAcl(String path) async {
    final grants = <String>[
      path,
      '/inheritance:r',
      '/grant:r',
      r'NT AUTHORITY\SYSTEM:(F)',
      r'BUILTIN\Administrators:(F)',
    ];
    final account = _currentWindowsAccount();
    if (account != null) {
      grants.add('$account:(F)');
    }
    try {
      final result = await _processService.run(
        executable: 'icacls',
        arguments: grants,
        timeout: _timing.shortTimeout,
      );
      return result.fold(
        (processResult) => processResult.exitCode == _successExitCode,
        (_) => false,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Não foi possível restringir ACL do arquivo de senha do serviço',
        e,
        s,
      );
      return false;
    }
  }

  String? _currentWindowsAccount() {
    final name = Platform.environment['USERNAME'];
    if (name == null || name.isEmpty) {
      return null;
    }
    final domain = Platform.environment['USERDOMAIN'];
    if (domain == null || domain.isEmpty) {
      return name;
    }
    return '$domain\\$name';
  }

  Future<void> _deleteQuietly(File? file) async {
    if (file == null) {
      return;
    }
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        'Não foi possível apagar o arquivo temporário da senha do serviço',
        e,
        s,
      );
    }
  }

  Future<void> _restrictScriptAcl(String scriptPath) async {
    try {
      await _processService.run(
        executable: 'icacls',
        arguments: [
          scriptPath,
          '/inheritance:r',
          '/grant:r',
          r'NT AUTHORITY\SYSTEM:(F)',
          r'BUILTIN\Administrators:(F)',
        ],
        timeout: _timing.shortTimeout,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Não foi possível restringir ACL do script UAC em $scriptPath',
        e,
        s,
      );
    }
  }

  Future<void> _rollbackPartialInstall(String nssmPath) async {
    LoggerService.warning(
      'Instalação elevada incompleta ou em timeout; tentando nssm remove',
    );
    try {
      await _processService.run(
        executable: nssmPath,
        arguments: ['remove', _serviceName, 'confirm'],
        timeout: _timing.longTimeout,
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        'Rollback nssm remove falhou (o filho elevado pode ainda existir)',
        e,
        s,
      );
    }
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
