import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceElevationController {
  WindowsServiceElevationController({
    required this._processService,
    required this._getStatus,
    required this._scmPoller,
    WindowsServiceTimingConfig? timing,
    IMetricsCollector? metricsCollector,
  }) : _timing = timing ?? WindowsServiceTimingConfig.defaultConfig,
       _metrics = metricsCollector;

  final ProcessService _processService;
  final WindowsServiceStatusSupplier _getStatus;
  final WindowsServiceScmPoller _scmPoller;
  final WindowsServiceTimingConfig _timing;
  final IMetricsCollector? _metrics;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const String _logPath = WindowsServiceConstants.logPath;

  Future<rd.Result<void>> startWithElevation({
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

        final runningAfterPoll = await _scmPoller.pollUntilRunning(
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

  Future<rd.Result<void>> stopWithElevation({
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

        final stoppedAfterPoll = await _scmPoller.pollUntilStopped(
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

  Future<rd.Result<void>> uninstallWithElevation() async {
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

        final postStatus = await _getStatus();
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

  bool _wasUacCancelled(String output) {
    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('canceled by the user') ||
        normalizedOutput.contains('cancelada pelo usuário') ||
        normalizedOutput.contains('cancelado pelo usuário') ||
        normalizedOutput.contains('foi cancelada pelo usuário');
  }
}
