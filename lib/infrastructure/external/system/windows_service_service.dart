import 'dart:io';

import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/appending_file_sink.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_controller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_installer.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_env_provisioner.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_nssm_configurator.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_sc_client.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:result_dart/result_dart.dart'
    as rd
    show Failure, Result, Success;
import 'package:result_dart/result_dart.dart' show unit;

export 'windows_service/windows_service_timing_config.dart';

class WindowsServiceService implements IWindowsServiceService {
  WindowsServiceService(
    this._processService, {
    WindowsServiceTimingConfig? timingConfig,
    IMetricsCollector? metricsCollector,
    WindowsServiceNssmConfigurator? nssmConfigurator,
    WindowsServiceScmPoller? scmPoller,
    WindowsServiceElevationInstaller? elevationInstaller,
    WindowsServiceEnvProvisioner? envProvisioner,
    WindowsServiceScClient? scClient,
    WindowsServiceElevationController? elevationController,
  }) : _timing = timingConfig ?? WindowsServiceTimingConfig.defaultConfig,
       _metrics = metricsCollector,
       _nssmConfigurator =
           nssmConfigurator ??
           WindowsServiceNssmConfigurator(
             processService: _processService,
             timing: timingConfig ?? WindowsServiceTimingConfig.defaultConfig,
           ),
       _envProvisioner = envProvisioner ?? const WindowsServiceEnvProvisioner(),
       _scClient =
           scClient ??
           WindowsServiceScClient(
             processService: _processService,
             timing: timingConfig ?? WindowsServiceTimingConfig.defaultConfig,
             metricsCollector: metricsCollector,
           ),
       _diagnosticsSink = AppendingFileSink(
         path: _controlDiagnosticsPath,
         maxFileSize: 1 * 1024 * 1024,
         maxFiles: 3,
       ) {
    _scmPoller =
        scmPoller ??
        WindowsServiceScmPoller(
          getStatus: getStatus,
          appendDiagnostics: _appendControlDiagnostics,
        );
    _elevationInstaller =
        elevationInstaller ??
        WindowsServiceElevationInstaller(
          processService: _processService,
          getStatus: getStatus,
          timing: _timing,
        );
    _elevationController =
        elevationController ??
        WindowsServiceElevationController(
          processService: _processService,
          getStatus: getStatus,
          scmPoller: _scmPoller,
          timing: _timing,
          metricsCollector: _metrics,
        );
  }

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;
  final IMetricsCollector? _metrics;
  final WindowsServiceNssmConfigurator _nssmConfigurator;
  final WindowsServiceEnvProvisioner _envProvisioner;
  final WindowsServiceScClient _scClient;
  late final WindowsServiceScmPoller _scmPoller;
  late final WindowsServiceElevationInstaller _elevationInstaller;
  late final WindowsServiceElevationController _elevationController;

  /// Sink dedicado de diagnostics, com fila serializada e rotação por
  /// tamanho. Substitui o `File.writeAsStringSync(flush: true)` síncrono
  /// (S2.5 da auditoria — bloqueava event loop) e a versão async
  /// fire-and-forget (S4 — race de interleaving).
  final AppendingFileSink _diagnosticsSink;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const String _displayName = WindowsServiceConstants.displayName;
  static const int _successExitCode = 0;

  /// Exit code retornado pelo `nssm remove confirm` quando o serviço já
  /// não está registrado. Anteriormente era `_serviceNotFoundExitCode`,
  /// nome genérico que confundia com `_serviceNotInstalledWinError`
  /// (1060), retornado pelo `sc.exe` em situação parecida.
  static const int _nssmServiceNotFoundExitCode = 3;
  static const String _nssmExeName = 'nssm.exe';
  static const String _toolsSubdir = 'tools';
  static const String _logPath = WindowsServiceConstants.logPath;
  static const String _controlDiagnosticsPath =
      r'C:\ProgramData\BackupDatabase\logs\service_control_diagnostics.log';

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
      r'2. Verificar se existe C:\ProgramData\BackupDatabase\config\.env'
      '\n'
      '3. Verificar logs em $_logPath (service_stdout.log, service_stderr.log)\n'
      '4. Atualizar o status e tentar novamente';
  static const int _accessDeniedWinError = 5;

