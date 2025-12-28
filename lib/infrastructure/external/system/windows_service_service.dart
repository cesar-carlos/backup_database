import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/services/i_windows_service_service.dart';
import '../process/process_service.dart';

class WindowsServiceService implements IWindowsServiceService {
  final ProcessService _processService;
  static const String _serviceName = 'BackupDatabaseService';
  static const String _displayName = 'Backup Database Service';
  static const String _description =
      'Serviço de backup automático para SQL Server e Sybase';

  WindowsServiceService(this._processService);

  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }

    try {
      final result = await _processService.run(
        executable: 'sc',
        arguments: ['query', _serviceName],
        timeout: const Duration(seconds: 10),
      );

      return result.fold(
        (processResult) {
          final isInstalled = processResult.exitCode == 0;

          if (!isInstalled) {
            return rd.Success(
              const WindowsServiceStatus(
                isInstalled: false,
                isRunning: false,
              ),
            );
          }

          final isRunning = processResult.stdout.contains('RUNNING');

          return rd.Success(
            WindowsServiceStatus(
              isInstalled: true,
              isRunning: isRunning,
              serviceName: _serviceName,
              displayName: _displayName,
            ),
          );
        },
        (failure) => rd.Failure(failure),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar status do serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(message: 'Erro ao verificar status do serviço: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> installService({
    String? serviceUser,
    String? servicePassword,
  }) async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }

    try {
      final appPath = Platform.resolvedExecutable;
      final appDir = File(appPath).parent.path;
      final nssmPath = '$appDir\\tools\\nssm.exe';

      if (!File(nssmPath).existsSync()) {
        return rd.Failure(
          ValidationFailure(
            message:
                'NSSM não encontrado. Verifique se o aplicativo foi instalado corretamente.',
          ),
        );
      }

      LoggerService.info('Instalando serviço do Windows...');

      final statusResult = await getStatus();
      final existingStatus = statusResult.getOrNull();

      if (existingStatus?.isInstalled == true) {
        LoggerService.info('Serviço já existe. Removendo versão anterior...');
        await uninstallService();
        await Future.delayed(const Duration(seconds: 2));
      }

      final installResult = await _processService.run(
        executable: nssmPath,
        arguments: ['install', _serviceName, appPath, '--minimized'],
        timeout: const Duration(seconds: 30),
      );

      return installResult.fold(
        (processResult) async {
          if (processResult.exitCode != 0) {
            return rd.Failure(
              ServerFailure(
                message: 'Erro ao instalar serviço: ${processResult.stderr}',
              ),
            );
          }

          await _configureService(nssmPath, serviceUser, servicePassword);

          LoggerService.info('Serviço instalado com sucesso');
          return rd.Success(());
        },
        (failure) => rd.Failure(failure),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao instalar serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(message: 'Erro ao instalar serviço: $e'),
      );
    }
  }

  Future<void> _configureService(
    String nssmPath,
    String? serviceUser,
    String? servicePassword,
  ) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final logPath = Platform.environment['ProgramData'] != null
        ? '${Platform.environment['ProgramData']}\\BackupDatabase\\logs'
        : 'C:\\ProgramData\\BackupDatabase\\logs';

    final logDir = Directory(logPath);
    if (!logDir.existsSync()) {
      try {
        logDir.createSync(recursive: true);
      } catch (e) {
        LoggerService.warning('Erro ao criar diretório de logs: $e');
      }
    }

    final configs = [
      ['set', _serviceName, 'AppDirectory', appDir],
      ['set', _serviceName, 'DisplayName', _displayName],
      ['set', _serviceName, 'Description', _description],
      ['set', _serviceName, 'Start', 'SERVICE_AUTO_START'],
      ['set', _serviceName, 'AppStdout', '$logPath\\service_stdout.log'],
      ['set', _serviceName, 'AppStderr', '$logPath\\service_stderr.log'],
      ['set', _serviceName, 'AppNoConsole', '1'],
    ];

    for (final config in configs) {
      final result = await _processService.run(
        executable: nssmPath,
        arguments: config,
        timeout: const Duration(seconds: 10),
      );

      result.fold(
        (processResult) {
          if (processResult.exitCode != 0) {
            LoggerService.warning(
              'Aviso ao configurar ${config[1]}: ${processResult.stderr}',
            );
          }
        },
        (failure) {
          LoggerService.warning(
            'Erro ao configurar ${config[1]}: $failure',
          );
        },
      );
    }

    if (serviceUser == null || serviceUser.isEmpty) {
      LoggerService.info(
        'Configurando serviço para rodar como LocalSystem (sem usuário logado)',
      );

      await _processService.run(
        executable: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', 'LocalSystem'],
        timeout: const Duration(seconds: 10),
      );
    } else if (servicePassword != null) {
      await _processService.run(
        executable: nssmPath,
        arguments: [
          'set',
          _serviceName,
          'ObjectName',
          serviceUser,
          servicePassword
        ],
        timeout: const Duration(seconds: 10),
      );
    }
  }

  @override
  Future<rd.Result<void>> uninstallService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final nssmPath = '$appDir\\tools\\nssm.exe';

      if (!File(nssmPath).existsSync()) {
        return rd.Failure(
          ValidationFailure(message: 'NSSM não encontrado'),
        );
      }

      await _processService.run(
        executable: 'sc',
        arguments: ['stop', _serviceName],
        timeout: const Duration(seconds: 30),
      );

      await Future.delayed(const Duration(seconds: 2));

      final removeResult = await _processService.run(
        executable: nssmPath,
        arguments: ['remove', _serviceName, 'confirm'],
        timeout: const Duration(seconds: 30),
      );

      return removeResult.fold(
        (processResult) {
          if (processResult.exitCode != 0 && processResult.exitCode != 3) {
            return rd.Failure(
              ServerFailure(
                message: 'Erro ao remover serviço: ${processResult.stderr}',
              ),
            );
          }
          LoggerService.info('Serviço removido com sucesso');
          return rd.Success(());
        },
        (failure) => rd.Failure(failure),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao remover serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(message: 'Erro ao remover serviço: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> startService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }
    return _controlService('start');
  }

  @override
  Future<rd.Result<void>> stopService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }
    return _controlService('stop');
  }

  @override
  Future<rd.Result<void>> restartService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(
          message: 'Windows Service só é suportado no Windows',
        ),
      );
    }

    final stopResult = await stopService();
    return stopResult.fold(
      (_) async {
        await Future.delayed(const Duration(seconds: 2));
        return await startService();
      },
      (failure) => rd.Failure(failure),
    );
  }

  Future<rd.Result<void>> _controlService(String action) async {
    try {
      final result = await _processService.run(
        executable: 'sc',
        arguments: [action, _serviceName],
        timeout: const Duration(seconds: 30),
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode != 0) {
            return rd.Failure(
              ServerFailure(
                message: 'Erro ao $action serviço: ${processResult.stderr}',
              ),
            );
          }
          LoggerService.info('Serviço $action com sucesso');
          return rd.Success(());
        },
        (failure) => rd.Failure(failure),
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao $action serviço', e, stackTrace);
      return rd.Failure(
        ServerFailure(message: 'Erro ao $action serviço: $e'),
      );
    }
  }
}

