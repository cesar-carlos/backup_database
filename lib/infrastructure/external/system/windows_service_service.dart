import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:result_dart/result_dart.dart'
    as rd
    show Failure, Result, Success;
import 'package:result_dart/result_dart.dart' show unit;

class WindowsServiceService implements IWindowsServiceService {
  WindowsServiceService(this._processService);
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
  static const String _defaultProgramData = r'C:\ProgramData';
  static const String _runningState = 'RUNNING';
  static const String _localSystemAccount = 'LocalSystem';
  static const int _serviceNotInstalledWinError = 1060;
  static const int _serviceNotInstalledBatchError = 36;
  static const int _accessDeniedWinError = 5;

  @override
  Future<rd.Result<WindowsServiceStatus>> getStatus() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final result = await _processService.run(
        executable: _scExeName,
        arguments: ['query', _serviceName],
        timeout: _shortTimeout,
      );

      return result.fold(
        (processResult) {
          if (processResult.exitCode == _successExitCode) {
            final isRunning = processResult.stdout.contains(_runningState);
            return rd.Success(
              WindowsServiceStatus(
                isInstalled: true,
                isRunning: isRunning,
                serviceName: _serviceName,
                displayName: _displayName,
              ),
            );
          }

          if (_isServiceNotInstalledResponse(processResult)) {
            return const rd.Success(
              WindowsServiceStatus(isInstalled: false, isRunning: false),
            );
          }

          if (_isAccessDeniedResponse(processResult)) {
            return const rd.Failure(
              ServerFailure(
                message:
                    'Acesso negado ao consultar status do serviço. Execute o aplicativo como Administrador.',
              ),
            );
          }

          final errorOutput = _getProcessOutput(processResult);
          return rd.Failure(
            ServerFailure(
              message:
                  'Falha ao consultar status do serviço (exit code: ${processResult.exitCode}). '
                  'Saída: $errorOutput',
            ),
          );
        },
        (failure) {
          return rd.Failure(
            ServerFailure(
              message:
                  'Erro ao executar comando para consultar status do serviço: $failure',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
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
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appPath = Platform.resolvedExecutable;
      final appDir = File(appPath).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

      if (!File(nssmPath).existsSync()) {
        return const rd.Failure(
          ValidationFailure(
            message:
                'NSSM não encontrado. Verifique se o aplicativo foi instalado corretamente.',
          ),
        );
      }

      LoggerService.info('Instalando serviço do Windows...');

      final statusResult = await getStatus();
      final existingStatus = statusResult.getOrNull();

      if (existingStatus?.isInstalled ?? false) {
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
            return const rd.Failure(
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
        LoggerService.info(
          'Auto-restart configurado: Reiniciará automaticamente após crash (60s delay)',
        );
        return const rd.Success(unit);
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
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
      } on Object catch (e) {
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
      // Configure auto-restart on crash
      ['set', _serviceName, 'AppExit', 'Default', 'Restart'],
      ['set', _serviceName, 'AppRestartDelay', '60000'],
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
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final appDir = File(Platform.resolvedExecutable).parent.path;
      final nssmPath = '$appDir\\$_toolsSubdir\\$_nssmExeName';

      if (!File(nssmPath).existsSync()) {
        return const rd.Failure(
          ValidationFailure(message: 'NSSM não encontrado'),
        );
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
            return const rd.Failure(
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
        return const rd.Success(unit);
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao remover serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao remover serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> startService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();

      if (status?.isRunning ?? false) {
        LoggerService.info('Serviço já está em execução');
        return const rd.Success(unit);
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

        if (statusAfter?.isRunning ?? false) {
          LoggerService.info('Serviço iniciado com sucesso');
          return const rd.Success(unit);
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

          if (finalStatus?.isRunning ?? false) {
            LoggerService.info('Serviço iniciado com sucesso');
            return const rd.Success(unit);
          }
        }

        final isAccessDenied =
            errorMessage.contains('Acesso negado') ||
            errorMessage.contains('Access denied') ||
            errorMessage.contains('FALHA 5') ||
            errorMessage.contains('FAILURE 5');

        if (isAccessDenied) {
          return const rd.Failure(
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
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao iniciar serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao iniciar serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> stopService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    try {
      final statusResult = await getStatus();
      final status = statusResult.getOrNull();

      if (status?.isRunning != true) {
        LoggerService.info('Serviço já está parado');
        return const rd.Success(unit);
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
          return const rd.Success(unit);
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
          return const rd.Failure(
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
            return const rd.Success(unit);
          }
        }

        return rd.Failure(
          ServerFailure(message: 'Erro ao parar serviço: $errorMessage'),
        );
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao parar serviço', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao parar serviço: $e'));
    }
  }

  @override
  Future<rd.Result<void>> restartService() async {
    if (!Platform.isWindows) {
      return const rd.Failure(
        ValidationFailure(message: 'Windows Service só é suportado no Windows'),
      );
    }

    final stopResult = await stopService();
    return stopResult.fold((_) async {
      await Future.delayed(_serviceDelay);
      return startService();
    }, rd.Failure.new);
  }

  bool _isServiceNotInstalledResponse(ProcessResult processResult) {
    if (processResult.exitCode == _serviceNotInstalledWinError ||
        processResult.exitCode == _serviceNotInstalledBatchError) {
      return true;
    }

    final output = _getProcessOutput(processResult).toLowerCase();
    return output.contains('1060') ||
        output.contains('does not exist as an installed service') ||
        output.contains('specified service does not exist') ||
        output.contains('nao existe como servico instalado') ||
        output.contains('não existe como serviço instalado');
  }

  bool _isAccessDeniedResponse(ProcessResult processResult) {
    if (processResult.exitCode == _accessDeniedWinError) {
      return true;
    }

    final output = _getProcessOutput(processResult).toLowerCase();
    return output.contains('access is denied') ||
        output.contains('acesso negado') ||
        output.contains('falha 5') ||
        output.contains('failure 5');
  }

  String _getProcessOutput(ProcessResult processResult) {
    final stderr = processResult.stderr.trim();
    final stdout = processResult.stdout.trim();
    if (stderr.isNotEmpty && stdout.isNotEmpty) {
      return '$stderr | $stdout';
    }
    if (stderr.isNotEmpty) {
      return stderr;
    }
    if (stdout.isNotEmpty) {
      return stdout;
    }
    return 'sem saída';
  }
}
