import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_controller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_failure.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_messages.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_sc_client.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceLifecycleOrchestrator {
  WindowsServiceLifecycleOrchestrator({
    required this._timing,
    required this._scClient,
    required this._scmPoller,
    required this._elevationController,
    required this._getStatus,
    required this._appendDiagnostics,
    IMetricsCollector? metricsCollector,
  }) : _metrics = metricsCollector;

  final WindowsServiceTimingConfig _timing;
  final WindowsServiceScClient _scClient;
  final WindowsServiceScmPoller _scmPoller;
  final WindowsServiceElevationController _elevationController;
  final WindowsServiceStatusSupplier _getStatus;
  final WindowsServiceDiagnosticsSink _appendDiagnostics;
  final IMetricsCollector? _metrics;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const String _logPath = WindowsServiceConstants.logPath;
  static const int _accessDeniedWinError = 5;

  Future<rd.Result<void>> start({
    Duration? pollingTimeout,
    Duration? pollingInterval,
    Duration? initialDelay,
  }) async {
    try {
      _appendDiagnostics(
        'startService: begin timeout='
        '${(pollingTimeout ?? _timing.startPollingTimeout).inSeconds}s '
        'interval='
        '${(pollingInterval ?? _timing.startPollingInterval).inMilliseconds}ms '
        'initialDelay='
        '${(initialDelay ?? _timing.startPollingInitialDelay).inMilliseconds}ms',
      );
      final statusResult = await _getStatus();
      final status = statusResult.getOrNull();
      _appendDiagnostics(
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
                'dentro do tempo esperado.\n\n'
                '${WindowsServiceMessages.troubleshootingWithEnv}',
          ),
        );
      }

      final isPaused = status?.stateCode?.isPaused ?? false;
      if (isPaused) {
        LoggerService.warning(
          'Serviço em PAUSED. Aplicando recuperação: STOP completo e START',
        );
        _appendDiagnostics(
          'startService: detected PAUSED, executing stop+start recovery',
        );
        final stopResult = await stop();
        final stopFailure = stopResult.exceptionOrNull();
        if (stopFailure != null) {
          _metrics?.incrementCounter(
            ObservabilityMetrics.windowsServiceStartFailure,
          );
          return rd.Failure(windowsServiceAsFailure(stopFailure));
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
          _appendDiagnostics(
            'startService: sc $scCommand exit=${processResult.exitCode}',
            output: errorMessage,
          );

          final isAlreadyRunning = _scClient.isServiceAlreadyRunningResponse(
            processResult,
            errorMessage,
          );

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
            _appendDiagnostics(
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
                    'Serviço não atingiu estado RUNNING dentro do tempo '
                    'esperado (${effectiveTimeout.inSeconds}s).\n\n'
                    'Tente:\n'
                    '1. Atualizar o status\n'
                    '2. Verificar os logs em $_logPath '
                    '(service_stdout.log e service_stderr.log)\n'
                    '3. Se o serviço falha ao iniciar: verifique se existe '
                    r'arquivo .env em C:\ProgramData\BackupDatabase\config '
                    '(copie de .env.example se necessario)',
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
                  'Erro ao iniciar serviço: $errorMessage\n\n'
                  '${WindowsServiceMessages.troubleshootingWithEnv}',
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
          message:
              'Erro ao iniciar serviço: $e\n\n'
              '${WindowsServiceMessages.troubleshootingWithEnv}',
        ),
      );
    }
  }

  Future<rd.Result<void>> stop() async {
    try {
      final statusResult = await _getStatus();
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

          final statusAfterResult = await _getStatus();
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
            final finalStatusResult = await _getStatus();
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
                  'Erro ao parar serviço: $errorMessage\n\n'
                  '${WindowsServiceMessages.troubleshootingAdminLogs}',
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
          message:
              'Erro ao parar serviço: $e\n\n'
              '${WindowsServiceMessages.troubleshootingAdminLogs}',
        ),
      );
    }
  }

  Future<rd.Result<void>> restart() async {
    final stopResult = await stop();
    return stopResult.fold(
      (_) async {
        await Future.delayed(_timing.serviceDelay);
        final startResult = await start();
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
}
