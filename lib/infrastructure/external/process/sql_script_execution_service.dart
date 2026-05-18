import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/services/i_sql_script_execution_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class SqlScriptExecutionService implements ISqlScriptExecutionService {
  SqlScriptExecutionService(this._processService);
  final ProcessService _processService;

  static const Duration _defaultScriptTimeout = Duration(minutes: 30);

  @override
  Future<rd.Result<void>> executeScript({
    required DatabaseType databaseType,
    required SqlServerConfig? sqlServerConfig,
    required SybaseConfig? sybaseConfig,
    required PostgresConfig? postgresConfig,
    required FirebirdConfig? firebirdConfig,
    required String script,
    Duration? timeout,
  }) async {
    final trimmedScript = script.trim();
    if (trimmedScript.isEmpty) {
      return const rd.Failure(
        ValidationFailure(message: 'Script SQL não pode estar vazio'),
      );
    }

    final effectiveTimeout = (timeout == null || timeout == Duration.zero)
        ? _defaultScriptTimeout
        : timeout;

    try {
      if (databaseType == DatabaseType.sqlServer) {
        return await _executeSqlServerScript(
          config: sqlServerConfig,
          script: trimmedScript,
          timeout: effectiveTimeout,
        );
      } else if (databaseType == DatabaseType.sybase) {
        return await _executeSybaseScript(
          config: sybaseConfig,
          script: trimmedScript,
          timeout: effectiveTimeout,
        );
      } else if (databaseType == DatabaseType.postgresql) {
        return await _executePostgresScript(
          config: postgresConfig,
          script: trimmedScript,
          timeout: effectiveTimeout,
        );
      } else if (databaseType == DatabaseType.firebird) {
        return await _executeFirebirdScript(
          config: firebirdConfig,
          script: trimmedScript,
          timeout: effectiveTimeout,
        );
      } else {
        return rd.Failure(
          ValidationFailure(
            message: 'Tipo de banco de dados não suportado: $databaseType',
          ),
        );
      }
    } on Object catch (e, stackTrace) {
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
    required Duration timeout,
  }) async {
    if (config == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Configuração SQL Server não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no SQL Server: ${config.databaseValue}',
      );

      final timeoutSeconds = timeout.inSeconds.clamp(1, 32767);

      final arguments = <String>[
        '-S',
        '${config.server},${config.portValue}',
        '-d',
        config.databaseValue,
        '-b',
        '-r',
        '1',
        '-Q',
        script,
        '-t',
        timeoutSeconds.toString(),
      ];

      if (config.username.isNotEmpty) {
        arguments.addAll(['-U', config.username, '-P', config.password]);
      } else {
        arguments.add('-E'); // Windows Authentication
      }

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        timeout: timeout,
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
    } on Object catch (e, stackTrace) {
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
    required Duration timeout,
  }) async {
    if (config == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Configuração Sybase não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no Sybase: ${config.serverName}',
      );

      final databaseName = config.databaseNameValue.isNotEmpty
          ? config.databaseNameValue
          : config.serverName;

      final dbisqlConnections = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
      ];

      rd.Result<void>? result;
      var lastError = '';
      var strategyIndex = 0;

      for (final connStr in dbisqlConnections) {
        strategyIndex++;
        LoggerService.debug(
          'Tentando executar script com estratégia '
          '$strategyIndex/${dbisqlConnections.length}',
        );

        final dbisqlArgs = ['-c', connStr, '-nogui', script];

        final scriptResult = await _processService.run(
          executable: 'dbisql',
          arguments: dbisqlArgs,
          timeout: timeout,
        );

        scriptResult.fold(
          (processResult) {
            if (processResult.isSuccess) {
              LoggerService.info(
                'Script SQL executado com sucesso no Sybase '
                'com estratégia $strategyIndex',
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
    } on Object catch (e, stackTrace) {
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
    required Duration timeout,
  }) async {
    if (config == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Configuração PostgreSQL não fornecida'),
      );
    }

    try {
      LoggerService.info(
        'Executando script SQL no PostgreSQL: ${config.databaseValue}',
      );

      final arguments = <String>[
        '-h',
        config.host,
        '-p',
        config.portValue.toString(),
        '-U',
        config.username,
        '-d',
        config.databaseValue,
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
        timeout: timeout,
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
    } on Object catch (e, stackTrace) {
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

  Future<rd.Result<void>> _executeFirebirdScript({
    required FirebirdConfig? config,
    required String script,
    required Duration timeout,
  }) async {
    if (config == null) {
      return const rd.Failure(
        ValidationFailure(message: 'Configuração Firebird não fornecida'),
      );
    }

    String databaseArgument;
    if (config.useEmbedded) {
      final path = config.databaseFile.trim();
      if (path.isEmpty) {
        return const rd.Failure(
          ValidationFailure(
            message: 'Caminho do arquivo do banco Firebird (embedded) vazio.',
          ),
        );
      }
      databaseArgument = path;
    } else {
      final alias = config.aliasName?.trim();
      if (alias != null && alias.isNotEmpty) {
        databaseArgument = '${config.host}/${config.portValue}:$alias';
      } else {
        final db = config.databaseFile.trim();
        if (db.isEmpty) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'Informe o caminho do banco no servidor ou um alias Firebird.',
            ),
          );
        }
        databaseArgument = '${config.host}/${config.portValue}:$db';
      }
    }

    Directory? tempDir;
    try {
      LoggerService.info(
        'Executando script SQL no Firebird: ${config.primaryDatabase.value}',
      );

      tempDir = await Directory.systemTemp.createTemp('fb_post_script_');
      final scriptFile = File(p.join(tempDir.path, 'post_backup.sql'));
      await scriptFile.writeAsString(script, flush: true);

      final arguments = <String>[
        '-q',
        '-user',
        config.username,
        '-password',
        config.password,
        '-i',
        scriptFile.path,
        databaseArgument,
      ];

      final environment = _firebirdClientLibEnvironment(config);

      final result = await _processService.run(
        executable: 'isql',
        arguments: arguments,
        environment: environment,
        timeout: timeout,
      );

      return result.fold(
        (processResult) {
          if (processResult.isSuccess) {
            LoggerService.info('Script SQL executado com sucesso no Firebird');
            return const rd.Success(unit);
          }
          final errorMessage =
              'Script SQL falhou (Exit Code: ${processResult.exitCode})\n'
              'STDOUT: ${processResult.stdout}\n'
              'STDERR: ${processResult.stderr}';
          LoggerService.warning('Script SQL falhou no Firebird', errorMessage);
          return rd.Failure(BackupFailure(message: errorMessage));
        },
        (failure) {
          final msg = failure is Failure ? failure.message : failure.toString();
          final lower = msg.toLowerCase();
          if (ToolPathHelp.isToolNotFoundError(lower, 'isql')) {
            return rd.Failure(
              BackupFailure(message: ToolPathHelp.buildMessage('isql')),
            );
          }
          LoggerService.warning(
            'Erro ao executar script SQL no Firebird',
            failure,
          );
          return rd.Failure(
            BackupFailure(
              message: 'Erro ao executar script SQL: $msg',
            ),
          );
        },
      );
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao executar script SQL no Firebird',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar script SQL: $e',
          originalError: e,
        ),
      );
    } finally {
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } on Object catch (e, s) {
          LoggerService.warning(
            'Falha ao remover diretório temporário do script Firebird',
            e,
            s,
          );
        }
      }
    }
  }

  Map<String, String>? _firebirdClientLibEnvironment(FirebirdConfig config) {
    final lib = config.clientLibraryPath?.trim();
    if (lib == null || lib.isEmpty) {
      return null;
    }
    final dir = p.dirname(lib);
    final key = Platform.isWindows ? 'Path' : 'PATH';
    final current = Platform.environment[key] ?? Platform.environment['PATH'];
    if (current == null || current.isEmpty) {
      return {key: dir};
    }
    final sep = Platform.isWindows ? ';' : ':';
    return {key: '$dir$sep$current'};
  }
}
