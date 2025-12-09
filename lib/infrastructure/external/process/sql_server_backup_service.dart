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

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SqlServerConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool truncateLog = true,
  }) async {
    try {
      LoggerService.info(
        'Iniciando backup SQL Server: ${config.database} (Tipo: ${backupType.displayName})',
      );

      // Verificar se o diretório de saída existe
      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Gerar nome do arquivo de backup com extensão apropriada
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = backupType == BackupType.log ? '.trn' : '.bak';
      final typeSlug = backupType.name; // full | differential | log
      final fileName = customFileName ??
          '${config.database}_${typeSlug}_$timestamp$extension';
      final backupPath = p.join(outputDirectory, fileName);

      // Construir comando sqlcmd
      // Converter barras invertidas para barras normais (SQL Server aceita ambos)
      final normalizedPath = backupPath.replaceAll('\\', '/');
      // Escapar aspas simples no caminho para SQL Server
      final escapedBackupPath = normalizedPath.replaceAll("'", "''");

      // Construir query baseado no tipo de backup
      String query;

      switch (backupType) {
        case BackupType.full:
          query =
              "BACKUP DATABASE [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH NOFORMAT, NOINIT, "
              "NAME = N'${config.database}-Full Database Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
        case BackupType.differential:
          query =
              "BACKUP DATABASE [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH DIFFERENTIAL, NOFORMAT, NOINIT, "
              "NAME = N'${config.database}-Differential Database Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
        case BackupType.log:
          final copyOnlyClause = truncateLog ? '' : 'COPY_ONLY, ';
          query =
              "BACKUP LOG [${config.database}] "
              "TO DISK = N'$escapedBackupPath' "
              "WITH ${copyOnlyClause}NOFORMAT, NOINIT, "
              "NAME = N'${config.database}-Transaction Log Backup', "
              "SKIP, NOREWIND, NOUNLOAD, STATS = 10";
          break;
      }

      final arguments = [
        '-S',
        '${config.server},${config.port}',
        '-d',
        config.database,
        '-Q',
        query,
      ];

      // Adicionar autenticação
      if (config.username.isNotEmpty) {
        arguments.addAll(['-U', config.username]);
        if (config.password.isNotEmpty) {
          arguments.addAll(['-P', config.password]);
        }
      } else {
        // Usar autenticação do Windows
        arguments.add('-E');
      }

      // Executar backup
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

        // Verificar mensagens de erro comuns no STDOUT/STDERR mesmo com exit code 0
        final outputLower = (stdout + stderr).toLowerCase();
        if (outputLower.contains('error') ||
            outputLower.contains('failed') ||
            outputLower.contains('cannot') ||
            outputLower.contains('unable')) {
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

        // Aguardar um pouco para garantir que o arquivo foi completamente escrito
        await Future.delayed(const Duration(milliseconds: 1000));

        // Verificar se o arquivo foi criado
        final backupFile = File(backupPath);

        // Tentar verificar múltiplas vezes (até 10 segundos)
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

      final arguments = [
        '-S', '${config.server},${config.port}',
        '-Q', query,
        '-t', '5', // Timeout de 5 segundos
      ];

      if (config.username.isNotEmpty) {
        arguments.addAll(['-U', config.username]);
        if (config.password.isNotEmpty) {
          arguments.addAll(['-P', config.password]);
        }
      } else {
        arguments.add('-E');
      }

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
      // Query para listar bancos de dados
      final query =
          "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') ORDER BY name";

      final arguments = [
        '-S', '${config.server},${config.port}',
        '-Q', query,
        '-h', '-1', // Sem cabeçalho
        '-W', // Remover espaços em branco
        '-t', '10', // Timeout de 10 segundos
      ];

      if (config.username.isNotEmpty) {
        arguments.addAll(['-U', config.username]);
        if (config.password.isNotEmpty) {
          arguments.addAll(['-P', config.password]);
        }
      } else {
        arguments.add('-E');
      }

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

        // Parse da saída do sqlcmd
        final output = processResult.stdout.trim();
        if (output.isEmpty) {
          return const rd.Success([]);
        }

        // Dividir por linhas e filtrar linhas vazias
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
