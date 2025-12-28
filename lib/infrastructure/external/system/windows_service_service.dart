import 'dart:io';

import 'package:result_dart/result_dart.dart'
    as rd
    show Result, Success, Failure;
import 'package:result_dart/result_dart.dart' show unit;

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

  static const Duration _shortTimeout = Duration(seconds: 10);
  static const Duration _longTimeout = Duration(seconds: 30);
  static const Duration _serviceDelay = Duration(seconds: 2);
  static const int _successExitCode = 0;
  static const int _serviceNotFoundExitCode = 3;
  static const String _nssmExeName = 'nssm.exe';
  static const String _scExeName = 'sc';
  static const String _toolsSubdir = 'tools';
  static const String _logSubdir = 'logs';
  static const String _programDataEnv = 'ProgramData';
  static const String _defaultProgramData = 'C:\\ProgramData';
  static const String _runningState = 'RUNNING';
  static const String _localSystemAccount = 'LocalSystem';

  WindowsServiceService(this._processService);

  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final result = await _processService.run(
        executable: _scExeName,
        arguments: ['query', _serviceName],
        timeout: _shortTimeout,
      );

      return result.fold((processResult) {
        final isInstalled = processResult.exitCode == _successExitCode;

        if (!isInstalled) {
          return rd.Success(
            const WindowsServiceStatus(isInstalled: false, isRunning: false),
          );
        }

        final isRunning = processResult.stdout.contains(_runningState);

        return rd.Success(
          WindowsServiceStatus(
            isInstalled: true,
            isRunning: isRunning,
            serviceName: _serviceName,
            displayName: _displayName,
          ),
        );
      }, (failure) => rd.Failure(failure));
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
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appPath = Platform.resolvedExecutable;
      final appDir = File(appPath).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

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
        await Future.delayed(_serviceDelay);
      }

      final installResult = await _processService.run(
        executable: nssmPath,
        arguments: ['install', _serviceName, appPath, '--minimized'],
        timeout: _longTimeout,
      );

      return installResult.fold((processResult) async {
        if (processResult.exitCode != _successExitCode) {
          final errorMessage = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;

          final isAccessDenied =
              errorMessage.contains('Acesso negado') ||
              errorMessage.contains('Access denied') ||
              errorMessage.contains('FALHA 5') ||
              errorMessage.contains('FAILURE 5');

          if (isAccessDenied) {
            return rd.Failure(
              ServerFailure(
                message:
                    'Acesso negado. É necessário executar o aplicativo como Administrador para instalar o serviço.\n\n'
                    'Solução:\n'
                    '1. Feche o aplicativo\n'
                    '2. Clique com botão direito no ícone do aplicativo\n'
                    '3. Selecione "Executar como administrador"\n'
                    '4. Tente instalar o serviço novamente',
              ),
            );
          }

          return rd.Failure(
            ServerFailure(message: 'Erro ao instalar serviço: $errorMessage'),
          );
        }

        await _configureService(nssmPath, serviceUser, servicePassword);

        LoggerService.info('Serviço instalado com sucesso');
        return rd.Success(unit);
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao instalar serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao instalar serviço: $e'));
    }
  }

  Future<void> _configureService(
    String nssmPath,
    String? serviceUser,
    String? servicePassword,
  ) async {
    final appDir = File(Platform.resolvedExecutable).parent.path;
    final programData =
        Platform.environment[_programDataEnv] ?? _defaultProgramData;
    final logPath = '$programData\\BackupDatabase\\$_logSubdir';

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
        timeout: _shortTimeout,
      );

      result.fold(
        (processResult) {
          if (processResult.exitCode != _successExitCode) {
            LoggerService.warning(
              'Aviso ao configurar ${config[1]}: ${processResult.stderr}',
            );
          }
        },
        (failure) {
          LoggerService.warning('Erro ao configurar ${config[1]}: $failure');
        },
      );
    }

    if (serviceUser == null || serviceUser.isEmpty) {
      LoggerService.info(
        'Configurando serviço para rodar como LocalSystem (sem usuário logado)',
      );

      await _processService.run(
        executable: nssmPath,
        arguments: ['set', _serviceName, 'ObjectName', _localSystemAccount],
        timeout: _shortTimeout,
      );
    } else if (servicePassword != null) {
      await _processService.run(
        executable: nssmPath,
        arguments: [
          'set',
          _serviceName,
          'ObjectName',
          serviceUser,
          servicePassword,
        ],
        timeout: _shortTimeout,
      );
    }
  }

  @override
  Future<rd.Result<void>> uninstallService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

      if (!File(nssmPath).existsSync()) {
        return rd.Failure(ValidationFailure(message: 'NSSM não encontrado'));
      }

      await _processService.run(
        executable: _scExeName,
        arguments: ['stop', _serviceName],
        timeout: _longTimeout,
      );

      await Future.delayed(_serviceDelay);

      final removeResult = await _processService.run(
        executable: nssmPath,
        arguments: ['remove', _serviceName, 'confirm'],
        timeout: _longTimeout,
      );

      return removeResult.fold((processResult) {
        if (processResult.exitCode != _successExitCode &&
            processResult.exitCode != _serviceNotFoundExitCode) {
          final errorMessage = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;

          final isAccessDenied =
              errorMessage.contains('Acesso negado') ||
              errorMessage.contains('Access denied') ||
              errorMessage.contains('FALHA 5') ||
              errorMessage.contains('FAILURE 5');

          if (isAccessDenied) {
            return rd.Failure(
              ServerFailure(
                message:
                    'Acesso negado. É necessário executar o aplicativo como Administrador para remover o serviço.\n\n'
                    'Solução:\n'
                    '1. Feche o aplicativo\n'
                    '2. Clique com botão direito no ícone do aplicativo\n'
                    '3. Selecione "Executar como administrador"\n'
                    '4. Tente remover o serviço novamente',
              ),
            );
          }

          return rd.Failure(
            ServerFailure(message: 'Erro ao remover serviço: $errorMessage'),
          );
        }
        LoggerService.info('Serviço removido com sucesso');
        return rd.Success(unit);
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao remover serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao remover serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> startService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();

      if (status?.isRunning == true) {
        LoggerService.info('Serviço já está em execução');
        return rd.Success(unit);
      }

      final result = await _processService.run(
        executable: _scExeName,
        arguments: ['start', _serviceName],
        timeout: _longTimeout,
      );

      return result.fold((processResult) async {
        await Future.delayed(_serviceDelay);

        final statusAfterResult = await getStatus();
        final statusAfter = statusAfterResult.getOrNull();

        if (statusAfter?.isRunning == true) {
          LoggerService.info('Serviço iniciado com sucesso');
          return rd.Success(unit);
        }

        final errorMessage = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        final isSuccessMessage =
            errorMessage.contains('SERVICE_ALREADY_RUNNING') ||
            errorMessage.contains('já está em execução');

        if (processResult.exitCode == _successExitCode || isSuccessMessage) {
          await Future.delayed(_serviceDelay);
          final finalStatusResult = await getStatus();
          final finalStatus = finalStatusResult.getOrNull();

          if (finalStatus?.isRunning == true) {
            LoggerService.info('Serviço iniciado com sucesso');
            return rd.Success(unit);
          }
        }

        final isAccessDenied =
            errorMessage.contains('Acesso negado') ||
            errorMessage.contains('Access denied') ||
            errorMessage.contains('FALHA 5') ||
            errorMessage.contains('FAILURE 5');

        if (isAccessDenied) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Acesso negado. É necessário executar o aplicativo como Administrador para iniciar o serviço.\n\n'
                  'Solução:\n'
                  '1. Feche o aplicativo\n'
                  '2. Clique com botão direito no ícone do aplicativo\n'
                  '3. Selecione "Executar como administrador"\n'
                  '4. Tente iniciar o serviço novamente',
            ),
          );
        }

        return rd.Failure(
          ServerFailure(message: 'Erro ao iniciar serviço: $errorMessage'),
        );
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao iniciar serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> stopService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();

      if (status?.isRunning != true) {
        LoggerService.info('Serviço já está parado');
        return rd.Success(unit);
      }

      final result = await _processService.run(
        executable: _scExeName,
        arguments: ['stop', _serviceName],
        timeout: _longTimeout,
      );

      return result.fold((processResult) async {
        await Future.delayed(_serviceDelay);

        final statusAfterResult = await getStatus();
        final statusAfter = statusAfterResult.getOrNull();

        if (statusAfter?.isRunning != true) {
          LoggerService.info('Serviço parado com sucesso');
          return rd.Success(unit);
        }

        final errorMessage = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;

        final isAccessDenied =
            errorMessage.contains('Acesso negado') ||
            errorMessage.contains('Access denied') ||
            errorMessage.contains('FALHA 5') ||
            errorMessage.contains('FAILURE 5');

        if (isAccessDenied) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Acesso negado. É necessário executar o aplicativo como Administrador para parar o serviço.\n\n'
                  'Solução:\n'
                  '1. Feche o aplicativo\n'
                  '2. Clique com botão direito no ícone do aplicativo\n'
                  '3. Selecione "Executar como administrador"\n'
                  '4. Tente parar o serviço novamente',
            ),
          );
        }

        if (processResult.exitCode == _successExitCode) {
          await Future.delayed(_serviceDelay);
          final finalStatusResult = await getStatus();
          final finalStatus = finalStatusResult.getOrNull();

          if (finalStatus?.isRunning != true) {
            LoggerService.info('Serviço parado com sucesso');
            return rd.Success(unit);
          }
        }

        return rd.Failure(
          ServerFailure(message: 'Erro ao parar serviço: $errorMessage'),
        );
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao parar serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao parar serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> restartService() async {
    if (!Platform.isWindows) {
      return rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    final stopResult = await stopService();
    return stopResult.fold((_) async {
      await Future.delayed(_serviceDelay);
      return await startService();
    }, (failure) => rd.Failure(failure));
  }
}
