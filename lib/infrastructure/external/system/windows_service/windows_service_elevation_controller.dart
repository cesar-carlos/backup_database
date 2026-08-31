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

  void Function(bool waiting)? onElevationWaitChanged;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static String get _logPath => WindowsServiceConstants.logPath;

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

    final result = await _runElevatedPowerShell(
      elevatedCommand,
      timeout: _timing.uacPromptTimeout,
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
                  'o serviço: ${failureUserMessage(failure)}',
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

    final result = await _runElevatedPowerShell(
      elevatedCommand,
      timeout: _timing.uacPromptTimeout,
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
                  'o serviço: ${failureUserMessage(failure)}',
            ),
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> uninstallWithElevation({
    required String nssmPath,
  }) async {
    final delaySeconds = _timing.serviceDelay.inSeconds;
    final pollSeconds = _timing.longTimeout.inSeconds;
    final nssmPs = nssmPath.replaceAll('`', '``').replaceAll('"', '`"');
    final inner =
        '\$nssm = "$nssmPs"; '
        'sc.exe stop $_serviceName | Out-Null; '
        '\$deadline = (Get-Date).AddSeconds($pollSeconds); '
        'do { '
        '  \$q = sc.exe query $_serviceName 2>\$null | Out-String; '
        r"  if ($q -match 'STOPPED' -or $q -match 'PARADO') { break }; "
        '  Start-Sleep -Seconds 1 '
        r'} while ((Get-Date) -lt $deadline); '
        'Start-Sleep -Seconds $delaySeconds; '
        '& \$nssm remove $_serviceName confirm; '
        r'exit $LASTEXITCODE';
    final elevatedCommand =
        r'$p = Start-Process -FilePath "powershell.exe" '
        "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',"
        " '$inner' "
        '-Verb RunAs -WindowStyle Hidden -PassThru -Wait; '
        r'if ($null -eq $p) { exit 1223 }; exit $p.ExitCode';

    final result = await _runElevatedPowerShell(
      elevatedCommand,
      timeout: _timing.uacPromptTimeout + _timing.longTimeout,
    );

    return result.fold(
      (processResult) async {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        if (processResult.exitCode != _successExitCode) {
          if (_wasUacCancelled(output) || processResult.exitCode == 1223) {
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
                  '(exit ${processResult.exitCode}). '
                  'Saída: ${failureUserMessage(output, fallback: output)}',
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
                  'o serviço: ${failureUserMessage(failure)}',
            ),
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> scheduleStartAfterUiExit() async {
    final delaySeconds = _timing.serviceDelay.inSeconds;
    final inner =
        'Start-Sleep -Seconds $delaySeconds; '
        'sc.exe start $_serviceName';
    final elevatedCommand =
        'try { '
        r'$p = Start-Process -FilePath "powershell.exe" '
        "-ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command',"
        " '$inner' "
        '-Verb RunAs -WindowStyle Hidden -PassThru; '
        r'if ($null -eq $p) { exit 1223 }; exit 0 '
        '} catch { '
        r'$msg = [string]$_.Exception.Message; '
        r"if ($msg -match 'canceled|cancelad') { exit 1223 }; "
        r'Write-Error $msg; exit 1 }';

    final result = await _runElevatedPowerShell(
      elevatedCommand,
      timeout: _timing.uacPromptTimeout,
    );

    return result.fold(
      (processResult) {
        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        if (processResult.exitCode == 1223 || _wasUacCancelled(output)) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'A solicitação de permissões de Administrador foi '
                  'cancelada. O aplicativo não será fechado. Confirme o '
                  'prompt UAC para iniciar o serviço após fechar.',
            ),
          );
        }
        if (processResult.exitCode != _successExitCode) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Não foi possível agendar o início do serviço após fechar '
                  'o aplicativo (exit ${processResult.exitCode}). '
                  'Saída: ${failureUserMessage(output, fallback: output)}',
            ),
          );
        }
        return const rd.Success(unit);
      },
      (failure) => rd.Failure(
        ServerFailure(
          message:
              'Não foi possível solicitar elevação UAC para iniciar o '
              'serviço após fechar: ${failureUserMessage(failure)}',
        ),
      ),
    );
  }

  Future<rd.Result<ProcessResult>> _runElevatedPowerShell(
    String elevatedCommand, {
    required Duration timeout,
  }) async {
    onElevationWaitChanged?.call(true);
    try {
      return await _processService.run(
        executable: 'powershell',
        arguments: [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          elevatedCommand,
        ],
        timeout: timeout,
      );
    } finally {
      onElevationWaitChanged?.call(false);
    }
  }

  bool _wasUacCancelled(String output) {
    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('canceled by the user') ||
        normalizedOutput.contains('cancelada pelo usuário') ||
        normalizedOutput.contains('cancelado pelo usuário') ||
        normalizedOutput.contains('foi cancelada pelo usuário');
  }
}
