import 'dart:io';

import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart'
    as rd
    show Failure, Result, Success;
import 'package:result_dart/result_dart.dart' show unit;

/// Parâmetros centralizados de timeout e polling para operações do serviço.
class WindowsServiceTimingConfig {
  const WindowsServiceTimingConfig({
    this.shortTimeout = const Duration(seconds: 10),
    this.longTimeout = const Duration(seconds: 30),
    this.serviceDelay = const Duration(seconds: 2),
    this.startPollingInterval = const Duration(seconds: 1),
    this.startPollingTimeout = const Duration(seconds: 30),
    this.startPollingInitialDelay = const Duration(seconds: 3),
    this.retryMaxAttempts = 3,
    this.retryInitialDelay = const Duration(milliseconds: 500),
    this.retryBackoffMultiplier = 2,
  });

  final Duration shortTimeout;
  final Duration longTimeout;
  final Duration serviceDelay;
  final Duration startPollingInterval;
  final Duration startPollingTimeout;
  final Duration startPollingInitialDelay;
  final int retryMaxAttempts;
  final Duration retryInitialDelay;
  final int retryBackoffMultiplier;

  static const WindowsServiceTimingConfig defaultConfig =
      WindowsServiceTimingConfig();
}

class WindowsServiceService implements IWindowsServiceService {
  WindowsServiceService(
    this._processService, {
    WindowsServiceTimingConfig? timingConfig,
    IMetricsCollector? metricsCollector,
  }) : _timing = timingConfig ?? WindowsServiceTimingConfig.defaultConfig,
       _metrics = metricsCollector;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;
  final IMetricsCollector? _metrics;

  static const String _serviceName = 'BackupDatabaseService';
  static const String _displayName = 'Backup Database Service';
  static const String _description =
      'Servico de backup automatico para SQL Server e Sybase';
  static const int _successExitCode = 0;
  static const int _serviceNotFoundExitCode = 3;
  static const String _nssmExeName = 'nssm.exe';
  static const String _scExeName = 'sc';
  static const String _toolsSubdir = 'tools';
  static const String _logSubdir = 'logs';
  static const String _programDataEnv = 'ProgramData';
  static const String _defaultProgramData = r'C:\ProgramData';
  static const String _runningState = 'RUNNING';
  static const String _runningStatePt = 'EM EXECUÇÃO';
  static const String _runningStatePtNoAccent = 'EM EXECUCAO';
  static const String _localSystemAccount = 'LocalSystem';
  static const String _logPath = r'C:\ProgramData\BackupDatabase\logs';
  static const String _controlDiagnosticsPath =
      r'C:\ProgramData\BackupDatabase\logs\service_control_diagnostics.log';
  static final RegExp _runningStateRegex = RegExp(
    r'(?:STATE|ESTADO)\s*:\s*4\b',
    caseSensitive: false,
  );
  static final RegExp _stateCodeRegex = RegExp(
    r'(?:STATE|ESTADO)\s*:\s*(\d+)',
    caseSensitive: false,
  );

  static const String _accessDeniedSolution =
      'Solução:\n'
      '1. Feche o aplicativo\n'
      '2. Clique com botão direito no ícone do aplicativo\n'
      '3. Selecione "Executar como administrador"\n'
      '4. Tente novamente';

  static const String _troubleshootingAdminLogs =
      'Tente:\n'
      '1. Executar como Administrador\n'
      '2. Verificar logs em $_logPath\n'
      '3. Atualizar o status e tentar novamente';

  static const String _troubleshootingWithEnv =
      'Tente:\n'
      '1. Executar como Administrador\n'
      '2. Verificar se existe .env na pasta do aplicativo (copie de .env.example)\n'
      '3. Verificar logs em $_logPath (service_stdout.log, service_stderr.log)\n'
      '4. Atualizar o status e tentar novamente';
  static const int _serviceNotInstalledWinError = 1060;
  static const int _serviceNotInstalledBatchError = 36;
  static const int _accessDeniedWinError = 5;
  static const int _serviceAlreadyRunningWinError = 1056;

