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
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_nssm_configurator.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_sc_client.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceInstallOrchestrator {
  WindowsServiceInstallOrchestrator({
    required this._processService,
    required this._timing,
    required this._nssmConfigurator,
    required this._envProvisioner,
    required this._scClient,
    required this._scmPoller,
    required this._elevationInstaller,
    required this._elevationController,
    required this._getStatus,
    IMetricsCollector? metricsCollector,
  }) : _metrics = metricsCollector;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;
  final WindowsServiceNssmConfigurator _nssmConfigurator;
  final WindowsServiceEnvProvisioner _envProvisioner;
  final WindowsServiceScClient _scClient;
  final WindowsServiceScmPoller _scmPoller;
  final WindowsServiceElevationInstaller _elevationInstaller;
  final WindowsServiceElevationController _elevationController;
  final WindowsServiceStatusSupplier _getStatus;
  final IMetricsCollector? _metrics;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const int _nssmServiceNotFoundExitCode = 3;
  static const String _nssmExeName = 'nssm.exe';
  static const String _toolsSubdir = 'tools';
  static const String _logPath = WindowsServiceConstants.logPath;

  Future<rd.Result<void>> runPreflight({required String appDir}) async {
    final statusResult = await _getStatus();
    final statusFailure = statusResult.exceptionOrNull();
    if (statusFailure != null) {
      final msg = failureUserMessage(statusFailure).toLowerCase();
      if (msg.contains('acesso negado') ||
          msg.contains('access denied') ||
          msg.contains('administrator')) {
        return rd.Failure(windowsServiceAsFailure(statusFailure));
      }
    }

    final envCopyResult = await _envProvisioner.ensureServiceEnvFile(
      appDir: appDir,
    );
    if (envCopyResult.isError()) {
      return rd.Failure(
        windowsServiceAsFailure(envCopyResult.exceptionOrNull()!),
      );
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

  Future<rd.Result<void>> install({
    String? serviceUser,
    String? servicePassword,
  }) async {
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
                '1. Reinstalar o aplicativo (o instalador deve incluir '
                'nssm.exe em tools/)\n'
                '2. Executar como Administrador\n'
                '3. Verificar se a pasta do aplicativo está corrompida '
                'ou incompleta',
          ),
        );
      }

      final preflightResult = await runPreflight(appDir: appDir);
      final preflightFailure = preflightResult.exceptionOrNull();
      if (preflightFailure != null) {
        _metrics?.incrementCounter(
          ObservabilityMetrics.windowsServiceInstallFailure,
        );
        return rd.Failure(windowsServiceAsFailure(preflightFailure));
      }

      LoggerService.info('Instalando serviço do Windows...');

      final statusResult = await _getStatus();
      final existingStatus = statusResult.getOrNull();

      if (existingStatus?.isInstalled ?? false) {
        LoggerService.info('Serviço já existe. Removendo versão anterior...');
        await uninstall();
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
                'Acesso negado ao instalar serviço; '
                'solicitando elevação UAC',
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
                    'Erro ao instalar serviço: $errorMessage\n\n'
                    '${WindowsServiceMessages.troubleshootingAdminLogs}',
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
              'Configuração crítica do serviço falhou — '
              'removendo instalação parcial',
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
            return rd.Failure(windowsServiceAsFailure(configFailure));
          }

          final postStatus = await _getStatus();
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
                        'não está registrado.\n\n'
                        '${WindowsServiceMessages.troubleshootingWithEnv}',
                  ),
                );
              }
              _metrics?.incrementCounter(
                ObservabilityMetrics.windowsServiceInstallSuccess,
              );
              LoggerService.info('Serviço instalado com sucesso');
              LoggerService.info(
                'Auto-restart configurado: Reiniciará automaticamente '
                'após crash (60s delay)',
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
          message:
              'Erro ao instalar serviço: $e\n\n'
              '${WindowsServiceMessages.troubleshootingAdminLogs}',
        ),
      );
    }
  }

  Future<rd.Result<void>> uninstall() async {
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
