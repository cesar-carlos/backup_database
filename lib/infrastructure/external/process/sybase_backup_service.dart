import 'dart:io';

import 'package:result_dart/result_dart.dart' as rd;
import 'package:path/path.dart' as p;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/backup_type.dart';
import '../../../domain/entities/sybase_config.dart';
import 'process_service.dart' as ps;

class SybaseBackupResult {
  final String backupPath;
  final int fileSize;
  final Duration duration;
  final String databaseName;

  const SybaseBackupResult({
    required this.backupPath,
    required this.fileSize,
    required this.duration,
    required this.databaseName,
  });
}

class SybaseBackupService {
  final ps.ProcessService _processService;

  SybaseBackupService(this._processService);

  Future<rd.Result<SybaseBackupResult>> executeBackup({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
  }) async {
    try {
      LoggerService.info(
        'Iniciando backup Sybase: ${config.serverName} (Tipo: ${backupType.displayName})',
      );

      // Verificar se o diretório de saída existe
      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // Gerar nome do arquivo de backup usando databaseName (DBN) ao invés de serverName
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = backupType == BackupType.log ? '.trn' : '';
      final fileName = customFileName ?? '${config.databaseName}_$timestamp$extension';
      final backupPath = p.join(outputDirectory, fileName);

      // Construir comando dbbackup
      final executable = dbbackupPath ?? 'dbbackup';

      // Usar databaseName como DBN (Database Name)
      final databaseName = config.databaseName;

      final stopwatch = Stopwatch()..start();
      rd.Result<ps.ProcessResult>? result;
      String lastError = '';

      // ESTRATÉGIA PRINCIPAL: Usar comando SQL BACKUP DATABASE via dbisql
      // Isso funciona porque o comando é executado pelo próprio servidor
      LoggerService.info('Tentando backup via comando SQL BACKUP DATABASE...');

      // O comando BACKUP DATABASE espera um DIRETÓRIO, não um arquivo
      // Criar o diretório de backup
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Escapar backslashes para o Windows no comando SQL
      final escapedBackupPath = backupPath.replaceAll('\\', '\\\\');

      // Lista de connection strings para tentar com dbisql
      // Usar databaseName como DBN e serverName como ENG
      final dbisqlConnections = <String>[
        // Conexão 1: ENG (serverName) + DBN (databaseName) - mais comum
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        // Conexão 2: Apenas ENG (fallback)
        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
        // Conexão 3: Usando databaseName como ENG também (caso sejam iguais)
        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
      ];

      bool sqlBackupSuccess = false;

      for (final connStr in dbisqlConnections) {
        LoggerService.debug('Tentando dbisql com: $connStr');

        // Comando SQL para backup - o servidor executa o backup internamente
        // Construir comando baseado no tipo de backup
        String backupSql;
        switch (backupType) {
          case BackupType.full:
            backupSql = "BACKUP DATABASE DIRECTORY '$escapedBackupPath'";
            break;
          case BackupType.differential:
            backupSql = "BACKUP DATABASE DIRECTORY '$escapedBackupPath' WITH DIFFERENTIAL";
            break;
          case BackupType.log:
            backupSql = "BACKUP DATABASE DIRECTORY '$escapedBackupPath' TRANSACTION LOG ONLY";
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

      // Se o backup via SQL não funcionou, tentar com dbbackup
      if (!sqlBackupSuccess) {
        LoggerService.info('Backup SQL falhou, tentando dbbackup...');

        // Lista de estratégias de conexão para tentar com dbbackup
        // Baseado no comando que funcionou: dbbackup -x -c "ENG=VL;DBN=VL;UID=dba;PWD=sql"
        // Usar serverName como ENG e databaseName como DBN
        final connectionStrategies = <Map<String, String>>[
          // Estratégia 1: ENG (serverName) + DBN (databaseName) - mais provável de funcionar
          {
            'name': 'ENG+DBN (serverName + databaseName)',
            'conn':
                'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
          },
          // Estratégia 2: Usar databaseName como ENG também (caso sejam iguais)
          {
            'name': 'ENG+DBN (databaseName como ambos)',
            'conn':
                'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
          },
          // Estratégia 3: Apenas ENG por serverName (fallback)
          {
            'name': 'Apenas ENG por serverName',
            'conn':
                'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
          },
          // Estratégia 4: Conectar via TCPIP com HOST e porta
          {
            'name': 'Conexão via TCPIP',
            'conn':
                'HOST=localhost:${config.port};DBN=$databaseName;UID=${config.username};PWD=${config.password};LINKS=TCPIP',
          },
        ];

        for (final strategy in connectionStrategies) {
          LoggerService.debug('Tentando dbbackup: ${strategy['name']}');
          LoggerService.debug('Connection string: ${strategy['conn']}');

          // Argumentos baseados no comando que funcionou:
          // dbbackup -x -c "ENG=VL;DBN=VL;UID=dba;PWD=sql"
          final arguments = [
            '-x', // Backup com extensões (transaction log)
            '-c', strategy['conn']!,
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

          // Verificar se funcionou
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

          // Mensagem de erro mais amigável
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

        // Aguardar um pouco para garantir que os arquivos foram completamente escritos
        await Future.delayed(const Duration(milliseconds: 500));

        // O backup pode criar um diretório (BACKUP DATABASE) ou arquivo (dbbackup)
        // Verificar ambos os casos
        int totalSize = 0;
        String actualBackupPath = backupPath;

        final backupDir = Directory(backupPath);
        final backupFile = File(backupPath);

        // Tentar verificar múltiplas vezes (até 5 segundos)
        bool backupFound = false;
        for (int i = 0; i < 10; i++) {
          // Verificar se é um diretório com arquivos
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
          // Verificar se é um arquivo direto
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
          SybaseBackupResult(
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

  Future<rd.Result<bool>> testConnection(SybaseConfig config) async {
    try {
      LoggerService.info(
        'Testando conexão Sybase: Engine=${config.serverName}, DBN=${config.databaseName}',
      );

      // Validar campos obrigatórios
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

      // Usar as mesmas estratégias de conexão que o backup usa
      // Isso garante que o teste seja consistente com o que será usado no backup
      final databaseName = config.databaseName;
      final connectionStrategies = <String>[
        // Estratégia 1: ENG (serverName) + DBN (databaseName) - mais comum
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        // Estratégia 2: Usar databaseName como ENG também (caso sejam iguais)
        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        // Estratégia 3: Apenas ENG por serverName (fallback)
        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
      ];

      String lastError = '';

      // Tentar cada estratégia de conexão
      for (final connStr in connectionStrategies) {
        try {
          LoggerService.debug('Tentando teste de conexão com: $connStr');

          final arguments = ['-c', connStr, '-q', 'SELECT 1', '-nogui'];

          final result = await _processService.run(
            executable: 'dbisql',
            arguments: arguments,
            timeout: const Duration(seconds: 10),
          );

          // Verificar se foi sucesso
          final success = result.fold(
            (processResult) => processResult.isSuccess,
            (failure) => false,
          );

          if (success) {
            LoggerService.info('Teste de conexão Sybase bem-sucedido');
            return rd.Success(true);
          }

          // Se falhou, registrar erro e continuar tentando outras estratégias
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
          // Continuar tentando outras estratégias
        }
      }

      // Se nenhuma estratégia funcionou, retornar erro com mensagem clara
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
