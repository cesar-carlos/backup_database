import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import 'process_service.dart';

class ToolVerificationService {
  final ProcessService _processService;

  ToolVerificationService(this._processService);

  Future<rd.Result<bool>> verifySqlCmd() async {
    try {
      LoggerService.info('Verificando se sqlcmd está disponível...');

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info('sqlcmd encontrado e disponível');
            return rd.Success(true);
          } else {
            LoggerService.warning(
              'sqlcmd não encontrado (exit code: ${processResult.exitCode})',
            );
            return rd.Failure(
              ValidationFailure(
                message:
                    'sqlcmd não está disponível no PATH do sistema.\n\n'
                    'Para fazer backup de SQL Server, você precisa:\n'
                    '1. Instalar SQL Server Command Line Tools\n'
                    '2. Adicionar o caminho ao PATH do Windows\n\n'
                    'Consulte: docs\\path_setup.md',
              ),
            );
          }
        },
        (failure) {
          final errorMessage = failure is Failure
              ? failure.message
              : failure.toString();
          LoggerService.warning('Erro ao verificar sqlcmd: $errorMessage');
          return rd.Failure(
            ValidationFailure(
              message:
                  'sqlcmd não está disponível no PATH do sistema.\n\n'
                  'Para fazer backup de SQL Server, você precisa:\n'
                  '1. Instalar SQL Server Command Line Tools\n'
                  '2. Adicionar o caminho ao PATH do Windows\n\n'
                  'Consulte: docs\\path_setup.md',
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao verificar sqlcmd', e, stackTrace);
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar sqlcmd: $e\n\n'
              'Para fazer backup de SQL Server, você precisa:\n'
              '1. Instalar SQL Server Command Line Tools\n'
              '2. Adicionar o caminho ao PATH do Windows\n\n'
              'Consulte: docs\\path_setup.md',
        ),
      );
    }
  }

  Future<rd.Result<bool>> verifySybaseTools() async {
    try {
      LoggerService.info(
        'Verificando se ferramentas Sybase estão disponíveis...',
      );

      bool dbisqlFound = false;
      bool dbbackupFound = false;

      final dbisqlResult = await _processService.run(
        executable: 'dbisql',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbisqlResult.fold((processResult) {
        if (processResult.isSuccess) {
          dbisqlFound = true;
          LoggerService.info('dbisql encontrado e disponível');
        }
      }, (_) {});

      final dbbackupResult = await _processService.run(
        executable: 'dbbackup',
        arguments: ['-?'],
        timeout: const Duration(seconds: 5),
      );

      dbbackupResult.fold((processResult) {
        if (processResult.isSuccess) {
          dbbackupFound = true;
          LoggerService.info('dbbackup encontrado e disponível');
        }
      }, (_) {});

      if (dbisqlFound || dbbackupFound) {
        LoggerService.info(
          'Ferramentas Sybase encontradas: dbisql=$dbisqlFound, dbbackup=$dbbackupFound',
        );
        return rd.Success(true);
      }

      LoggerService.warning('Ferramentas Sybase não encontradas');
      return rd.Failure(
        ValidationFailure(
          message:
              'Ferramentas Sybase não estão disponíveis no PATH do sistema.\n\n'
              'Para fazer backup de Sybase SQL Anywhere, você precisa:\n'
              '1. Instalar Sybase SQL Anywhere\n'
              '2. Adicionar o caminho Bin64 ao PATH do Windows\n'
              '   (ex: C:\\Program Files\\SQL Anywhere 16\\Bin64)\n\n'
              'Consulte: docs\\path_setup.md',
        ),
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao verificar ferramentas Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        ValidationFailure(
          message:
              'Erro ao verificar ferramentas Sybase: $e\n\n'
              'Para fazer backup de Sybase SQL Anywhere, você precisa:\n'
              '1. Instalar Sybase SQL Anywhere\n'
              '2. Adicionar o caminho Bin64 ao PATH do Windows\n\n'
              'Consulte: docs\\path_setup.md',
        ),
      );
    }
  }
}
