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
    required ProcessService processService,
    WindowsServiceTimingConfig? timing,
  }) : _processService = processService,
       _timing = timing ?? WindowsServiceTimingConfig.defaultConfig;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;

  static const String _serviceName = WindowsServiceConstants.serviceName;
  static const int _successExitCode = 0;
  static const String _programDataEnv = 'ProgramData';
  static const String _defaultProgramData = r'C:\ProgramData';
  static const String _logSubdir = 'logs';
  static const String _localSystemAccount = 'LocalSystem';

  Future<rd.Result<void>> configure({
    required String nssmPath,
    String? serviceUser,
    String? servicePassword,
  }) async {
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

    final plan = NssmConfigPlan.build(appDir: appDir, logPath: logPath);

    for (final entry in plan.entries) {
      final result = await _processService.run(
        executable: nssmPath,
        arguments: entry.arguments(_serviceName),
        timeout: _timing.shortTimeout,
      );

      final failure = result.fold(
        (processResult) {
          if (processResult.exitCode != _successExitCode) {
            final msg = processResult.stderr.isNotEmpty
                ? processResult.stderr
                : processResult.stdout;
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
              message: 'Erro ao configurar chave crítica "${entry.key}": $f',
            );
          }
          LoggerService.warning('Erro ao configurar ${entry.key}: $f');
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
      await _runSetObjectNameWithCredentials(
        nssmPath: nssmPath,
        serviceUser: serviceUser,
        servicePassword: servicePassword,
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

  Future<rd.Result<ProcessResult>> _runSetObjectNameWithCredentials({
    required String nssmPath,
    required String serviceUser,
    required String servicePassword,
  }) async {
    final result = await _processService.run(
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

  Failure _asFailure(Object failure) {
    if (failure is Failure) return failure;
    return ServerFailure(
      message: failure.toString(),
      originalError: failure,
    );
  }
}
