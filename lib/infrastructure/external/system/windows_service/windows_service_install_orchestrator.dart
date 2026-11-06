import 'dart:io';

import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_controller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_installer.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_env_provisioner.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_failure.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_messages.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_sc_client.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceInstallOrchestrator {
  WindowsServiceInstallOrchestrator({
    required this._processService,
    required this._timing,
    required this._envProvisioner,
    required this._scClient,
    required this._scmPoller,
    required this._elevationInstaller,
    required this._elevationController,
    required this._getStatus,
    IMetricsCollector? metricsCollector,
    @visibleForTesting this.nssmPathOverride,
  }) : _metrics = metricsCollector;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;

  final WindowsServiceEnvProvisioner _envProvisioner;
  final WindowsServiceScClient _scClient;
  final WindowsServiceScmPoller _scmPoller;
  final WindowsServiceElevationInstaller _elevationInstaller;
  final WindowsServiceElevationController _elevationController;
  final WindowsServiceStatusSupplier _getStatus;
  final IMetricsCollector? _metrics;
  final String? nssmPathOverride;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const int _serviceNotFoundExitCode = 1060;
  static String get _logPath => WindowsServiceConstants.logPath;

  Future<rd.Result<void>> runPreflight({required String appDir}) async {
    final statusResult = await _getStatus();
    final statusFailure = statusResult.exceptionOrNull();
    if (statusFailure != null) {
      final msg = failureUserMessage(statusFailure);
      if (_scClient.textContainsAccessDenied(msg) ||
          msg.toLowerCase().contains('administrator')) {
        LoggerService.warning(
          'Preflight: consulta de status com acesso negado; '
          'seguindo para instalação (UAC se necessário)',
        );
      } else {
        return rd.Failure(windowsServiceAsFailure(statusFailure));
      }
    }

    final envCopyResult = await _envProvisioner.ensureServiceEnvFile(
      appDir: appDir,
    );
    if (envCopyResult.isError()) {
      final envFailure = envCopyResult.exceptionOrNull()!;
      if (_isPreflightPermissionFailure(envFailure)) {
        LoggerService.warning(
          'Preflight: não foi possível gravar .env sem elevação; '
          'o instalador elevado criará o arquivo',
        );
      } else {
        return rd.Failure(windowsServiceAsFailure(envFailure));
      }
    }

    try {
      Directory(_logPath).createSync(recursive: true);
    } on Object catch (e) {
      LoggerService.warning(
        'Preflight: diretório de logs não pôde ser criado '
        '($_logPath): $e — seguindo para UAC se a instalação exigir',
      );
      return const rd.Success(unit);
    }

    final hasWritePermission =
        await DirectoryPermissionCheck.hasWritePermissionForPath(_logPath);
    if (!hasWritePermission) {
      LoggerService.warning(
        'Preflight: diretório de logs não é gravável ($_logPath); '
        'seguindo para instalação (UAC se necessário)',
      );
    }

    return const rd.Success(unit);
  }

  bool _isPreflightPermissionFailure(Object failure) {
    final msg = failureUserMessage(failure).toLowerCase();
    return _scClient.textContainsAccessDenied(msg) ||
        msg.contains('administrator') ||
        msg.contains('administrador') ||
        msg.contains('permiss');
  }

  Future<rd.Result<void>> install({
    String? serviceUser,
    String? servicePassword,
  }) async {
    final appPath = Platform.resolvedExecutable;
    final appDir = File(appPath).parent.path;
    final wrapper = '$appDir\\tools\\BackupDatabaseService.exe';
    if (!File(wrapper).existsSync()) {
      return const rd.Failure(
        ValidationFailure(
          message: 'WinSW ausente. Reinstale o aplicativo com o instalador atualizado.',
        ),
      );
    }
    final preflight = await runPreflight(appDir: appDir);
    if (preflight.isError()) return preflight;
    return _elevationInstaller.install(
      wrapperPath: wrapper,
      appPath: appPath,
      appDir: appDir,
      serviceUser: serviceUser,
      servicePassword: servicePassword,
    );
  }

  @visibleForTesting
  Future<rd.Result<void>> ensureServiceNotInstalled() async {
    final statusResult = await _getStatus();
    final statusFailure = statusResult.exceptionOrNull();
    if (statusFailure != null) {
      final msg = failureUserMessage(statusFailure);
      if (!_scClient.textContainsAccessDenied(msg)) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceInstallFailure,
        );
        return rd.Failure(
          ServerFailure(
            message:
                'Não foi possível verificar se o serviço já está '
                'instalado: $msg',
          ),
        );
      }
      return const rd.Success(unit);
    }
    if (!(statusResult.getOrNull()?.isInstalled ?? false)) {
      return const rd.Success(unit);
    }

    return const rd.Failure(
      ValidationFailure(
        message:
            'O serviço já está instalado. A instalação foi interrompida '
            'para preservar sua configuração e credenciais. '
            'Use o instalador do aplicativo para atualizar a versão.',
      ),
    );
  }

  Future<rd.Result<void>> uninstall() async {
    try {
      await _scClient.run(
        arguments: ['stop', _serviceName],
        timeout: _timing.longTimeout,
      );

      final stopped = await _scmPoller.pollUntilStopped(
        timeout: _timing.longTimeout,
        interval: _timing.startPollingInterval,
        onConvergence: (d) => _metrics?.recordHistogram(
          ObservabilityMetrics.windowsServiceStopConvergenceSeconds,
          d.inMilliseconds / 1000,
        ),
      );

      if (!stopped) {
        return _elevationController.uninstallWithElevation();
      }
      final removeResult = await _processService.run(
        executable: 'sc',
        arguments: ['delete', _serviceName],
        timeout: _timing.longTimeout,
      );

      return await removeResult.fold<Future<rd.Result<void>>>(
        (processResult) async {
          if (processResult.exitCode != _successExitCode &&
              processResult.exitCode != _serviceNotFoundExitCode) {
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
                    'Erro ao remover serviço: $errorMessage\n\n'
                    '${WindowsServiceMessages.troubleshootingAdminLogs}',
              ),
            );
          }

          final postStatus = await _getStatus();
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
          message:
              'Erro ao remover serviço: $e\n\n'
              '${WindowsServiceMessages.troubleshootingAdminLogs}',
        ),
      );
    }
  }
}