  Future<rd.Result<void>> _runInstallPreflight({
    required String appDir,
  }) async {
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
        return rd.Failure(_asFailure(statusFailure));
      }
    }

    final envCopyResult = await _envProvisioner.ensureServiceEnvFile(
      appDir: appDir,
    );
    if (envCopyResult.isError()) {
      return rd.Failure(_asFailure(envCopyResult.exceptionOrNull()!));
    }

    try {
      Directory(_logPath).createSync(recursive: true);
    } on Object catch (e) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Diretório de logs não pôde ser criado: $_logPath\n\n'
              'Erro: $e\n\n'
              'Tente:\n'
              '1. Executar como Administrador\n'
              '2. Verificar permissões da pasta $_logPath',
        ),
      );
    }

    final hasWritePermission =
        await DirectoryPermissionCheck.hasWritePermissionForPath(_logPath);
    if (!hasWritePermission) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Diretório de logs não é gravável: $_logPath\n\n'
              'Tente:\n'
              '1. Executar como Administrador\n'
              '2. Verificar permissões da pasta $_logPath',
        ),
      );
    }

    return const rd.Success(unit);
  }

  @visibleForTesting
  Future<rd.Result<void>> ensureServiceEnvFileForTesting({
    required String appDir,
    String? configDirOverride,
  }) => _envProvisioner.ensureServiceEnvFile(
    appDir: appDir,
    configDirOverride: configDirOverride,
  );

  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final result = await _scClient.runWithRetry(
        arguments: ['query', _serviceName],
        timeout: _timing.shortTimeout,
        operationName: 'sc query',
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == _successExitCode) {
            final stdout = processResult.stdout;
            final isRunning = _scClient.isRunningState(stdout);
            final stateCode = _scClient.parseStateCode(stdout);
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

          if (_scClient.isServiceNotInstalledResponse(processResult)) {
            _appendControlDiagnostics(
              'getStatus: installed=false exit=${processResult.exitCode}',
              output: _scClient.getProcessOutput(processResult),
            );
            return const rd.Success(
              WindowsServiceStatus(
                isInstalled: false,
                isRunning: false,
              ),
            );
          }

          if (_scClient.isAccessDeniedResponse(processResult)) {
            return const rd.Failure(
              ServerFailure(
                message:
                    'Acesso negado ao consultar status do serviço. '
                    'Execute o aplicativo como Administrador.\n\n'
                    '$_accessDeniedSolution',
              ),
            );
          }

          final errorOutput = _scClient.getProcessOutput(processResult);
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

      final preflightResult = await _runInstallPreflight(appDir: appDir);
      final preflightFailure = preflightResult.exceptionOrNull();
      if (preflightFailure != null) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceInstallFailure,
        );
        return rd.Failure(_asFailure(preflightFailure));
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

            final isAccessDenied = _scClient.textContainsAccessDenied(
              errorMessage,
            );

            if (isAccessDenied) {
              LoggerService.warning(
                'Acesso negado ao instalar serviço; solicitando elevação UAC',
              );
              final elevatedResult = await _elevationInstaller.install(
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

          final configResult = await _nssmConfigurator.configure(
            nssmPath: nssmPath,
            serviceUser: serviceUser,
            servicePassword: servicePassword,
          );
          final configFailure = configResult.exceptionOrNull();
          if (configFailure != null) {
            final failureMsg = failureUserMessage(configFailure);
            final isConfigAccessDenied = _scClient.textContainsAccessDenied(
              failureMsg,
            );

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
              final elevatedResult = await _elevationInstaller.install(
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
            return rd.Failure(_asFailure(configFailure));
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

      await _scClient.run(
        arguments: ['stop', _serviceName],
        timeout: _timing.longTimeout,
      );

      // Aguarda STOPPED de verdade antes do `nssm remove`. Antes era um
      // `Future.delayed(_timing.serviceDelay)` (2s) — insuficiente quando
      // o `ServiceShutdownHandler` está aguardando backups (até 30s),
      // levando a `nssm remove` falhar silenciosamente ou deixar o
      // registro órfão (issue §2.4 da auditoria).
      await _scmPoller.pollUntilStopped(
        timeout: _timing.longTimeout,
        interval: _timing.startPollingInterval,
        onConvergence: (d) => _metrics?.recordHistogram(
          ObservabilityMetrics.windowsServiceStopConvergenceSeconds,
          d.inMilliseconds / 1000,
        ),
      );

      final removeResult = await _processService.run(
        executable: nssmPath,
        arguments: ['remove', _serviceName, 'confirm'],
        timeout: _timing.longTimeout,
      );

      return await removeResult.fold<Future<rd.Result<void>>>(
        (processResult) async {
          if (processResult.exitCode != _successExitCode &&
              processResult.exitCode != _nssmServiceNotFoundExitCode) {
            final errorMessage = processResult.stderr.isNotEmpty
                ? processResult.stderr
                : processResult.stdout;

            final isAccessDenied = _scClient.textContainsAccessDenied(
              errorMessage,
            );

            if (isAccessDenied) {
              LoggerService.warning(
                'Acesso negado ao remover serviço; solicitando elevação UAC',
              );
              final elevatedUninstallResult = await _elevationController
                  .uninstallWithElevation();
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
  @visibleForTesting
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
        final runningAfterPoll = await _scmPoller.pollUntilRunning(
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
          return rd.Failure(_asFailure(stopFailure));
        }
        await Future.delayed(_timing.serviceDelay);
      }
      const scCommand = 'start';

      final result = await _scClient.runWithRetry(
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

          final isAlreadyRunning = _scClient.isServiceAlreadyRunningResponse(
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

            final runningAfterPoll = await _scmPoller.pollUntilRunning(
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
                    r'arquivo .env em C:\ProgramData\BackupDatabase\config (copie de .env.example se necessario)',
              ),
            );
          }

          final isAccessDenied =
              processResult.exitCode == _accessDeniedWinError ||
              _scClient.textContainsAccessDenied(errorMessage);

          if (isAccessDenied) {
            LoggerService.warning(
              'Acesso negado ao iniciar serviço; solicitando elevação UAC',
            );

            final elevatedResult = await _elevationController
                .startWithElevation(
                  scCommand: scCommand,
                  pollingTimeout: pollingTimeout ?? _timing.startPollingTimeout,
                  pollingInterval:
                      pollingInterval ?? _timing.startPollingInterval,
                  initialDelay:
                      initialDelay ?? _timing.startPollingInitialDelay,
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
      final isStopped = WindowsServiceScmPoller.isServiceStopped(status);

      if (isStopPending) {
        LoggerService.info('Serviço em STOP_PENDING, aguardando parada');
        final stoppedAfterPoll = await _scmPoller.pollUntilStopped(
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
        LoggerService.warning(
          'Serviço permaneceu em STOP_PENDING após timeout; '
          'tentando comando stop explicitamente',
        );
      }

      if (isStopped && !isStartPending) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceStopSuccess,
        );
        LoggerService.info('Serviço já está parado');
        return const rd.Success(unit);
      }

      if (isStartPending) {
        LoggerService.info('Serviço em START_PENDING, enviando comando stop');
      }

      final result = await _scClient.runWithRetry(
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

          final isAccessDenied = _scClient.textContainsAccessDenied(
            errorMessage,
          );

          if (isAccessDenied) {
            LoggerService.warning(
              'Acesso negado ao parar serviço; solicitando elevação UAC',
            );
            final elevatedStopResult = await _elevationController
                .stopWithElevation(
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

  /// Converte o `Object?` que sai de `Result.exceptionOrNull()` em
  /// `Failure` de forma segura. Os 3 call sites originais usavam
  /// `failure as Failure` (cast direto), que crashava quando vinha um
  /// `Exception` puro (ex.: erro do binding). Agora normalizamos
  /// preservando a mensagem e o erro original.
  Failure _asFailure(Object failure) {
    if (failure is Failure) return failure;
    return ServerFailure(
      message: failureUserMessage(failure),
      originalError: failure,
    );
  }

  /// Helper de testes — expõe os comandos NSSM que `_configureService`
  /// emitiria para uma combinação de `appDir`/`logPath`. Permite verificar
  /// (sem precisar mockar 11 chamadas separadas a `ProcessService`) que
  /// o plan declarativo cobre todas as chaves críticas — em particular,
  /// que `AppExit 78 Exit` e `AppNoConsole 1` não regrediram (S17).
  @visibleForTesting
  static List<List<String>> nssmInstallCommandsForTesting({
    required String appDir,
    required String logPath,
  }) {
    final plan = NssmConfigPlan.build(appDir: appDir, logPath: logPath);
    return plan.installCommandsFor(_serviceName);
  }

  void _appendControlDiagnostics(String message, {String? output}) {
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
    // Delegado ao sink: enfileirado em ordem, gravado em background com
    // rotação por tamanho. Não há race de interleaving entre callers
    // concorrentes nem bloqueio do event loop.
    _diagnosticsSink.append(buffer.toString());
  }

  /// Aguarda o sink de diagnostics drenar a fila atual. Usar em testes
  /// que validam o conteúdo escrito no log.
  @visibleForTesting
  Future<void> flushDiagnosticsForTesting() => _diagnosticsSink.flush();
}
