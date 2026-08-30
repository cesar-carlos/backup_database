import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/appending_file_sink.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_controller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_elevation_installer.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_env_provisioner.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_install_orchestrator.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_lifecycle_orchestrator.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_messages.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_nssm_configurator.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_sc_client.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_scm_poller.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:result_dart/result_dart.dart'
    as rd
    show Failure, Result, Success;

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
    WindowsServiceInstallOrchestrator? installOrchestrator,
    WindowsServiceLifecycleOrchestrator? lifecycleOrchestrator,
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
    _install =
        installOrchestrator ??
        WindowsServiceInstallOrchestrator(
          processService: _processService,
          timing: _timing,
          nssmConfigurator: _nssmConfigurator,
          envProvisioner: _envProvisioner,
          scClient: _scClient,
          scmPoller: _scmPoller,
          elevationInstaller: _elevationInstaller,
          elevationController: _elevationController,
          getStatus: getStatus,
          metricsCollector: _metrics,
        );
    _lifecycle =
        lifecycleOrchestrator ??
        WindowsServiceLifecycleOrchestrator(
          timing: _timing,
          scClient: _scClient,
          scmPoller: _scmPoller,
          elevationController: _elevationController,
          getStatus: getStatus,
          appendDiagnostics: _appendControlDiagnostics,
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
  late final WindowsServiceInstallOrchestrator _install;
  late final WindowsServiceLifecycleOrchestrator _lifecycle;

  final AppendingFileSink _diagnosticsSink;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const String _displayName = WindowsServiceConstants.displayName;
  static const int _successExitCode = 0;
  static const String _controlDiagnosticsPath =
      r'C:\ProgramData\BackupDatabase\logs\service_control_diagnostics.log';

  static rd.Result<void> get _notSupportedOnPlatform => const rd.Failure(
    ValidationFailure(message: WindowsServiceMessages.notSupportedOnPlatform),
  );

  static rd.Result<WindowsServiceStatus> get _notSupportedStatus =>
      const rd.Failure(
        ValidationFailure(
          message: WindowsServiceMessages.notSupportedOnPlatform,
        ),
      );

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
      return _notSupportedStatus;
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
                    '${WindowsServiceMessages.accessDeniedSolution}',
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
                  'Falha ao consultar status do serviço '
                  '(exit code: ${processResult.exitCode}). '
                  'Saída: $errorOutput\n\n'
                  '${WindowsServiceMessages.troubleshootingAdminLogs}',
            ),
          );
        },
        (failure) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Erro ao executar comando para consultar status do '
                  'serviço: ${failureUserMessage(failure)}\n\n'
                  '${WindowsServiceMessages.troubleshootingAdminLogs}',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar status do serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(
          message:
              'Erro ao verificar status do serviço: $e\n\n'
              '${WindowsServiceMessages.troubleshootingAdminLogs}',
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
      return _notSupportedOnPlatform;
    }
    return _install.install(
      serviceUser: serviceUser,
      servicePassword: servicePassword,
    );
  }

  @override
  Future<rd.Result<void>> uninstallService() async {
    if (!Platform.isWindows) {
      return _notSupportedOnPlatform;
    }
    return _install.uninstall();
  }

  @override
  Future<rd.Result<void>> startService() => startServiceWithTimeout();

  @visibleForTesting
  Future<rd.Result<void>> startServiceWithTimeout({
    Duration? pollingTimeout,
    Duration? pollingInterval,
    Duration? initialDelay,
  }) async {
    if (!Platform.isWindows) {
      return _notSupportedOnPlatform;
    }
    return _lifecycle.start(
      pollingTimeout: pollingTimeout,
      pollingInterval: pollingInterval,
      initialDelay: initialDelay,
    );
  }

  @override
  Future<rd.Result<void>> stopService() async {
    if (!Platform.isWindows) {
      return _notSupportedOnPlatform;
    }
    return _lifecycle.stop();
  }

  @override
  Future<rd.Result<void>> restartService() async {
    if (!Platform.isWindows) {
      return _notSupportedOnPlatform;
    }
    return _lifecycle.restart();
  }

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
    _diagnosticsSink.append(buffer.toString());
  }

  @visibleForTesting
  Future<void> flushDiagnosticsForTesting() => _diagnosticsSink.flush();
}