  Future<rd.Result<void>> _runInstallPreflight(String appDir) async {
    final statusResult = await getStatus();
    final statusFailure = statusResult.exceptionOrNull();
    if (statusFailure != null) {
      final msg =
          (statusFailure is Failure
                  ? statusFailure.message
                  : statusFailure.toString())
              .toLowerCase();
      if (msg.contains('acesso negado') ||
          msg.contains('access denied') ||
          msg.contains('administrator')) {
        return rd.Failure(
          statusFailure is Failure
              ? statusFailure
              : ServerFailure(message: statusFailure.toString()),
        );
      }
    }

    final envPath = '$appDir\\.env';
    if (!File(envPath).existsSync()) {
      LoggerService.warning(
        'Arquivo .env não encontrado em $appDir. '
        'Copie .env.example para .env. O serviço pode falhar ao iniciar.',
      );
    }

    try {
      final logDir = Directory(_logPath);
      logDir.createSync(recursive: true);
      final testFile = File('$_logPath\\.preflight_write_test');
      testFile.writeAsStringSync('');
      testFile.deleteSync();
    } on Object catch (e) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Diretório de logs não é gravável: $_logPath\n\n'
              'Erro: $e\n\n'
              'Tente:\n'
              '1. Executar como Administrador\n'
              '2. Verificar permissões da pasta $_logPath',
        ),
      );
    }

    return const rd.Success(unit);
  }

  bool _isRetryableProcessFailure(Object failure) {
    final msg = failure.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('scm') ||
        msg.contains('service control manager') ||
        msg.contains('busy') ||
        msg.contains('temporarily');
  }

  Future<rd.Result<ProcessResult>> _runScWithRetry({
    required List<String> arguments,
    required Duration timeout,
    String operationName = 'sc',
  }) async {
    var attempt = 0;
    var delay = _timing.retryInitialDelay;
    rd.Result<ProcessResult>? lastResult;

    while (true) {
      attempt++;
      lastResult = await _processService.run(
        executable: _scExeName,
        arguments: arguments,
        timeout: timeout,
      );

      if (lastResult.isSuccess()) {
        return lastResult;
      }

      final failure = lastResult.exceptionOrNull()!;
      final isLastAttempt = attempt >= _timing.retryMaxAttempts;
      final canRetry = _isRetryableProcessFailure(failure);

      LoggerService.warning(
        '$operationName falhou (tentativa $attempt/${_timing.retryMaxAttempts}): $failure',
        failure,
      );

      if (isLastAttempt || !canRetry) {
        return lastResult;
      }

      _metrics?.incrementCounter(ObservabilityMetrics.windowsServiceScRetries);

      LoggerService.info(
        'Retentando $operationName em ${delay.inMilliseconds}ms '
        '(tentativa ${attempt + 1}/${_timing.retryMaxAttempts})',
      );
      await Future.delayed(delay);
      delay = Duration(
        milliseconds: delay.inMilliseconds * _timing.retryBackoffMultiplier,
      );
    }
  }

  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final result = await _runScWithRetry(
        arguments: ['query', _serviceName],
        timeout: _timing.shortTimeout,
        operationName: 'sc query',
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == _successExitCode) {
            final stdout = processResult.stdout;
            final isRunning = _isRunningState(stdout);
            final stateCode = _parseStateCode(stdout);
            _appendControlDiagnostics(
              'getStatus: installed=true running=$isRunning '
              'state=${stateCode?.name ?? 'unknown'} '
              'exit=${processResult.exitCode}',
              output: stdout,
            );
            return rd.Success(
              WindowsServiceStatus(
                isInstalled: true,
                isRunning: isRunning,
                stateCode: stateCode,
                serviceName: _serviceName,
                displayName: _displayName,
              ),
            );
          }

          if (_isServiceNotInstalledResponse(processResult)) {
            _appendControlDiagnostics(
              'getStatus: installed=false exit=${processResult.exitCode}',
              output: _getProcessOutput(processResult),
            );
            return const rd.Success(
              WindowsServiceStatus(
                isInstalled: false,
                isRunning: false,
              ),
            );
          }

          if (_isAccessDeniedResponse(processResult)) {
            return const rd.Failure(
              ServerFailure(
                message:
                    'Acesso negado ao consultar status do serviço. '
                    'Execute o aplicativo como Administrador.\n\n$_accessDeniedSolution',
              ),
            );
          }

          final errorOutput = _getProcessOutput(processResult);
          _appendControlDiagnostics(
            'getStatus: failure exit=${processResult.exitCode}',
            output: errorOutput,
          );
          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao consultar status do serviço (exit code: ${processResult.exitCode}). '
                  'Saída: $errorOutput\n\n$_troubleshootingAdminLogs',
            ),
          );
        },
        (failure) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Erro ao executar comando para consultar status do serviço: '
                  '$failure\n\n$_troubleshootingAdminLogs',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar status do serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(
          message:
              'Erro ao verificar status do serviço: $e\n\n$_troubleshootingAdminLogs',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> installService({
    String? serviceUser,
    String? servicePassword,
  }) async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appPath = Platform.resolvedExecutable;
      final appDir = File(appPath).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

      if (!File(nssmPath).existsSync()) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceInstallFailure,
        );
        return rd.Failure(
          ValidationFailure(
            message:
                'NSSM não encontrado em $nssmPath.\n\n'
                'Tente:\n'
                '1. Reinstalar o aplicativo (o instalador deve incluir nssm.exe em tools/)\n'
                '2. Executar como Administrador\n'
                '3. Verificar se a pasta do aplicativo está corrompida ou incompleta',
          ),
        );
      }

      final preflightResult = await _runInstallPreflight(appDir);
      final preflightFailure = preflightResult.exceptionOrNull();
      if (preflightFailure != null) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceInstallFailure,
        );
        return rd.Failure(preflightFailure as Failure);
      }

      LoggerService.info('Instalando serviço do Windows...');

      final statusResult = await getStatus();
      final existingStatus = statusResult.getOrNull();

      if (existingStatus?.isInstalled ?? false) {
        LoggerService.info('Serviço já existe. Removendo versão anterior...');
        await uninstallService();
        await Future.delayed(_timing.serviceDelay);
      }

      final installResult = await _processService.run(
        executable: nssmPath,
        arguments: ['install', _serviceName, appPath],
        timeout: _timing.longTimeout,
      );

      return await installResult.fold<Future<rd.Result<void>>>(
        (processResult) async {
          if (processResult.exitCode != _successExitCode) {
            final errorMessage = processResult.stderr.isNotEmpty
                ? processResult.stderr
                : processResult.stdout;

            final isAccessDenied =
                errorMessage.contains('Acesso negado') ||
                errorMessage.contains('Access denied') ||
                errorMessage.contains('FALHA 5') ||
                errorMessage.contains('FAILURE 5');

            if (isAccessDenied) {
              LoggerService.warning(
                'Acesso negado ao instalar serviço; solicitando elevação UAC',
              );
              final elevatedResult = await _installWithElevation(
                nssmPath: nssmPath,
                appPath: appPath,
                appDir: appDir,
                serviceUser: serviceUser,
                servicePassword: servicePassword,
              );
              return elevatedResult.fold(
                (_) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceInstallSuccess,
                  );
                  LoggerService.info('Serviço instalado com sucesso (UAC)');
                  return const rd.Success(unit);
                },
                (f) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceInstallFailure,
                  );
                  return rd.Failure(f);
                },
              );
            }

            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceInstallFailure,
            );
            return rd.Failure(
              ServerFailure(
                message:
                    'Erro ao instalar serviço: $errorMessage\n\n$_troubleshootingAdminLogs',
              ),
            );
          }

          await Future.delayed(_timing.serviceDelay);

          final configResult = await _configureService(
            nssmPath,
            serviceUser,
            servicePassword,
          );
          final configFailure = configResult.exceptionOrNull();
          if (configFailure != null) {
            final failureMsg =
                (configFailure is Failure ? configFailure.message : null) ??
                    configFailure.toString();
            final isConfigAccessDenied =
                failureMsg.contains('Acesso negado') ||
                failureMsg.contains('Access denied') ||
                failureMsg.contains('FALHA 5') ||
                failureMsg.contains('FAILURE 5');

            if (isConfigAccessDenied) {
              LoggerService.warning(
                'Acesso negado ao configurar serviço; removendo parcial e '
                'solicitando elevação UAC',
              );
              await _processService.run(
                executable: nssmPath,
                arguments: ['remove', _serviceName, 'confirm'],
                timeout: _timing.longTimeout,
              );
              await Future.delayed(_timing.serviceDelay);
              final elevatedResult = await _installWithElevation(
                nssmPath: nssmPath,
                appPath: appPath,
                appDir: appDir,
                serviceUser: serviceUser,
                servicePassword: servicePassword,
              );
              return elevatedResult.fold(
                (_) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceInstallSuccess,
                  );
                  LoggerService.info('Serviço instalado com sucesso (UAC)');
                  return const rd.Success(unit);
                },
                (f) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceInstallFailure,
                  );
                  return rd.Failure(f);
                },
              );
            }

            LoggerService.error(
              'Configuração crítica do serviço falhou — removendo instalação parcial',
              configFailure,
            );
            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceInstallFailure,
            );
            await _processService.run(
              executable: nssmPath,
              arguments: ['remove', _serviceName, 'confirm'],
              timeout: _timing.longTimeout,
            );
            return rd.Failure(configFailure as Failure);
          }

          final postStatus = await getStatus();
          return postStatus.fold(
            (status) {
              if (!status.isInstalled) {
                LoggerService.warning(
                  'Instalação concluiu mas serviço não aparece como instalado',
                );
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceInstallFailure,
                );
                return const rd.Failure(
                  ServerFailure(
                    message:
                        'O comando de instalação foi executado, mas o serviço '
                        'não está registrado.\n\n$_troubleshootingWithEnv',
                  ),
                );
              }
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceInstallSuccess,
              );
              LoggerService.info('Serviço instalado com sucesso');
              LoggerService.info(
                'Auto-restart configurado: Reiniciará automaticamente após crash (60s delay)',
              );
              return const rd.Success(unit);
            },
            (f) {
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceInstallFailure,
              );
              return rd.Failure(f);
            },
          );
        },
        (f) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceInstallFailure,
          );
          return Future.value(rd.Failure(f));
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao instalar serviço', e, stackTrace);
      _metrics?.incrementCounter(
        ObservabilityMetrics.windowsServiceInstallFailure,
      );
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao instalar serviço: $e\n\n$_troubleshootingAdminLogs',
        ),
      );
    }
  }

  Future<rd.Result<void>> _configureService(
    String nssmPath,
    String? serviceUser,
    String? servicePassword,
  ) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final programData =
        Platform.environment[_programDataEnv] ?? _defaultProgramData;
    final logPath = '$programData\\BackupDatabase\\$_logSubdir';

    final logDir = Directory(logPath);
    if (!logDir.existsSync()) {
      try {
        logDir.createSync(recursive: true);
      } on Object catch (e) {
        LoggerService.warning('Erro ao criar diretório de logs: $e');
      }
    }

    // Critical keys: if any fail the installation must be aborted.
    const criticalKeys = {
      'AppParameters',
      'AppDirectory',
      'AppEnvironmentExtra',
      'AppStdout',
      'AppStderr',
    };

    final configs = [
      // Critical: --run-as-service triggers headless mode; without it the
      // service process opens a (invisible) window and the SCM times out.
      [
        'set',
        _serviceName,
        'AppParameters',
        '--mode=server --minimized --run-as-service',
      ],
      // Critical: working dir is needed for .env and asset resolution.
      ['set', _serviceName, 'AppDirectory', appDir],
      // Critical: environment variable used as the primary service-mode signal.
      ['set', _serviceName, 'AppEnvironmentExtra', 'SERVICE_MODE=server'],
      ['set', _serviceName, 'DisplayName', _displayName],
      ['set', _serviceName, 'Description', _description],
      ['set', _serviceName, 'Start', 'SERVICE_AUTO_START'],
      ['set', _serviceName, 'AppStdout', '$logPath\\service_stdout.log'],
      ['set', _serviceName, 'AppStderr', '$logPath\\service_stderr.log'],
      ['set', _serviceName, 'AppExit', 'Default', 'Restart'],
      ['set', _serviceName, 'AppRestartDelay', '60000'],
    ];

    for (final config in configs) {
      final key = config[2];
      final result = await _processService.run(
        executable: nssmPath,
        arguments: config,
        timeout: _timing.shortTimeout,
      );

      final isCritical = criticalKeys.contains(key);

      final failure = result.fold(
        (processResult) {
          if (processResult.exitCode != _successExitCode) {
            final msg = processResult.stderr.isNotEmpty
                ? processResult.stderr
                : processResult.stdout;
            if (isCritical) {
              return ServerFailure(
                message:
                    'Falha ao configurar chave crítica "$key" do serviço '
                    '(exit ${processResult.exitCode}): $msg',
              );
            }
            LoggerService.warning('Aviso ao configurar $key: $msg');
          }
          return null;
        },
        (f) {
          if (isCritical) {
            return ServerFailure(
              message: 'Erro ao configurar chave crítica "$key": $f',
            );
          }
          LoggerService.warning('Erro ao configurar $key: $f');
          return null;
        },
      );

      if (failure != null) {
        return rd.Failure(failure);
      }
    }

    if (serviceUser == null || serviceUser.isEmpty) {
      LoggerService.info(
        'Configurando serviço para rodar como LocalSystem (sem usuário logado)',
      );
      await _processService.run(
        executable: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', _localSystemAccount],
        timeout: _timing.shortTimeout,
      );
    } else if (servicePassword != null && servicePassword.isNotEmpty) {
      await _processService.run(
        executable: nssmPath,
        arguments: [
          'set',
          _serviceName,
          'ObjectName',
          serviceUser,
          servicePassword,
        ],
        timeout: _timing.shortTimeout,
      );
    } else {
      LoggerService.warning(
        'Usuário "$serviceUser" fornecido sem senha — usando LocalSystem',
      );
      await _processService.run(
        executable: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', _localSystemAccount],
        timeout: _timing.shortTimeout,
      );
    }

    return const rd.Success(unit);
  }

  @override
  Future<rd.Result<void>> uninstallService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

      if (!File(nssmPath).existsSync()) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceUninstallFailure,
        );
        return rd.Failure(
          ValidationFailure(
            message:
                'NSSM não encontrado em $nssmPath.\n\n'
                'Tente:\n'
                '1. Remover manualmente via services.msc (Services)\n'
                '2. Ou reinstalar o aplicativo e executar como Administrador',
          ),
        );
      }

      await _processService.run(
        executable: _scExeName,
        arguments: ['stop', _serviceName],
        timeout: _timing.longTimeout,
      );

      await Future.delayed(_timing.serviceDelay);

      final removeResult = await _processService.run(
        executable: nssmPath,
        arguments: ['remove', _serviceName, 'confirm'],
        timeout: _timing.longTimeout,
      );

      return await removeResult.fold<Future<rd.Result<void>>>(
        (processResult) async {
          if (processResult.exitCode != _successExitCode &&
              processResult.exitCode != _serviceNotFoundExitCode) {
            final errorMessage = processResult.stderr.isNotEmpty
                ? processResult.stderr
                : processResult.stdout;

            final isAccessDenied =
                errorMessage.contains('Acesso negado') ||
                errorMessage.contains('Access denied') ||
                errorMessage.contains('FALHA 5') ||
                errorMessage.contains('FAILURE 5');

            if (isAccessDenied) {
              LoggerService.warning(
                'Acesso negado ao remover serviço; solicitando elevação UAC',
              );
              final elevatedUninstallResult = await _uninstallWithElevation();
              return elevatedUninstallResult.fold(
                (_) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceUninstallSuccess,
                  );
                  LoggerService.info(
                    'Serviço removido com sucesso após elevação UAC',
                  );
                  return const rd.Success(unit);
                },
                (failure) {
                  _metrics?.incrementCounter(
                    ObservabilityMetrics.windowsServiceUninstallFailure,
                  );
                  return rd.Failure(failure);
                },
              );
            }

            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceUninstallFailure,
            );
            return rd.Failure(
              ServerFailure(
                message:
                    'Erro ao remover serviço: $errorMessage\n\n$_troubleshootingAdminLogs',
              ),
            );
          }

          final postStatus = await getStatus();
          return postStatus.fold(
            (status) {
              if (status.isInstalled) {
                LoggerService.warning(
                  'Remoção concluiu mas serviço ainda aparece como instalado',
                );
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceUninstallFailure,
                );
                return const rd.Failure(
                  ServerFailure(
                    message:
                        'O comando de remoção foi executado, mas o serviço '
                        'ainda está registrado. Tente atualizar o status ou '
                        'remover manualmente via services.msc.',
                  ),
                );
              }
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceUninstallSuccess,
              );
              LoggerService.info('Serviço removido com sucesso');
              return const rd.Success(unit);
            },
            (f) {
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceUninstallFailure,
              );
              return rd.Failure(f);
            },
          );
        },
        (f) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceUninstallFailure,
          );
          return Future.value(rd.Failure(f));
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao remover serviço', e, stackTrace);
      _metrics?.incrementCounter(
        ObservabilityMetrics.windowsServiceUninstallFailure,
      );
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao remover serviço: $e\n\n$_troubleshootingAdminLogs',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> startService() => startServiceWithTimeout();

  /// Inicia o serviço com parâmetros de polling configuráveis.
  ///
  /// Exposto para testes — use [startService] no código de produção.
  Future<rd.Result<void>> startServiceWithTimeout({
    Duration? pollingTimeout,
    Duration? pollingInterval,
    Duration? initialDelay,
  }) async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      _appendControlDiagnostics(
        'startService: begin timeout=${(pollingTimeout ?? _timing.startPollingTimeout).inSeconds}s '
        'interval=${(pollingInterval ?? _timing.startPollingInterval).inMilliseconds}ms '
        'initialDelay=${(initialDelay ?? _timing.startPollingInitialDelay).inMilliseconds}ms',
      );
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();
      _appendControlDiagnostics(
        'startService: initialStatus installed=${status?.isInstalled} '
        'running=${status?.isRunning} state=${status?.stateCode?.name}',
      );

      if (status?.isRunning ?? false) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceStartSuccess,
        );
        LoggerService.info('Serviço já está em execução');
        return const rd.Success(unit);
      }

      final isStartPending =
          status?.stateCode == WindowsServiceStateCode.startPending;
      if (isStartPending) {
        LoggerService.info('Serviço em START_PENDING, aguardando RUNNING');
        final runningAfterPoll = await _pollUntilRunning(
          timeout: pollingTimeout ?? _timing.startPollingTimeout,
          interval: pollingInterval ?? _timing.startPollingInterval,
          initialDelay: initialDelay ?? _timing.startPollingInitialDelay,
          onConvergence: (d) => _metrics?.recordHistogram(
            ObservabilityMetrics.windowsServiceStartConvergenceSeconds,
            d.inMilliseconds / 1000,
          ),
        );
        if (runningAfterPoll) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStartSuccess,
          );
          LoggerService.info('Serviço entrou em execução');
          return const rd.Success(unit);
        }
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceStartFailure,
        );
        return const rd.Failure(
          ServerFailure(
            message:
                'Serviço permaneceu em START_PENDING e não atingiu RUNNING '
                'dentro do tempo esperado.\n\n$_troubleshootingWithEnv',
          ),
        );
      }

      final isPaused = status?.stateCode?.isPaused ?? false;
      if (isPaused) {
        LoggerService.warning(
          'Serviço em PAUSED. Aplicando recuperação: STOP completo e START',
        );
        _appendControlDiagnostics(
          'startService: detected PAUSED, executing stop+start recovery',
        );
        final stopResult = await stopService();
        final stopFailure = stopResult.exceptionOrNull();
        if (stopFailure != null) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStartFailure,
          );
          return rd.Failure(stopFailure as Failure);
        }
        await Future.delayed(_timing.serviceDelay);
      }
      const scCommand = 'start';

      final result = await _runScWithRetry(
        arguments: [scCommand, _serviceName],
        timeout: _timing.longTimeout,
        operationName: 'sc $scCommand',
      );

      return result.fold(
        (processResult) async {
          final errorMessage = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;
          _appendControlDiagnostics(
            'startService: sc $scCommand exit=${processResult.exitCode}',
            output: errorMessage,
          );

          final isAlreadyRunning = _isServiceAlreadyRunningResponse(
            processResult,
            errorMessage,
          );

          // Erro 1056 ou sucesso: ambos levam ao polling — o serviço pode já estar
          // subindo ou já estava ativo. Polling decide o resultado real.
          final shouldPoll =
              processResult.exitCode == _successExitCode ||
              isAlreadyRunning ||
              errorMessage.contains('SERVICE_ALREADY_RUNNING') ||
              errorMessage.contains('já está em execução');

          if (shouldPoll) {
            final effectiveTimeout =
                pollingTimeout ?? _timing.startPollingTimeout;
            final effectiveInterval =
                pollingInterval ?? _timing.startPollingInterval;
            final effectiveInitialDelay =
                initialDelay ?? _timing.startPollingInitialDelay;

            final runningAfterPoll = await _pollUntilRunning(
              timeout: effectiveTimeout,
              interval: effectiveInterval,
              initialDelay: effectiveInitialDelay,
              onConvergence: (d) => _metrics?.recordHistogram(
                ObservabilityMetrics.windowsServiceStartConvergenceSeconds,
                d.inMilliseconds / 1000,
              ),
            );

            if (runningAfterPoll) {
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceStartSuccess,
              );
              final label = isAlreadyRunning ? 'já estava em' : 'entrou em';
              LoggerService.info('Serviço $label execução');
              return const rd.Success(unit);
            }
            _appendControlDiagnostics(
              'startService: polling finished without RUNNING',
            );

            if (isAlreadyRunning) {
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceStartFailure,
              );
              return rd.Failure(
                ServerFailure(
                  message:
                      'O Windows reportou que o serviço já está em execução '
                      '(erro 1056), mas o status não retornou RUNNING '
                      'após ${effectiveTimeout.inSeconds}s de verificação.\n\n'
                      'Tente:\n'
                      '1. Atualizar o status\n'
                      '2. Reiniciar o serviço\n'
                      '3. Verificar os logs em $_logPath',
                ),
              );
            }

            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceStartFailure,
            );
            return rd.Failure(
              ServerFailure(
                message:
                    'Serviço não atingiu estado RUNNING dentro do tempo esperado '
                    '(${effectiveTimeout.inSeconds}s).\n\n'
                    'Tente:\n'
                    '1. Atualizar o status\n'
                    '2. Verificar os logs em $_logPath '
                    '(service_stdout.log e service_stderr.log)\n'
                    '3. Se o serviço falha ao iniciar: verifique se existe '
                    'arquivo .env na pasta do aplicativo (copie de .env.example)',
              ),
            );
          }

          final isAccessDenied =
              processResult.exitCode == _accessDeniedWinError ||
              errorMessage.contains('Acesso negado') ||
              errorMessage.contains('Access denied') ||
              errorMessage.contains('Access is denied') ||
              errorMessage.contains('FALHA 5') ||
              errorMessage.contains('FAILURE 5');

          if (isAccessDenied) {
            LoggerService.warning(
              'Acesso negado ao iniciar serviço; solicitando elevação UAC',
            );

            final elevatedResult = await _startServiceWithElevation(
              scCommand: scCommand,
              pollingTimeout: pollingTimeout ?? _timing.startPollingTimeout,
              pollingInterval: pollingInterval ?? _timing.startPollingInterval,
              initialDelay: initialDelay ?? _timing.startPollingInitialDelay,
            );

            return elevatedResult.fold(
              (_) {
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceStartSuccess,
                );
                LoggerService.info(
                  'Serviço iniciado com sucesso após elevação UAC',
                );
                return const rd.Success(unit);
              },
              (failure) {
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceStartFailure,
                );
                return rd.Failure(failure);
              },
            );
          }

          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStartFailure,
          );
          return rd.Failure(
            ServerFailure(
              message:
                  'Erro ao iniciar serviço: $errorMessage\n\n$_troubleshootingWithEnv',
            ),
          );
        },
        (f) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStartFailure,
          );
          return rd.Failure(f);
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar serviço', e, stackTrace);
      _metrics?.incrementCounter(
        ObservabilityMetrics.windowsServiceStartFailure,
      );
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao iniciar serviço: $e\n\n$_troubleshootingWithEnv',
        ),
      );
    }
  }

  Future<rd.Result<void>> _startServiceWithElevation({
    required String scCommand,
    required Duration pollingTimeout,
    required Duration pollingInterval,
    required Duration initialDelay,
  }) async {
    final elevatedCommand =
        r'$process = Start-Process -FilePath "sc.exe" '
        '-ArgumentList "$scCommand $_serviceName" '
        r'-Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $process.ExitCode';

    final result = await _processService.run(
      executable: 'powershell',
      arguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevatedCommand,
      ],
      timeout: _timing.longTimeout,
    );

    return result.fold(
      (processResult) async {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        if (processResult.exitCode != _successExitCode) {
          final normalizedOutput = output.toLowerCase();
          final wasCancelled =
              normalizedOutput.contains('canceled by the user') ||
              normalizedOutput.contains('cancelada pelo usuário') ||
              normalizedOutput.contains('cancelado pelo usuário') ||
              normalizedOutput.contains('foi cancelada pelo usuário');

          if (wasCancelled) {
            return const rd.Failure(
              ValidationFailure(
                message:
                    'A solicitação de permissões de Administrador foi '
                    'cancelada. Para iniciar o serviço, confirme o prompt UAC.',
              ),
            );
          }

          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao iniciar serviço com elevação UAC '
                  '(exit ${processResult.exitCode}). Saída: $output',
            ),
          );
        }

        final runningAfterPoll = await _pollUntilRunning(
          timeout: pollingTimeout,
          interval: pollingInterval,
          initialDelay: initialDelay,
          onConvergence: (d) => _metrics?.recordHistogram(
            ObservabilityMetrics.windowsServiceStartConvergenceSeconds,
            d.inMilliseconds / 1000,
          ),
        );

        if (!runningAfterPoll) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Comando elevado executado, mas o serviço não atingiu '
                  'RUNNING dentro de ${pollingTimeout.inSeconds}s.\n\n'
                  'Tente:\n'
                  '1. Atualizar o status\n'
                  '2. Verificar os logs em $_logPath '
                  '(service_stdout.log e service_stderr.log)\n'
                  '3. Confirmar que o prompt UAC foi aceito',
            ),
          );
        }

        return const rd.Success(unit);
      },
      (failure) {
        return Future.value(
          rd.Failure(
            ServerFailure(
              message:
                  'Não foi possível solicitar elevação UAC para iniciar '
                  'o serviço: $failure',
            ),
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> _stopServiceWithElevation({
    required Duration pollingTimeout,
    required Duration pollingInterval,
  }) async {
    const elevatedCommand =
        r'$process = Start-Process -FilePath "sc.exe" '
        '-ArgumentList "stop $_serviceName" '
        r'-Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $process.ExitCode';

    final result = await _processService.run(
      executable: 'powershell',
      arguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevatedCommand,
      ],
      timeout: _timing.longTimeout,
    );

    return result.fold(
      (processResult) async {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        if (processResult.exitCode != _successExitCode) {
          if (_wasUacCancelled(output)) {
            return const rd.Failure(
              ValidationFailure(
                message:
                    'A solicitação de permissões de Administrador foi '
                    'cancelada. Para parar o serviço, confirme o prompt UAC.',
              ),
            );
          }
          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao parar serviço com elevação UAC '
                  '(exit ${processResult.exitCode}). Saída: $output',
            ),
          );
        }

        final stoppedAfterPoll = await _pollUntilStopped(
          timeout: pollingTimeout,
          interval: pollingInterval,
          onConvergence: (d) => _metrics?.recordHistogram(
            ObservabilityMetrics.windowsServiceStopConvergenceSeconds,
            d.inMilliseconds / 1000,
          ),
        );

        if (!stoppedAfterPoll) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Comando elevado executado, mas o serviço não atingiu '
                  'STOPPED dentro de ${pollingTimeout.inSeconds}s.\n\n'
                  'Tente:\n'
                  '1. Atualizar o status\n'
                  '2. Verificar os logs em $_logPath\n'
                  '3. Confirmar que o prompt UAC foi aceito',
            ),
          );
        }

        return const rd.Success(unit);
      },
      (failure) {
        return Future.value(
          rd.Failure(
            ServerFailure(
              message:
                  'Não foi possível solicitar elevação UAC para parar '
                  'o serviço: $failure',
            ),
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> _uninstallWithElevation() async {
    const elevatedCommand =
        r'$process = Start-Process -FilePath "cmd.exe" '
        '-ArgumentList "/c sc stop $_serviceName & sc delete $_serviceName" '
        r'-Verb RunAs -WindowStyle Hidden -PassThru -Wait; exit $process.ExitCode';

    final result = await _processService.run(
      executable: 'powershell',
      arguments: [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        elevatedCommand,
      ],
      timeout: _timing.longTimeout,
    );

    return result.fold(
      (processResult) async {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        if (processResult.exitCode != _successExitCode) {
          if (_wasUacCancelled(output)) {
            return const rd.Failure(
              ValidationFailure(
                message:
                    'A solicitação de permissões de Administrador foi '
                    'cancelada. Para remover o serviço, confirme o prompt UAC.',
              ),
            );
          }
          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao remover serviço com elevação UAC '
                  '(exit ${processResult.exitCode}). Saída: $output',
            ),
          );
        }

        final postStatus = await getStatus();
        return postStatus.fold(
          (status) {
            if (status.isInstalled) {
              return const rd.Failure(
                ServerFailure(
                  message:
                      'O comando elevado foi executado, mas o serviço '
                      'ainda está registrado. Tente remover manualmente '
                      'via services.msc.',
                ),
              );
            }
            return const rd.Success(unit);
          },
          rd.Failure.new,
        );
      },
      (failure) {
        return Future.value(
          rd.Failure(
            ServerFailure(
              message:
                  'Não foi possível solicitar elevação UAC para remover '
                  'o serviço: $failure',
            ),
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> _installWithElevation({
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

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final scriptPath = p.join(
      Directory.systemTemp.path,
      'backup_db_install_$timestamp.ps1',
    );
    final installLogPath =
        '$programData\\BackupDatabase\\logs\\install_elevated_$timestamp.log';

    String safePath(String s) => s.replaceAll("'", "''");
    final scriptContent = '''
\$ErrorActionPreference = "Stop"
if (Get-Variable PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
  \$PSNativeCommandUseErrorActionPreference = \$false
}
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

if (-not (Test-Path \$logDir)) { New-Item -ItemType Directory -Path \$logDir -Force | Out-Null }
if (-not (Test-Path \$logPath)) { New-Item -ItemType Directory -Path \$logPath -Force | Out-Null }

try {
  sc.exe query $_serviceName 2>\$null | Out-Null
  if (\$LASTEXITCODE -eq 0) {
    & \$nssmPath remove $_serviceName confirm 2>\$null | Out-Null
    Start-Sleep -Seconds 2
  }

  \$r = & \$nssmPath install $_serviceName \$appPath 2>&1
  if (\$LASTEXITCODE -ne 0) { Fail "install" (\$r -join " ") }

  Start-Sleep -Seconds 5

  \$configErr = \$null
  foreach (\$attempt in 1..3) {
    \$r = & \$nssmPath set $_serviceName AppParameters "--minimized --mode=server --run-as-service" 2>&1
    if (\$LASTEXITCODE -eq 0) { \$configErr = \$null; break }
    \$configErr = \$r -join " "
    if (\$configErr -notmatch "Can't open service") { Fail "AppParameters" \$configErr }
    Start-Sleep -Seconds 2
  }
  if (\$configErr) { Fail "AppParameters" "Can't open service após 3 tentativas: \$configErr" }

  \$r = & \$nssmPath set $_serviceName AppDirectory \$appDir 2>&1
  if (\$LASTEXITCODE -ne 0) { Fail "AppDirectory" (\$r -join " ") }
  \$r = & \$nssmPath set $_serviceName AppEnvironmentExtra "SERVICE_MODE=server" 2>&1
  if (\$LASTEXITCODE -ne 0) { Fail "AppEnvironmentExtra" (\$r -join " ") }
  \$r = & \$nssmPath set $_serviceName AppStdout "\$logPath\\service_stdout.log" 2>&1
  if (\$LASTEXITCODE -ne 0) { Fail "AppStdout" (\$r -join " ") }
  \$r = & \$nssmPath set $_serviceName AppStderr "\$logPath\\service_stderr.log" 2>&1
  if (\$LASTEXITCODE -ne 0) { Fail "AppStderr" (\$r -join " ") }
  & \$nssmPath set $_serviceName DisplayName "$_displayName" | Out-Null
  & \$nssmPath set $_serviceName Description "$_description" | Out-Null
  & \$nssmPath set $_serviceName Start SERVICE_AUTO_START | Out-Null
  & \$nssmPath set $_serviceName AppExit Default Restart | Out-Null
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
      timeout: _timing.longTimeout,
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
      await scriptFile.delete();
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

        final postStatus = await getStatus();
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
    const logsDir = r'C:\ProgramData\BackupDatabase\logs';
    final dir = Directory(logsDir);
    if (!await dir.exists()) {
      return 'Pasta de logs não encontrada: $logsDir';
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

      for (final f in files.take(5)) {
        try {
          final content = await f.readAsString();
          if (content.trim().isNotEmpty) {
            buffer.writeln('--- ${f.path} ---');
            buffer.writeln(content.trim().length > 2000
                ? '${content.trim().substring(0, 2000)}...'
                : content.trim());
            buffer.writeln();
          }
        } on Object catch (_) {}
      }
    } on Object catch (e) {
      return 'Erro ao ler $logsDir: $e';
    }

    final result = buffer.toString().trim();
    return result.isNotEmpty ? result : 'Nenhum log encontrado em $logsDir';
  }

  bool _wasUacCancelled(String output) {
    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('canceled by the user') ||
        normalizedOutput.contains('cancelada pelo usuário') ||
        normalizedOutput.contains('cancelado pelo usuário') ||
        normalizedOutput.contains('foi cancelada pelo usuário');
  }

  /// Verifica se a saída do sc query indica estado RUNNING.
  /// Suporta locale EN (RUNNING) e PT-BR (EM EXECUÇÃO), além do código 4.
  bool _isRunningState(String stdout) {
    final upper = stdout.toUpperCase();
    return upper.contains(_runningState) ||
        upper.contains(_runningStatePt.toUpperCase()) ||
        upper.contains(_runningStatePtNoAccent) ||
        _runningStateRegex.hasMatch(stdout);
  }

  WindowsServiceStateCode? _parseStateCode(String stdout) {
    final match = _stateCodeRegex.firstMatch(stdout);
    if (match == null) return null;
    final code = int.tryParse(match.group(1) ?? '');
    return code != null ? WindowsServiceStateCode.fromCode(code) : null;
  }

  /// Verifica em loop se o serviço entrou em estado RUNNING.
  /// Retorna `true` assim que detectar, ou `false` se o [timeout] esgotar.
  /// Se [onConvergence] for fornecido, é chamado com a duração ao atingir RUNNING.
  Future<bool> _pollUntilRunning({
    required Duration timeout,
    required Duration interval,
    Duration initialDelay = Duration.zero,
    void Function(Duration)? onConvergence,
  }) async {
    final stopwatch = Stopwatch()..start();
    var pollCount = 0;
    if (initialDelay > Duration.zero) {
      await Future.delayed(initialDelay);
    }
    final deadline = DateTime.now().add(timeout);
    rd.Result<WindowsServiceStatus>? lastStatusResult;

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      pollCount++;
      lastStatusResult = await getStatus();
      final status = lastStatusResult.getOrNull();
      _appendControlDiagnostics(
        '_pollUntilRunning: poll=$pollCount installed=${status?.isInstalled} '
        'running=${status?.isRunning} state=${status?.stateCode?.name}',
      );
      if (status?.isRunning ?? false) {
        onConvergence?.call(stopwatch.elapsed);
        _appendControlDiagnostics(
          '_pollUntilRunning: converged in ${stopwatch.elapsedMilliseconds}ms',
        );
        return true;
      }
    }

    if (lastStatusResult != null) {
      final lastStatus = lastStatusResult.getOrNull();
      LoggerService.warning(
        'Timeout ao aguardar RUNNING. Último status: '
        'isInstalled=${lastStatus?.isInstalled}, '
        'isRunning=${lastStatus?.isRunning}, '
        'stateCode=${lastStatus?.stateCode?.name}',
      );
      _appendControlDiagnostics(
        '_pollUntilRunning: timeout after ${stopwatch.elapsedMilliseconds}ms '
        'lastState=${lastStatus?.stateCode?.name}',
      );
    }
    return false;
  }

  /// Verifica em loop se o serviço entrou em estado parado (não RUNNING).
  /// Se [onConvergence] for fornecido, é chamado com a duração ao parar.
  Future<bool> _pollUntilStopped({
    required Duration timeout,
    required Duration interval,
    void Function(Duration)? onConvergence,
  }) async {
    final stopwatch = Stopwatch()..start();
    var pollCount = 0;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(interval);
      pollCount++;
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();
      _appendControlDiagnostics(
        '_pollUntilStopped: poll=$pollCount installed=${status?.isInstalled} '
        'running=${status?.isRunning} state=${status?.stateCode?.name}',
      );
      if (_isServiceStopped(status)) {
        onConvergence?.call(stopwatch.elapsed);
        _appendControlDiagnostics(
          '_pollUntilStopped: converged in ${stopwatch.elapsedMilliseconds}ms',
        );
        return true;
      }
    }
    _appendControlDiagnostics(
      '_pollUntilStopped: timeout after ${stopwatch.elapsedMilliseconds}ms',
    );
    return false;
  }

  @override
  Future<rd.Result<void>> stopService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();

      final isStartPending =
          status?.stateCode == WindowsServiceStateCode.startPending;
      final isStopPending =
          status?.stateCode == WindowsServiceStateCode.stopPending;
      final isStopped = _isServiceStopped(status);

      if (isStopped && !isStartPending) {
        if (isStopPending) {
          LoggerService.info('Serviço em STOP_PENDING, aguardando parada');
          final stoppedAfterPoll = await _pollUntilStopped(
            timeout: _timing.longTimeout,
            interval: _timing.startPollingInterval,
            onConvergence: (d) => _metrics?.recordHistogram(
              ObservabilityMetrics.windowsServiceStopConvergenceSeconds,
              d.inMilliseconds / 1000,
            ),
          );
          if (stoppedAfterPoll) {
            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceStopSuccess,
            );
            LoggerService.info('Serviço parado com sucesso');
            return const rd.Success(unit);
          }
        }
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceStopSuccess,
        );
        LoggerService.info('Serviço já está parado');
        return const rd.Success(unit);
      }

      if (isStartPending) {
        LoggerService.info('Serviço em START_PENDING, enviando comando stop');
      }

      final result = await _runScWithRetry(
        arguments: ['stop', _serviceName],
        timeout: _timing.longTimeout,
        operationName: 'sc stop',
      );

      return result.fold(
        (processResult) async {
          await Future.delayed(_timing.serviceDelay);

          final statusAfterResult = await getStatus();
          final statusAfter = statusAfterResult.getOrNull();

          if (statusAfter?.isRunning != true) {
            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceStopSuccess,
            );
            LoggerService.info('Serviço parado com sucesso');
            return const rd.Success(unit);
          }

          final errorMessage = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;

          final isAccessDenied =
              errorMessage.contains('Acesso negado') ||
              errorMessage.contains('Access denied') ||
              errorMessage.contains('FALHA 5') ||
              errorMessage.contains('FAILURE 5');

          if (isAccessDenied) {
            LoggerService.warning(
              'Acesso negado ao parar serviço; solicitando elevação UAC',
            );
            final elevatedStopResult = await _stopServiceWithElevation(
              pollingTimeout: _timing.longTimeout,
              pollingInterval: _timing.startPollingInterval,
            );
            return elevatedStopResult.fold(
              (_) {
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceStopSuccess,
                );
                LoggerService.info(
                  'Serviço parado com sucesso após elevação UAC',
                );
                return const rd.Success(unit);
              },
              (failure) {
                _metrics?.incrementCounter(
                  ObservabilityMetrics.windowsServiceStopFailure,
                );
                return rd.Failure(failure);
              },
            );
          }

          if (processResult.exitCode == _successExitCode) {
            await Future.delayed(_timing.serviceDelay);
            final finalStatusResult = await getStatus();
            final finalStatus = finalStatusResult.getOrNull();

            if (finalStatus?.isRunning != true) {
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceStopSuccess,
              );
              LoggerService.info('Serviço parado com sucesso');
              return const rd.Success(unit);
            }
          }

          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStopFailure,
          );
          return rd.Failure(
            ServerFailure(
              message:
                  'Erro ao parar serviço: $errorMessage\n\n$_troubleshootingAdminLogs',
            ),
          );
        },
        (f) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStopFailure,
          );
          return rd.Failure(f);
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao parar serviço', e, stackTrace);
      _metrics?.incrementCounter(
        ObservabilityMetrics.windowsServiceStopFailure,
      );
      return rd.Failure(
        ServerFailure(
          message: 'Erro ao parar serviço: $e\n\n$_troubleshootingAdminLogs',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> restartService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    final stopResult = await stopService();
    return stopResult.fold(
      (_) async {
        await Future.delayed(_timing.serviceDelay);
        final startResult = await startService();
        return startResult.fold(
          (_) {
            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceRestartSuccess,
            );
            return const rd.Success(unit);
          },
          (f) {
            _metrics?.incrementCounter(
              ObservabilityMetrics.windowsServiceRestartFailure,
            );
            return rd.Failure(f);
          },
        );
      },
      (f) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceRestartFailure,
        );
        return Future.value(rd.Failure(f));
      },
    );
  }

  bool _isServiceNotInstalledResponse(ProcessResult processResult) {
    if (processResult.exitCode == _serviceNotInstalledWinError ||
        processResult.exitCode == _serviceNotInstalledBatchError) {
      return true;
    }

    final output = _getProcessOutput(processResult).toLowerCase();
    return output.contains('1060') ||
        output.contains('does not exist as an installed service') ||
        output.contains('specified service does not exist') ||
        output.contains('nao existe como servico instalado') ||
        output.contains('não existe como serviço instalado');
  }

  bool _isAccessDeniedResponse(ProcessResult processResult) {
    if (processResult.exitCode == _accessDeniedWinError) {
      return true;
    }

    final output = _getProcessOutput(processResult).toLowerCase();
    return output.contains('access is denied') ||
        output.contains('acesso negado') ||
        output.contains('falha 5') ||
        output.contains('failure 5');
  }

  bool _isServiceAlreadyRunningResponse(
    ProcessResult processResult,
    String output,
  ) {
    if (processResult.exitCode == _serviceAlreadyRunningWinError) {
      return true;
    }

    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('1056') ||
        normalizedOutput.contains('already running') ||
        normalizedOutput.contains('já está em execução') ||
        normalizedOutput.contains('ja esta em execucao') ||
        normalizedOutput.contains('uma copia deste serv') ||
        normalizedOutput.contains('uma cópia deste serv');
  }

  String _getProcessOutput(ProcessResult processResult) {
    final stderr = processResult.stderr.trim();
    final stdout = processResult.stdout.trim();
    if (stderr.isNotEmpty && stdout.isNotEmpty) {
      return '$stderr | $stdout';
    }
    if (stderr.isNotEmpty) {
      return stderr;
    }
    if (stdout.isNotEmpty) {
      return stdout;
    }
    return 'sem saída';
  }

  bool _isServiceStopped(WindowsServiceStatus? status) {
    if (status == null) {
      return false;
    }
    if (!status.isInstalled) {
      return true;
    }
    return status.stateCode == WindowsServiceStateCode.stopped;
  }

  void _appendControlDiagnostics(String message, {String? output}) {
    try {
      final logDir = Directory(_logPath);
      if (!logDir.existsSync()) {
        logDir.createSync(recursive: true);
      }
      final file = File(_controlDiagnosticsPath);
      final ts = DateTime.now().toIso8601String();
      final buffer = StringBuffer('[$ts] $message');
      if (output != null && output.trim().isNotEmpty) {
        final trimmed = output.trim();
        const maxChars = 3000;
        final safeOutput = trimmed.length > maxChars
            ? '${trimmed.substring(0, maxChars)}...'
            : trimmed;
        buffer.write('\noutput: $safeOutput');
      }
      buffer.write('\n');
      file.writeAsStringSync(
        buffer.toString(),
        mode: FileMode.append,
        flush: true,
      );
    } on Object {
      // best-effort diagnostics only
    }
  }
}
