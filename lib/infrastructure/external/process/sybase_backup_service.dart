import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/backup_type.dart';
import '../../../domain/entities/sybase_config.dart';
import '../../../domain/services/backup_execution_result.dart';
import '../../../domain/services/i_sybase_backup_service.dart';
import 'process_service.dart' as ps;

class SybaseBackupService implements ISybaseBackupService {
  final ps.ProcessService _processService;

  SybaseBackupService(this._processService);

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog = true,
  }) async {
    try {
      LoggerService.info(
        'Iniciando backup Sybase: ${config.serverName} (Tipo: ${backupType.displayName})',
      );

      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final effectiveType = backupType == BackupType.differential
          ? BackupType.full
          : backupType;

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = effectiveType == BackupType.log ? '.trn' : '';
      final typeSlug = effectiveType.name;

      String backupPath;
      if (effectiveType == BackupType.full) {
        backupPath = p.join(outputDirectory, config.databaseName);
      } else {
        final fileName =
            customFileName ??
            '${config.databaseName}_${typeSlug}_$timestamp$extension';
        backupPath = p.join(outputDirectory, fileName);
      }

      final executable = dbbackupPath ?? 'dbbackup';

      final databaseName = config.databaseName;

      final stopwatch = Stopwatch()..start();
      rd.Result<ps.ProcessResult>? result;
      String lastError = '';

      LoggerService.info('Tentando backup via comando SQL BACKUP DATABASE...');

      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final escapedBackupPath = backupPath.replaceAll('\\', '\\\\');

      final dbisqlConnections = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',

        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
      ];

      bool sqlBackupSuccess = false;

      for (final connStr in dbisqlConnections) {
        LoggerService.debug('Tentando dbisql com: $connStr');

        String backupSql;
        switch (effectiveType) {
          case BackupType.full:
            backupSql = "BACKUP DATABASE DIRECTORY '$escapedBackupPath'";
            break;
          case BackupType.log:
            backupSql =
                "BACKUP DATABASE DIRECTORY '$escapedBackupPath' TRANSACTION LOG ONLY";
            break;
          case BackupType.differential:
            backupSql = "BACKUP DATABASE DIRECTORY '$escapedBackupPath'";
            break;
        }

        final dbisqlArgs = ['-c', connStr, '-nogui', backupSql];

        result = await _processService.run(
          executable: 'dbisql',
          arguments: dbisqlArgs,
          timeout: const Duration(hours: 2),
        );

        result.fold(
          (processResult) {
            if (processResult.isSuccess) {
              sqlBackupSuccess = true;
              LoggerService.info(
                'Backup SQL bem-sucedido com conexão: $connStr',
              );
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

        if (sqlBackupSuccess) break;
      }

      if (!sqlBackupSuccess) {
        LoggerService.info('Backup SQL falhou, tentando dbbackup...');

        final connectionStrategies = <Map<String, String>>[
          {
            'name': 'ENG+DBN (serverName + databaseName)',
            'conn':
                'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
          },

          {
            'name': 'ENG+DBN (databaseName como ambos)',
            'conn':
                'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
          },

          {
            'name': 'Apenas ENG por serverName',
            'conn':
                'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
          },

          {
            'name': 'Conexão via TCPIP',
            'conn':
                'HOST=localhost:${config.port};DBN=$databaseName;UID=${config.username};PWD=${config.password};LINKS=TCPIP',
          },
        ];

        for (final strategy in connectionStrategies) {
          LoggerService.debug('Tentando dbbackup: ${strategy['name']}');
          LoggerService.debug('Connection string: ${strategy['conn']}');

          final arguments = [
            '-x',
            '-c',
            strategy['conn']!,
            '-d',
            '-r',
            '-y',
            backupPath,
          ];

          result = await _processService.run(
            executable: executable,
            arguments: arguments,
            timeout: const Duration(hours: 2),
          );

          bool success = false;
          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                success = true;
                LoggerService.info(
                  'Backup bem-sucedido com: ${strategy['name']}',
                );
              } else {
                lastError = processResult.stderr;
                LoggerService.debug(
                  'Estratégia "${strategy['name']}" falhou: ${processResult.stderr}',
                );
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

          if (success) break;
        }
      }

      stopwatch.stop();

      if (result == null) {
        return rd.Failure(
          BackupFailure(
            message:
                'Nenhuma estratégia de backup funcionou. Último erro: $lastError',
          ),
        );
      }

      return result.fold((processResult) async {
        if (!processResult.isSuccess) {
          LoggerService.error(
            'Backup Sybase falhou após todas as tentativas',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: ${processResult.stdout}\n'
              'STDERR: ${processResult.stderr}',
            ),
          );

          String errorMessage = 'Erro ao executar backup Sybase';
          final stderr = processResult.stderr.toLowerCase();

          if (stderr.contains('already in use')) {
            errorMessage =
                'O banco de dados está em uso e não foi possível conectar. '
                'Verifique se o nome do servidor (Engine Name) está correto. '
                'Geralmente é o nome do arquivo .db sem extensão (ex: "Data7").';
          } else if (stderr.contains('server not found') ||
              stderr.contains('unable to connect')) {
            errorMessage =
                'Não foi possível encontrar/conectar ao servidor Sybase. '
                'Verifique:\n'
                '1. Se o servidor Sybase está rodando\n'
                '2. Se a porta ${config.port} está correta\n'
                '3. O Engine Name geralmente é o nome do arquivo .db (ex: "$databaseName")';
          } else if (stderr.contains('permission denied')) {
            errorMessage =
                'Permissão negada. Verifique se o usuário tem permissão para fazer backup.';
          } else if (stderr.contains('invalid user') ||
              stderr.contains('login failed')) {
            errorMessage = 'Usuário ou senha inválidos.';
          } else {
            errorMessage =
                'Erro ao executar backup (Exit Code: ${processResult.exitCode})\n${processResult.stderr}';
          }

          return rd.Failure(BackupFailure(message: errorMessage));
        }

        await Future.delayed(const Duration(milliseconds: 500));

        int totalSize = 0;
        String actualBackupPath = backupPath;

        final backupDir = Directory(backupPath);
        final backupFile = File(backupPath);

        bool backupFound = false;
        for (int i = 0; i < 10; i++) {
          if (await backupDir.exists()) {
            final files = await backupDir.list().toList();
            if (files.isNotEmpty) {
              for (final entity in files) {
                if (entity is File) {
                  totalSize += await entity.length();
                }
              }
              if (totalSize > 0) {
                backupFound = true;
                break;
              }
            }
          }

          if (await backupFile.exists()) {
            totalSize = await backupFile.length();
            if (totalSize > 0) {
              backupFound = true;
              break;
            }
          }
          await Future.delayed(const Duration(milliseconds: 500));
        }

        if (!backupFound) {
          return rd.Failure(
            BackupFailure(message: 'Backup não foi criado em: $backupPath'),
          );
        }

        if (totalSize == 0) {
          return rd.Failure(
            BackupFailure(message: 'Backup foi criado mas está vazio'),
          );
        }

        LoggerService.info(
          'Backup Sybase concluído: $actualBackupPath (${_formatBytes(totalSize)})',
        );

        return rd.Success(
          BackupExecutionResult(
            backupPath: actualBackupPath,
            fileSize: totalSize,
            duration: stopwatch.elapsed,
            databaseName: config.databaseName,
          ),
        );
      }, (failure) => rd.Failure(failure));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao executar backup Sybase', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar backup Sybase: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(SybaseConfig config) async {
    try {
      LoggerService.info(
        'Testando conexão Sybase: Engine=${config.serverName}, DBN=${config.databaseName}',
      );

      if (config.serverName.trim().isEmpty) {
        return rd.Failure(
          BackupFailure(
            message: 'Nome do servidor (Engine Name) não pode estar vazio',
          ),
        );
      }

      if (config.databaseName.trim().isEmpty) {
        return rd.Failure(
          BackupFailure(
            message: 'Nome do banco de dados (DBN) não pode estar vazio',
          ),
        );
      }

      if (config.username.trim().isEmpty) {
        return rd.Failure(
          BackupFailure(message: 'Usuário não pode estar vazio'),
        );
      }

      final databaseName = config.databaseName;
      final connectionStrategies = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
      ];

      String lastError = '';

      for (final connStr in connectionStrategies) {
        try {
          LoggerService.debug('Tentando teste de conexão com: $connStr');

          final arguments = ['-c', connStr, '-q', 'SELECT 1', '-nogui'];

          final result = await _processService.run(
            executable: 'dbisql',
            arguments: arguments,
            timeout: const Duration(seconds: 10),
          );

          final success = result.fold(
            (processResult) => processResult.isSuccess,
            (failure) => false,
          );

          if (success) {
            LoggerService.info('Teste de conexão Sybase bem-sucedido');
            return rd.Success(true);
          }

          result.fold(
            (processResult) {
              final combinedOutput =
                  '${processResult.stdout}\n${processResult.stderr}'.trim();
              lastError = combinedOutput.isNotEmpty
                  ? combinedOutput
                  : 'Falha na conexão (Exit Code: ${processResult.exitCode})';
              LoggerService.debug('Estratégia falhou: $lastError');
            },
            (failure) {
              lastError = failure is Failure
                  ? failure.message
                  : failure.toString();
              LoggerService.debug('Estratégia falhou: $lastError');
            },
          );
        } catch (e) {
          lastError = e.toString();
          LoggerService.debug('Erro ao testar estratégia: $lastError');
        }
      }

      String errorMessage =
          'Não foi possível conectar ao banco de dados Sybase';

      if (lastError.isNotEmpty) {
        final errorLower = lastError.toLowerCase();
        if (errorLower.contains('unable to connect') ||
            errorLower.contains('server not found')) {
          errorMessage =
              'Não foi possível conectar ao servidor Sybase. Verifique:\n'
              '1. Se o servidor está rodando\n'
              '2. Se o Engine Name (${config.serverName}) está correto\n'
              '3. Se o DBN (${config.databaseName}) está correto\n'
              '4. Se a porta (${config.port}) está correta';
        } else if (errorLower.contains('invalid user') ||
            errorLower.contains('login failed')) {
          errorMessage = 'Usuário ou senha inválidos.';
        } else if (errorLower.contains('already in use')) {
          errorMessage =
              'O banco de dados está em uso. Verifique se o Engine Name está correto.';
        } else {
          errorMessage = 'Erro ao conectar: $lastError';
        }
      }

      LoggerService.warning(
        'Todas as estratégias de teste de conexão falharam',
      );
      return rd.Failure(NetworkFailure(message: errorMessage));
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);
      return rd.Failure(
        NetworkFailure(
          message: 'Erro ao testar conexão Sybase: ${e.toString()}',
          originalError: e,
        ),
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
