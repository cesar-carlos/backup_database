import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/backup_type.dart';
import '../../../domain/entities/sql_server_config.dart';
import '../../../domain/services/backup_execution_result.dart';
import '../../../domain/services/i_sql_server_backup_service.dart';
import 'process_service.dart' as ps;

class SqlServerBackupService implements ISqlServerBackupService {
  final ps.ProcessService _processService;

  SqlServerBackupService(this._processService);

  List<String> _baseSqlcmdArgs(SqlServerConfig config) {
    final args = <String>[
      '-S',
      '${config.server},${config.port}',
      '-d',
      config.database,
      // Fail fast for automation: return non-zero exit code on error.
      '-b',
      // Send error messages to STDERR (helps logging and parsing).
      '-r',
      '1',
    ];

    if (config.username.isNotEmpty) {
      args.addAll(['-U', config.username, '-P', config.password]);
    } else {
      args.add('-E');
    }

    return args;
  }

  bool _hasSqlcmdErrorOutput(String combinedOutputLower) {
    // More precise than "contains('error')" to avoid false positives like "0 errors".
    // Typical SQL Server error format: "Msg 3013, Level 16, State ..."
    final msgPattern = RegExp(r'\bmsg\s+\d+\b');
    final levelPattern = RegExp(r'\blevel\s+\d+\b');
    if (msgPattern.hasMatch(combinedOutputLower) &&
        levelPattern.hasMatch(combinedOutputLower)) {
      return true;
    }

    // sqlcmd client-side errors usually start with "Sqlcmd:".
    if (combinedOutputLower.contains('sqlcmd: error')) return true;

    return false;
  }

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SqlServerConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool truncateLog = true,
    bool enableChecksum = false,
    bool verifyAfterBackup = false,
  }) async {
    try {
      LoggerService.info(
        'Iniciando backup SQL Server: ${config.database} (Tipo: ${backupType.displayName})',
      );

      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = backupType == BackupType.log ? '.trn' : '.bak';
      final typeSlug = backupType.name;
      final fileName =
          customFileName ??
          '${config.database}_${typeSlug}_$timestamp$extension';
      final backupPath = p.join(outputDirectory, fileName);

      final normalizedPath = backupPath.replaceAll('\\', '/');

      final escapedBackupPath = normalizedPath.replaceAll("'", "''");

      String checksumClause = enableChecksum ? 'CHECKSUM, ' : '';
      String query;

      switch (backupType) {
        case BackupType.full:
        case BackupType.fullSingle:
          query =
              "BACKUP DATABASE [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH $checksumClause NOFORMAT, INIT, "
              "NAME = N'${config.database}-Full Database Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
        case BackupType.differential:
          query =
              "BACKUP DATABASE [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH DIFFERENTIAL, $checksumClause NOFORMAT, INIT, "
              "NAME = N'${config.database}-Differential Database Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
        case BackupType.log:
          final copyOnlyClause = truncateLog ? '' : 'COPY_ONLY, ';
          query =
              "BACKUP LOG [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH $copyOnlyClause$checksumClause NOFORMAT, INIT, "
              "NAME = N'${config.database}-Transaction Log Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
      }

      final arguments = [..._baseSqlcmdArgs(config), '-Q', query];

      final stopwatch = Stopwatch()..start();
      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        timeout: const Duration(hours: 2),
      );

      stopwatch.stop();

      return result.fold((processResult) async {
        final stdout = processResult.stdout;
        final stderr = processResult.stderr;

        final outputLower = (stdout + stderr).toLowerCase();
        if (_hasSqlcmdErrorOutput(outputLower)) {
          LoggerService.error(
            'Backup SQL Server falhou (mensagem de erro detectada)',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: $stdout\n'
              'STDERR: $stderr',
            ),
          );
          return rd.Failure(
            BackupFailure(
              message:
                  'Erro ao executar backup SQL Server\n'
                  'STDOUT: $stdout\n'
                  'STDERR: $stderr',
            ),
          );
        }

        if (!processResult.isSuccess) {
          LoggerService.error(
            'Backup SQL Server falhou',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: $stdout\n'
              'STDERR: $stderr',
            ),
          );
          return rd.Failure(
            BackupFailure(
              message:
                  'Erro ao executar backup SQL Server (Exit Code: ${processResult.exitCode})\n'
                  'STDERR: $stderr',
            ),
          );
        }

        await Future.delayed(const Duration(milliseconds: 1000));

        final backupFile = File(backupPath);

        bool fileExists = false;
        for (int i = 0; i < 20; i++) {
          if (await backupFile.exists()) {
            fileExists = true;
            break;
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (!fileExists) {
          return rd.Failure(
            BackupFailure(
              message: 'Arquivo de backup não foi criado em: $backupPath',
            ),
          );
        }

        final fileSize = await backupFile.length();

        if (fileSize == 0) {
          return rd.Failure(
            BackupFailure(
              message: 'Arquivo de backup foi criado mas está vazio',
            ),
          );
        }

        LoggerService.info(
          'Backup SQL Server concluído: $backupPath (${_formatBytes(fileSize)})',
        );

        // Verificar integridade do backup se solicitado
        if (verifyAfterBackup) {
          LoggerService.info('Verificando integridade do backup...');
          final verifyQuery =
              "RESTORE VERIFYONLY FROM DISK = N'$escapedBackupPath' "
              "${enableChecksum ? 'WITH CHECKSUM' : ''}";

          final verifyArguments = [
            ..._baseSqlcmdArgs(config),
            '-Q',
            verifyQuery,
          ];

          final verifyResult = await _processService.run(
            executable: 'sqlcmd',
            arguments: verifyArguments,
            timeout: const Duration(minutes: 30),
          );

          verifyResult.fold(
            (processResult) {
              if (processResult.isSuccess) {
                LoggerService.info(
                  'Verificação de integridade concluída com sucesso',
                );
              } else {
                LoggerService.warning(
                  'Verificação de integridade falhou: ${processResult.stderr}',
                );
                // Não falha o backup, apenas registra o warning
              }
            },
            (failure) {
              LoggerService.warning(
                'Erro ao verificar integridade do backup: ${failure is Failure ? failure.message : failure.toString()}',
              );
              // Não falha o backup, apenas registra o warning
            },
          );
        }

        return rd.Success(
          BackupExecutionResult(
            backupPath: backupPath,
            fileSize: fileSize,
            duration: stopwatch.elapsed,
            databaseName: config.database,
          ),
        );
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao executar backup SQL Server', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar backup SQL Server: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(SqlServerConfig config) async {
    try {
      final query = 'SELECT @@VERSION';

      final arguments = [..._baseSqlcmdArgs(config), '-Q', query, '-t', '5'];

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        timeout: const Duration(seconds: 10),
      );

      return result.fold(
        (processResult) => rd.Success(processResult.isSuccess),
        (failure) => rd.Failure(failure),
      );
    } catch (e) {
      return rd.Failure(
        NetworkFailure(message: 'Erro ao testar conexão SQL Server: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required SqlServerConfig config,
    Duration? timeout,
  }) async {
    try {
      final query =
          "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') ORDER BY name";

      final arguments = [
        ..._baseSqlcmdArgs(config),
        '-Q',
        query,
        '-h',
        '-1',
        '-W',
        '-t',
        '10',
      ];

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        timeout: timeout ?? const Duration(seconds: 15),
      );

      return result.fold((processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            NetworkFailure(
              message:
                  'Erro ao listar bancos de dados: ${processResult.stderr}',
            ),
          );
        }

        final output = processResult.stdout.trim();
        if (output.isEmpty) {
          return const rd.Success([]);
        }

        final databases = output
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('---'))
            .toList();

        LoggerService.debug('Bancos de dados encontrados: ${databases.length}');
        return rd.Success(databases);
      }, (failure) => rd.Failure(failure));
    } catch (e) {
      LoggerService.error('Erro ao listar bancos de dados', e);
      return rd.Failure(
        NetworkFailure(message: 'Erro ao listar bancos de dados: $e'),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
