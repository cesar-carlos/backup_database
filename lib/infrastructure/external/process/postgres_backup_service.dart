import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/backup_type.dart';
import '../../../domain/entities/postgres_config.dart';
import '../../../domain/services/backup_execution_result.dart';
import '../../../domain/services/i_postgres_backup_service.dart';
import 'process_service.dart' as ps;

class PostgresBackupService implements IPostgresBackupService {
  final ps.ProcessService _processService;

  PostgresBackupService(this._processService);

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required PostgresConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool verifyAfterBackup = false,
    String? pgBasebackupPath,
  }) async {
    LoggerService.info(
      'Iniciando backup PostgreSQL: ${config.database} (Tipo: ${backupType.displayName})',
    );

    final outputDir = Directory(outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final typeSlug = backupType == BackupType.log
        ? 'log'
        : backupType == BackupType.differential
            ? 'incremental'
            : backupType == BackupType.fullSingle
                ? 'fullSingle'
                : 'full';

    final String backupPath;
    if (backupType == BackupType.fullSingle) {
      final backupFileName =
          customFileName ?? '${config.database}_${typeSlug}_$timestamp.backup';
      backupPath = p.join(outputDirectory, backupFileName);
    } else {
      final backupDirName =
          customFileName ?? '${config.database}_${typeSlug}_$timestamp';
      backupPath = p.join(outputDirectory, backupDirName);
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
    }

    final stopwatch = Stopwatch()..start();

    final result = await _executeBackupByType(
      config: config,
      backupType: backupType,
      backupPath: backupPath,
      outputDirectory: outputDirectory,
      pgBasebackupPath: pgBasebackupPath,
    );

    stopwatch.stop();

    return result.fold(
      (processResult) async {
        final stdout = processResult.stdout;
        final stderr = processResult.stderr;
        final outputLower = (stdout + stderr).toLowerCase();

        if (!processResult.isSuccess) {
          return _handleBackupError(
            stdout: stdout,
            stderr: stderr,
            outputLower: outputLower,
            backupType: backupType,
          );
        }

        final sizeResult = backupType == BackupType.fullSingle
            ? await _calculateFileSize(backupPath)
            : await _calculateBackupSize(backupPath);
        return sizeResult.fold((totalSize) async {
          if (totalSize == 0) {
            return rd.Failure(
              BackupFailure(
                message: 'Backup foi criado mas está vazio',
                originalError: Exception('Backup vazio'),
              ),
            );
          }

          LoggerService.info(
            'Backup PostgreSQL concluído: $backupPath (${_formatBytes(totalSize)})',
          );

          if (verifyAfterBackup && backupType != BackupType.log) {
            final verifyResult = backupType == BackupType.fullSingle
                ? await _verifyFullSingleBackup(backupPath)
                : await _verifyBackup(backupPath);
            verifyResult.fold(
              (_) {
                LoggerService.info(
                  'Verificação de integridade concluída com sucesso',
                );
              },
              (failure) {
                final errorMessage = failure is Failure
                    ? failure.message
                    : failure.toString();
                LoggerService.warning(
                  'Verificação de integridade falhou: $errorMessage',
                );
              },
            );
          }

          return rd.Success(
            BackupExecutionResult(
              backupPath: backupPath,
              fileSize: totalSize,
              duration: stopwatch.elapsed,
              databaseName: config.database,
            ),
          );
        }, (failure) => rd.Failure(failure));
      },
      (failure) async {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        final errorLower = errorMessage.toLowerCase();

        if (_isExecutableNotFoundError(errorLower, backupType)) {
          return rd.Failure(_createExecutableNotFoundFailure(backupType));
        }

        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeBackupByType({
    required PostgresConfig config,
    required BackupType backupType,
    required String backupPath,
    required String outputDirectory,
    String? pgBasebackupPath,
  }) async {
    switch (backupType) {
      case BackupType.full:
        return await _executeFullBackup(
          config: config,
          backupPath: backupPath,
          pgBasebackupPath: pgBasebackupPath,
        );

      case BackupType.fullSingle:
        return await _executeFullSingleBackup(
          config: config,
          backupPath: backupPath,
        );

      case BackupType.differential:
        final previousBackupResult = await _findPreviousFullBackup(
          outputDirectory: outputDirectory,
          databaseName: config.database,
        );

        return previousBackupResult.fold(
          (previousBackupPath) async {
            return await _executeIncrementalBackup(
              config: config,
              backupPath: backupPath,
              previousBackupPath: previousBackupPath,
              pgBasebackupPath: pgBasebackupPath,
            );
          },
          (failure) async {
            final errorMessage = failure is Failure
                ? failure.message
                : failure.toString();
            LoggerService.warning(
              'Backup incremental requer backup FULL anterior. Executando FULL: $errorMessage',
            );
            return await _executeFullBackup(
              config: config,
              backupPath: backupPath,
              pgBasebackupPath: pgBasebackupPath,
            );
          },
        );

      case BackupType.log:
        return await _executeLogBackup(
          config: config,
          backupPath: backupPath,
          pgBasebackupPath: pgBasebackupPath,
        );
    }
  }

  Future<rd.Result<ps.ProcessResult>> _executeFullBackup({
    required PostgresConfig config,
    required String backupPath,
    String? pgBasebackupPath,
  }) async {
    final executable = pgBasebackupPath ?? 'pg_basebackup';

    final arguments = [
      '-h',
      config.host,
      '-p',
      config.port.toString(),
      '-U',
      config.username,
      '-D',
      backupPath,
      '-P',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return await _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeFullSingleBackup({
    required PostgresConfig config,
    required String backupPath,
  }) async {
    final executable = 'pg_dump';

    final arguments = [
      '-h',
      config.host,
      '-p',
      config.port.toString(),
      '-U',
      config.username,
      '-d',
      config.database,
      '-F',
      'c',
      '-f',
      backupPath,
      '-v',
      '--no-owner',
      '--no-privileges',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return await _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeIncrementalBackup({
    required PostgresConfig config,
    required String backupPath,
    required String previousBackupPath,
    String? pgBasebackupPath,
  }) async {
    final executable = pgBasebackupPath ?? 'pg_basebackup';

    final manifestPath = p.join(previousBackupPath, 'backup_manifest');
    final manifestFile = File(manifestPath);

    if (!await manifestFile.exists()) {
      return rd.Failure(
        BackupFailure(
          message:
              'Backup anterior não possui backup_manifest. '
              'Backups incrementais requerem backup FULL com manifest.',
          originalError: Exception('backup_manifest não encontrado'),
        ),
      );
    }

    final arguments = [
      '-h',
      config.host,
      '-p',
      config.port.toString(),
      '-U',
      config.username,
      '--incremental',
      manifestPath,
      '-D',
      backupPath,
      '-P',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return await _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeLogBackup({
    required PostgresConfig config,
    required String backupPath,
    String? pgBasebackupPath,
  }) async {
    final executable = pgBasebackupPath ?? 'pg_basebackup';

    final arguments = [
      '-h',
      config.host,
      '-p',
      config.port.toString(),
      '-U',
      config.username,
      '-D',
      backupPath,
      '-P',
      '-X',
      'stream',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return await _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 1),
    );
  }

  Future<rd.Result<String>> _findPreviousFullBackup({
    required String outputDirectory,
    required String databaseName,
  }) async {
    try {
      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Diretório de backup não existe: $outputDirectory',
            originalError: Exception('Diretório não encontrado'),
          ),
        );
      }

      final fullBackups = <Directory>[];
      await for (final entity in outputDir.list()) {
        if (entity is Directory) {
          final dirName = p.basename(entity.path);
          if (dirName.startsWith('${databaseName}_full_')) {
            final manifestPath = p.join(entity.path, 'backup_manifest');
            final manifestFile = File(manifestPath);
            if (await manifestFile.exists()) {
              fullBackups.add(entity);
            }
          }
        }
      }

      if (fullBackups.isEmpty) {
        return rd.Failure(
          BackupFailure(
            message:
                'Nenhum backup FULL anterior encontrado para backup incremental. '
                'Execute um backup FULL primeiro.',
            originalError: Exception('Backup anterior não encontrado'),
          ),
        );
      }

      fullBackups.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      return rd.Success(fullBackups.first.path);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao buscar backup anterior', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao buscar backup anterior: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<int>> _calculateBackupSize(String backupPath) async {
    try {
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Diretório de backup não existe: $backupPath',
            originalError: Exception('Diretório não encontrado'),
          ),
        );
      }

      int totalSize = 0;
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return rd.Success(totalSize);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do backup', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do backup: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<int>> _calculateFileSize(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Arquivo de backup não existe: $backupPath',
            originalError: Exception('Arquivo não encontrado'),
          ),
        );
      }

      final fileSize = await backupFile.length();
      return rd.Success(fileSize);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do arquivo', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do arquivo: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<void>> _verifyBackup(String backupPath) async {
    final verifyArgs = ['-D', backupPath, '-m'];

    final verifyResult = await _processService.run(
      executable: 'pg_verifybackup',
      arguments: verifyArgs,
      timeout: const Duration(minutes: 30),
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, (failure) => rd.Failure(failure));
  }

  Future<rd.Result<void>> _verifyFullSingleBackup(String backupPath) async {
    final verifyArgs = ['-l', backupPath];

    final verifyResult = await _processService.run(
      executable: 'pg_restore',
      arguments: verifyArgs,
      timeout: const Duration(minutes: 30),
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        final objectCount = processResult.stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty && !line.startsWith(';'))
            .length;
        LoggerService.info(
          'Verificação de integridade concluída. Objetos no backup: $objectCount',
        );
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, (failure) => rd.Failure(failure));
  }

  rd.Result<BackupExecutionResult> _handleBackupError({
    required String stdout,
    required String stderr,
    required String outputLower,
    required BackupType backupType,
  }) {
    if (_isExecutableNotFoundError(outputLower, backupType)) {
      return rd.Failure(_createExecutableNotFoundFailure(backupType));
    }

    final errorMessage = stderr.isNotEmpty ? stderr : stdout;
    return rd.Failure(
      BackupFailure(
        message: 'Backup PostgreSQL falhou: $errorMessage',
        originalError: Exception(errorMessage),
      ),
    );
  }

  bool _isExecutableNotFoundError(String errorLower, BackupType backupType) {
    final toolName = backupType == BackupType.fullSingle
        ? 'pg_dump'
        : 'pg_basebackup';

    return (errorLower.contains("'$toolName'") ||
            errorLower.contains(toolName) ||
            errorLower.contains('command not found')) &&
        (errorLower.contains('não é reconhecido') ||
            errorLower.contains("não reconhecido") ||
            errorLower.contains('não reconhecido como um comando interno') ||
            errorLower.contains('não reconhecido como') ||
            errorLower.contains('command not found') ||
            errorLower.contains('não encontrado') ||
            errorLower.contains('não foi encontrado') ||
            errorLower.contains('cmdlet') ||
            errorLower.contains('programa operável') ||
            errorLower.contains('arquivo de script') ||
            errorLower.contains('programa oper'));
  }

  BackupFailure _createExecutableNotFoundFailure(BackupType backupType) {
    final toolName = backupType == BackupType.fullSingle
        ? 'pg_dump'
        : 'pg_basebackup';

    return BackupFailure(
      message:
          '$toolName não encontrado no PATH do sistema.\n\n'
          'INSTRUÇÕES PARA ADICIONAR AO PATH:\n\n'
          '1. Localize a pasta bin do PostgreSQL instalado\n'
          '   (geralmente: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
          '2. Adicione ao PATH do Windows:\n'
          '   - Pressione Win + X e selecione "Sistema"\n'
          '   - Clique em "Configurações avançadas do sistema"\n'
          '   - Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
          '   - Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
          '   - Clique em "Novo" e adicione o caminho completo da pasta bin\n'
          '   - Clique em "OK" em todas as janelas\n\n'
          '3. Reinicie o aplicativo de backup\n\n'
          'Consulte: docs\\path_setup.md para mais detalhes.',
      originalError: Exception('$toolName não encontrado'),
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(PostgresConfig config) async {
    LoggerService.info(
      'Testando conexão PostgreSQL: ${config.host}:${config.port}/${config.database}',
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
      'SELECT 1',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(seconds: 30),
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('Conexão PostgreSQL bem-sucedida');
          return rd.Success(true);
        } else {
          final errorOutput = '${processResult.stderr}\n${processResult.stdout}'
              .trim();
          final errorLower = errorOutput.toLowerCase();

          if (_isExecutableNotFoundError(errorLower, BackupType.full)) {
            return rd.Failure(
              ValidationFailure(
                message: _createExecutableNotFoundFailure(
                  BackupType.full,
                ).message,
              ),
            );
          }

          String errorMessage = 'Falha na conexão';

          if (errorLower.contains('password authentication failed') ||
              errorLower.contains('autenticação de senha falhou')) {
            errorMessage = 'Falha na autenticação: usuário ou senha incorretos';
          } else if (errorLower.contains('could not connect') ||
              errorLower.contains('não foi possível conectar')) {
            errorMessage =
                'Não foi possível conectar ao servidor. Verifique host e porta.';
          } else if (errorLower.contains('does not exist') ||
              errorLower.contains('não existe')) {
            errorMessage = 'Banco de dados não existe';
          } else if (errorOutput.isNotEmpty) {
            errorMessage = errorOutput.split('\n').first.trim();
            if (errorMessage.length > 200) {
              errorMessage = '${errorMessage.substring(0, 200)}...';
            }
          }

          return rd.Failure(
            ValidationFailure(
              message: errorMessage,
              originalError: Exception(errorOutput),
            ),
          );
        }
      },
      (failure) {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        final errorLower = errorMessage.toLowerCase();

        if (_isExecutableNotFoundError(errorLower, BackupType.full)) {
          return rd.Failure(
            ValidationFailure(
              message: _createExecutableNotFoundFailure(
                BackupType.full,
              ).message,
            ),
          );
        }

        return rd.Failure(
          ValidationFailure(
            message: 'Erro ao executar psql: $errorMessage',
            originalError: Exception(errorMessage),
          ),
        );
      },
    );
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required PostgresConfig config,
    Duration? timeout,
  }) async {
    LoggerService.info('Listando bancos de dados PostgreSQL');

    final arguments = [
      '-h',
      config.host,
      '-p',
      config.port.toString(),
      '-U',
      config.username,
      '-d',
      'postgres',
      '-t',
      '-A',
      '-c',
      "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres'",
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: timeout ?? const Duration(seconds: 30),
    );

    return result.fold((processResult) {
      if (processResult.isSuccess) {
        final databases = processResult.stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => line.trim())
            .toList();
        LoggerService.info('Bancos encontrados: ${databases.length}');
        return rd.Success(databases);
      } else {
        final errorOutput = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        return rd.Failure(
          BackupFailure(
            message: 'Erro ao listar bancos: $errorOutput',
            originalError: Exception(errorOutput),
          ),
        );
      }
    }, (failure) => rd.Failure(failure));
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
