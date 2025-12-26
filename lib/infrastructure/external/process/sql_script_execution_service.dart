import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/schedule.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../domain/entities/postgres_config.dart';
import '../../../domain/services/i_sql_script_execution_service.dart';
import 'process_service.dart';

class SqlScriptExecutionService implements ISqlScriptExecutionService {
  final ProcessService _processService;

  SqlScriptExecutionService(this._processService);

  @override
  Future<rd.Result<void>> executeScript({
    required DatabaseType databaseType,
    required SqlServerConfig? sqlServerConfig,
    required SybaseConfig? sybaseConfig,
    required PostgresConfig? postgresConfig,
    required String script,
  }) async {
    // Validar script não vazio
    final trimmedScript = script.trim();
    if (trimmedScript.isEmpty) {
      return rd.Failure(
        ValidationFailure(message: 'Script SQL não pode estar vazio'),
      );
    }

    try {
      if (databaseType == DatabaseType.sqlServer) {
        return await _executeSqlServerScript(
          config: sqlServerConfig,
          script: trimmedScript,
        );
      } else if (databaseType == DatabaseType.sybase) {
        return await _executeSybaseScript(
          config: sybaseConfig,
          script: trimmedScript,
        );
      } else if (databaseType == DatabaseType.postgresql) {
        return await _executePostgresScript(
          config: postgresConfig,
          script: trimmedScript,
        );
      } else {
        return rd.Failure(
          ValidationFailure(
            message: 'Tipo de banco de dados não suportado: $databaseType',
          ),
        );
      }
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro inesperado ao executar script SQL',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar script SQL: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<void>> _executeSqlServerScript({
    required SqlServerConfig? config,
    required String script,
  }) async {
    if (config == null) {
      return rd.Failure(
        ValidationFailure(message: 'Configuração SQL Server não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no SQL Server: ${config.database}',
      );

      final arguments = [
        '-S',
        '${config.server},${config.port}',
        '-d',
        config.database,
        '-b',
        '-r',
        '1',
        '-Q',
        script,
        '-t',
        '30', // Timeout de 30 segundos
      ];

      if (config.username.isNotEmpty) {
        arguments.addAll(['-U', config.username, '-P', config.password]);
      } else {
        arguments.add('-E'); // Windows Authentication
      }

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        timeout: const Duration(seconds: 30),
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info(
              'Script SQL executado com sucesso no SQL Server',
            );
            return const rd.Success(unit);
          } else {
            final errorMessage =
                'Script SQL falhou (Exit Code: ${processResult.exitCode})\n'
                'STDOUT: ${processResult.stdout}\n'
                'STDERR: ${processResult.stderr}';
            LoggerService.warning(
              'Script SQL falhou no SQL Server',
              errorMessage,
            );
            return rd.Failure(BackupFailure(message: errorMessage));
          }
        },
        (failure) {
          final errorMessage = failure is Failure
              ? failure.message
              : failure.toString();
          LoggerService.warning(
            'Erro ao executar script SQL no SQL Server',
            failure,
          );
          return rd.Failure(
            BackupFailure(
              message: 'Erro ao executar script SQL: $errorMessage',
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao executar script SQL no SQL Server',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar script SQL: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<void>> _executeSybaseScript({
    required SybaseConfig? config,
    required String script,
  }) async {
    if (config == null) {
      return rd.Failure(
        ValidationFailure(message: 'Configuração Sybase não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no Sybase: ${config.serverName}',
      );

      // Construir connection string (seguindo padrão do SybaseBackupService)
      final databaseName = config.databaseName.isNotEmpty
          ? config.databaseName
          : config.serverName;

      // Tentar múltiplas variações de connection string
      final dbisqlConnections = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
      ];

      rd.Result<void>? result;
      String lastError = '';

      for (final connStr in dbisqlConnections) {
        LoggerService.debug('Tentando executar script com: $connStr');

        final dbisqlArgs = ['-c', connStr, '-nogui', script];

        final scriptResult = await _processService.run(
          executable: 'dbisql',
          arguments: dbisqlArgs,
          timeout: const Duration(seconds: 30),
        );

        scriptResult.fold(
          (processResult) {
            if (processResult.isSuccess) {
              LoggerService.info(
                'Script SQL executado com sucesso no Sybase com: $connStr',
              );
              result = const rd.Success(unit);
            } else {
              lastError = processResult.stderr;
              LoggerService.debug('dbisql falhou: ${processResult.stderr}');
            }
          },
          (failure) {
            if (failure is Failure) {
              lastError = failure.message;
            } else {
              lastError = failure.toString();
            }
          },
        );

        if (result != null && result!.isSuccess()) {
          break;
        }
      }

      if (result == null) {
        final errorMessage =
            'Nenhuma connection string funcionou. Último erro: $lastError';
        LoggerService.warning('Script SQL falhou no Sybase', errorMessage);
        return rd.Failure(BackupFailure(message: errorMessage));
      }

      return result!;
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao executar script SQL no Sybase',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar script SQL: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<void>> _executePostgresScript({
    required PostgresConfig? config,
    required String script,
  }) async {
    if (config == null) {
      return rd.Failure(
        ValidationFailure(message: 'Configuração PostgreSQL não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no PostgreSQL: ${config.database}',
      );

      final arguments = [
        '-h',
        config.host,
        '-p',
        config.port.toString(),
        '-U',
        config.username,
        '-d',
        config.database,
        '-c',
        script,
      ];

      final environment = <String, String>{
        'PGPASSWORD': config.password,
      };

      final result = await _processService.run(
        executable: 'psql',
        arguments: arguments,
        environment: environment,
        timeout: const Duration(seconds: 30),
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info(
              'Script SQL executado com sucesso no PostgreSQL',
            );
            return const rd.Success(unit);
          } else {
            final errorMessage =
                'Script SQL falhou (Exit Code: ${processResult.exitCode})\n'
                'STDOUT: ${processResult.stdout}\n'
                'STDERR: ${processResult.stderr}';
            LoggerService.warning(
              'Script SQL falhou no PostgreSQL',
              errorMessage,
            );
            return rd.Failure(BackupFailure(message: errorMessage));
          }
        },
        (failure) {
          final errorMessage = failure is Failure
              ? failure.message
              : failure.toString();
          LoggerService.warning(
            'Erro ao executar script SQL no PostgreSQL',
            failure,
          );
          return rd.Failure(
            BackupFailure(
              message: 'Erro ao executar script SQL: $errorMessage',
            ),
          );
        },
      );
    } catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao executar script SQL no PostgreSQL',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar script SQL: $e',
          originalError: e,
        ),
      );
    }
  }
}
