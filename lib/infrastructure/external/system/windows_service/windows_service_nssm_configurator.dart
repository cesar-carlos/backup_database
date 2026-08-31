import 'dart:io';

import 'package:backup_database/core/constants/windows_service_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/nssm_config_plan.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceNssmConfigurator {
  WindowsServiceNssmConfigurator({
    required this._processService,
    WindowsServiceTimingConfig? timing,
  }) : _timing = timing ?? WindowsServiceTimingConfig.defaultConfig;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const String _localSystemAccount = 'LocalSystem';
  static const String _cantOpenService = "Can't open service";

  Future<rd.Result<void>> configure({
    required String nssmPath,
    String? serviceUser,
    String? servicePassword,
  }) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final logPath = WindowsServiceConstants.logPath;

    final logDir = Directory(logPath);
    if (!logDir.existsSync()) {
      try {
        logDir.createSync(recursive: true);
      } on Object catch (e) {
        LoggerService.warning('Erro ao criar diretório de logs: $e');
      }
    }

    final plan = NssmConfigPlan.build(appDir: appDir, logPath: logPath);

    for (final entry in plan.entries) {
      final result = await _runNssmSet(
        nssmPath: nssmPath,
        arguments: entry.arguments(_serviceName),
      );

      final failure = result.fold(
        (processResult) {
          if (processResult.exitCode != _successExitCode) {
            final msg = _nssmOutput(processResult);
            if (entry.critical) {
              return ServerFailure(
                message:
                    'Falha ao configurar chave crítica "${entry.key}" do serviço '
                    '(exit ${processResult.exitCode}): $msg',
              );
            }
            LoggerService.warning('Aviso ao configurar ${entry.key}: $msg');
          }
          return null;
        },
        (f) {
          if (entry.critical) {
            return ServerFailure(
              message:
                  'Erro ao configurar chave crítica "${entry.key}": '
                  '${failureUserMessage(f)}',
            );
          }
          LoggerService.warning(
            'Erro ao configurar ${entry.key}: ${failureUserMessage(f)}',
          );
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
      final objectResult = await _runNssmSet(
        nssmPath: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', _localSystemAccount],
      );
      _warnObjectNameLocalSystem(objectResult);
    } else if (servicePassword != null && servicePassword.isNotEmpty) {
      final credsResult = await _runSetObjectNameWithCredentials(
        nssmPath: nssmPath,
        serviceUser: serviceUser,
        servicePassword: servicePassword,
      );
      final credsFailure = credsResult.exceptionOrNull();
      if (credsFailure != null) {
        return rd.Failure(_asFailure(credsFailure));
      }
      final processResult = credsResult.getOrNull();
      if (processResult != null && processResult.exitCode != _successExitCode) {
        return const rd.Failure(
          ServerFailure(
            message:
                'Falha ao configurar a conta do serviço (ObjectName). '
                'Verifique o usuário e a senha.',
          ),
        );
      }
    } else {
      LoggerService.warning(
        'Usuário "$serviceUser" fornecido sem senha — usando LocalSystem',
      );
      final objectResult = await _runNssmSet(
        nssmPath: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', _localSystemAccount],
      );
      _warnObjectNameLocalSystem(objectResult);
    }

    return const rd.Success(unit);
  }

  void _warnObjectNameLocalSystem(rd.Result<ProcessResult> result) {
    result.fold(
      (processResult) {
        if (processResult.exitCode != _successExitCode) {
          LoggerService.warning(
            'nssm set ObjectName LocalSystem falhou '
            '(exit ${processResult.exitCode}): ${_nssmOutput(processResult)}',
          );
        }
      },
      (failure) {
        LoggerService.warning(
          'nssm set ObjectName LocalSystem falhou: '
          '${failureUserMessage(failure)}',
        );
      },
    );
  }

  Future<rd.Result<ProcessResult>> _runNssmSet({
    required String nssmPath,
    required List<String> arguments,
  }) async {
    rd.Result<ProcessResult>? last;
    for (var attempt = 1; attempt <= _timing.retryMaxAttempts; attempt++) {
      last = await _processService.run(
        executable: nssmPath,
        arguments: arguments,
        timeout: _timing.shortTimeout,
      );
      final processResult = last.getOrNull();
      if (processResult != null && processResult.exitCode == _successExitCode) {
        return last;
      }
      final msg = processResult != null
          ? _nssmOutput(processResult)
          : failureUserMessage(last.exceptionOrNull());
      final canRetry =
          msg.contains(_cantOpenService) && attempt < _timing.retryMaxAttempts;
      if (!canRetry) {
        return last;
      }
      await Future.delayed(_timing.nssmCantOpenRetryDelay);
    }
    return last!;
  }

  Future<rd.Result<ProcessResult>> _runSetObjectNameWithCredentials({
    required String nssmPath,
    required String serviceUser,
    required String servicePassword,
  }) async {
    final result = await _runNssmSet(
      nssmPath: nssmPath,
      arguments: [
        'set',
        _serviceName,
        'ObjectName',
        serviceUser,
        servicePassword,
      ],
    );
    return result.fold(
      (processResult) {
        if (processResult.exitCode != _successExitCode) {
          LoggerService.warning(
            'nssm set ObjectName falhou para usuário "$serviceUser" '
            '(exit ${processResult.exitCode}). Detalhes suprimidos para '
            'evitar vazamento de credencial em log.',
          );
        }
        return rd.Success(processResult);
      },
      (failure) {
        LoggerService.warning(
          'nssm set ObjectName falhou para usuário "$serviceUser". '
          'Detalhes suprimidos para evitar vazamento de credencial em log.',
        );
        return rd.Failure(_asFailure(failure));
      },
    );
  }

  String _nssmOutput(ProcessResult processResult) {
    return processResult.stderr.isNotEmpty
        ? processResult.stderr
        : processResult.stdout;
  }

  Failure _asFailure(Object failure) {
    if (failure is Failure) return failure;
    return ServerFailure(
      message: failureUserMessage(failure),
      originalError: failure,
    );
  }
}
