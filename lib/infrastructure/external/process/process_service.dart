import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:path/path.dart' as path;
import 'package:result_dart/result_dart.dart' as rd;

class ProcessResult {
  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  bool get isSuccess => exitCode == 0;
}

class ProcessService {
  Future<rd.Result<ProcessResult>> run({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      LoggerService.info('Executando: $executable ${arguments.join(' ')}');

      final mergedEnvironment = <String, String>{};

      final systemEnv = Platform.environment;
      mergedEnvironment.addAll(systemEnv);

      String? executablePath;
      String? executableDir;
      var executableFound = false;

      final isAbsolutePath = path.isAbsolute(executable);

      if (isAbsolutePath) {
        final file = File(executable);
        if (file.existsSync()) {
          executablePath = executable;
          executableDir = path.dirname(executable);
          executableFound = true;
          LoggerService.info(
            'Executável encontrado (caminho absoluto): $executablePath',
          );
        } else {
          LoggerService.debug(
            'Caminho absoluto fornecido mas arquivo não existe: $executable',
          );
        }
      } else {
        try {
          if (Platform.isWindows) {
            final whereResult = await Process.run(
              'cmd',
              ['/c', 'where', executable],
              runInShell: true,
            );

            if (whereResult.exitCode == 0 &&
                whereResult.stdout.toString().trim().isNotEmpty) {
              final foundPath = whereResult.stdout
                  .toString()
                  .trim()
                  .split('\n')
                  .first
                  .trim();
              if (foundPath.isNotEmpty && File(foundPath).existsSync()) {
                executablePath = foundPath;
                executableDir = path.dirname(foundPath);
                executableFound = true;
                LoggerService.info(
                  'Executável encontrado via where no PATH: $executablePath',
                );
              }
            } else {
              LoggerService.debug(
                'where não encontrou $executable. Exit code: ${whereResult.exitCode}, stderr: ${whereResult.stderr}',
              );
            }
          } else {
            final whereResult = await Process.run(
              'which',
              [executable],
            );

            if (whereResult.exitCode == 0 &&
                whereResult.stdout.toString().trim().isNotEmpty) {
              final foundPath = whereResult.stdout
                  .toString()
                  .trim()
                  .split('\n')
                  .first
                  .trim();
              if (foundPath.isNotEmpty && File(foundPath).existsSync()) {
                executablePath = foundPath;
                executableDir = path.dirname(foundPath);
                executableFound = true;
                LoggerService.info(
                  'Executável encontrado via which no PATH: $executablePath',
                );
              }
            }
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Erro ao usar where/which para encontrar $executable: $e',
          );
        }
      }

      if (!executableFound && Platform.isWindows) {
        final executableLower = executable.toLowerCase();
        final isPostgresTool =
            executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');

        final isSqlCmdTool = executableLower.contains('sqlcmd');

        final isSybaseTool = executableLower.contains('dbisql') ||
            executableLower.contains('dbbackup') ||
            executableLower.contains('dbverify');

        List<String>? commonPaths;

        if (isPostgresTool) {
          commonPaths = [
            r'C:\Program Files\PostgreSQL\16\bin',
            r'C:\Program Files\PostgreSQL\15\bin',
            r'C:\Program Files\PostgreSQL\14\bin',
            r'C:\Program Files\PostgreSQL\13\bin',
            r'C:\Program Files (x86)\PostgreSQL\16\bin',
            r'C:\Program Files (x86)\PostgreSQL\15\bin',
            r'C:\Program Files (x86)\PostgreSQL\14\bin',
            r'C:\Program Files (x86)\PostgreSQL\13\bin',
          ];
        } else if (isSqlCmdTool) {
          commonPaths = [
            // SQL Server 2022 (160) - ODBC 170
            r'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn',
            // SQL Server 2019 (150) - ODBC 160
            r'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\160\Tools\Binn',
            // SQL Server 2017 (140) - ODBC 150
            r'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn',
            // SQL Server 2016 (130) - ODBC 140
            r'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn',
            // SQL Server 2014 (120) - ODBC 120
            r'C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\120\Tools\Binn',
            // Binn padrão de versões específicas
            r'C:\Program Files\Microsoft SQL Server\160\Tools\Binn',
            r'C:\Program Files\Microsoft SQL Server\150\Tools\Binn',
            r'C:\Program Files\Microsoft SQL Server\140\Tools\Binn',
            r'C:\Program Files\Microsoft SQL Server\130\Tools\Binn',
            r'C:\Program Files\Microsoft SQL Server\120\Tools\Binn',
            r'C:\Program Files\Microsoft SQL Server\110\Tools\Binn',
            // x86 alternativo
            r'C:\Program Files (x86)\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\Client SDK\ODBC\160\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\Client SDK\ODBC\150\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\Client SDK\ODBC\130\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\Client SDK\ODBC\120\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\160\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\150\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\140\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\130\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\120\Tools\Binn',
            r'C:\Program Files (x86)\Microsoft SQL Server\110\Tools\Binn',
          ];
        } else if (isSybaseTool) {
          commonPaths = [
            // SQL Anywhere 17
            r'C:\Program Files\SQL Anywhere 17\Bin64',
            r'C:\Program Files (x86)\SQL Anywhere 17\Bin64',
            // SQL Anywhere 16
            r'C:\Program Files\SQL Anywhere 16\Bin64',
            r'C:\Program Files (x86)\SQL Anywhere 16\Bin64',
            // SQL Anywhere 12
            r'C:\Program Files\SQL Anywhere 12\Bin64',
            r'C:\Program Files (x86)\SQL Anywhere 12\Bin64',
            // SQL Anywhere 11
            r'C:\Program Files\SQL Anywhere 11\Bin64',
            r'C:\Program Files (x86)\SQL Anywhere 11\Bin64',
          ];
        }

        if (commonPaths != null) {
          for (final basePath in commonPaths) {
            final potentialPath = path.join(basePath, executable);
            if (File(potentialPath).existsSync()) {
              executablePath = potentialPath;
              executableDir = basePath;
              executableFound = true;
              final toolType = isPostgresTool
                  ? 'PostgreSQL'
                  : isSqlCmdTool
                      ? 'SQL Server'
                      : 'Sybase';
              LoggerService.info(
                'Executável $toolType encontrado em caminho comum: $executablePath',
              );
              break;
            }
          }
        }
      }

      if (!executableFound) {
        final executableLower = executable.toLowerCase();
        final isPostgresTool =
            executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');

        final isSqlCmdTool = executableLower.contains('sqlcmd');

        final isSybaseTool = executableLower.contains('dbisql') ||
            executableLower.contains('dbbackup') ||
            executableLower.contains('dbverify');

        String message;

        if (isPostgresTool) {
          final toolName = executableLower.contains('pg_basebackup')
              ? 'pg_basebackup'
              : executableLower.contains('pg_verifybackup')
              ? 'pg_verifybackup'
              : executableLower.contains('pg_restore')
              ? 'pg_restore'
              : executableLower.contains('pg_dump')
              ? 'pg_dump'
              : 'psql';

          message =
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
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else if (isSqlCmdTool) {
          message =
              'sqlcmd não encontrado no PATH do sistema.\n\n'
              'O sqlcmd é uma ferramenta de linha de comando do SQL Server.\n\n'
              'OPÇÕES PARA RESOLVER:\n\n'
              'Opção 1: Instalar SQL Server Command Line Tools\n'
              '  - Baixe SQL Server Command Line Tools da Microsoft\n'
              '  - Durante a instalação, selecione "SQL Server Command Line Tools"\n'
              '  - O instalador configurará o PATH automaticamente\n\n'
              'Opção 2: Adicionar ao PATH manualmente\n'
              '  - Localize a pasta Tools\\Binn do SQL Server instalado\n'
              '    (ex: C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\170\\Tools\\Binn)\n'
              '  - Adicione ao PATH do Windows:\n'
              '    * Pressione Win + X → "Sistema"\n'
              '    * Clique em "Configurações avançadas do sistema"\n'
              '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
              '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
              '    * Clique em "Novo" e adicione o caminho completo da pasta\n'
              '    * Clique em "OK" em todas as janelas\n\n'
              'Opção 3: Usar SQL Server Management Studio (SSMS)\n'
              '  - SSMS inclui sqlcmd\n'
              '  - Localize sqlcmd.exe na pasta do SSMS\n'
              '  - Adicione a pasta ao PATH conforme Opção 2\n\n'
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else if (isSybaseTool) {
          final toolName = executableLower.contains('dbisql')
              ? 'dbisql'
              : executableLower.contains('dbbackup')
              ? 'dbbackup'
              : 'dbverify';

          message =
              '$toolName não encontrado no PATH do sistema.\n\n'
              'As ferramentas do Sybase SQL Anywhere não estão disponíveis.\n\n'
              'OPÇÕES PARA RESOLVER:\n\n'
              'Opção 1: Adicionar ao PATH manualmente\n'
              '  - Localize a pasta Bin64 do SQL Anywhere instalado\n'
              '    (ex: C:\\Program Files\\SQL Anywhere 16\\Bin64)\n'
              '  - Adicione ao PATH do Windows:\n'
              '    * Pressione Win + X → "Sistema"\n'
              '    * Clique em "Configurações avançadas do sistema"\n'
              '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
              '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
              '    * Clique em "Novo" e adicione o caminho completo da pasta Bin64\n'
              '    * Clique em "OK" em todas as janelas\n\n'
              'Opção 2: SQL Anywhere não instalado?\n'
              '  - Baixe e instale SQL Anywhere (versões 11, 12, 16 ou 17)\n'
              '  - Durante a instalação, selecione "Add to PATH"\n\n'
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else {
          message =
              '$executable não encontrado no PATH do sistema.\n\n'
              'Verifique se a ferramenta está instalada e adicionada ao PATH.';
        }

        return rd.Failure(
          BackupFailure(
            message: message,
            originalError: Exception('$executable não encontrado no PATH'),
          ),
        );
      }

      if (executableDir != null) {
        final currentPath =
            mergedEnvironment['PATH'] ?? mergedEnvironment['Path'] ?? '';
        final pathList = currentPath.split(Platform.isWindows ? ';' : ':');
        final normalizedExecutableDir = executableDir
            .replaceAll(r'\', '/')
            .toLowerCase();
        final isInPath = pathList.any(
          (p) =>
              p.replaceAll(r'\', '/').toLowerCase() == normalizedExecutableDir,
        );

        if (!isInPath) {
          mergedEnvironment['PATH'] =
              '$executableDir${Platform.isWindows ? ';' : ':'}$currentPath';
          LoggerService.info(
            'Adicionado diretório do executável ao PATH do processo: $executableDir',
          );
        }
      }

      if (environment != null) {
        mergedEnvironment.addAll(environment);
      }

      final shouldUseShell = executablePath == null;

      final finalExecutable = executablePath ?? executable;
      var executableToUse = finalExecutable;
      if (shouldUseShell && finalExecutable.contains(' ')) {
        executableToUse = '"$finalExecutable"';
      }

      final process = await Process.start(
        executableToUse,
        arguments,
        workingDirectory: workingDirectory,
        environment: mergedEnvironment,
        runInShell: shouldUseShell,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      String? stdoutError;
      String? stderrError;

      final stdoutFuture = process.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (data) {
              try {
                stdoutBuffer.write(data);
                LoggerService.debug('STDOUT: $data');
              } on Object catch (e) {
                stdoutError = 'Erro ao processar stdout: $e';
                LoggerService.warning(stdoutError!);
              }
            },
            onError: (error) {
              stdoutError = 'Erro ao capturar stdout: $error';
              LoggerService.warning(stdoutError!);
            },
          )
          .asFuture();

      final stderrFuture = process.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(
            (data) {
              try {
                stderrBuffer.write(data);
                LoggerService.debug('STDERR: $data');
              } on Object catch (e) {
                stderrError = 'Erro ao processar stderr: $e';
                LoggerService.warning(stderrError!);
              }
            },
            onError: (error) {
              stderrError = 'Erro ao capturar stderr: $error';
              LoggerService.warning(stderrError!);
            },
          )
          .asFuture();

      int exitCode;
      if (timeout != null) {
        exitCode = await process.exitCode.timeout(
          timeout,
          onTimeout: () {
            process.kill();
            throw TimeoutException('Processo excedeu o timeout de $timeout');
          },
        );
      } else {
        exitCode = await process.exitCode;
      }

      try {
        await stdoutFuture;
      } on Object catch (e) {
        LoggerService.warning('Erro ao aguardar stdout: $e');
      }

      try {
        await stderrFuture;
      } on Object catch (e) {
        LoggerService.warning('Erro ao aguardar stderr: $e');
      }

      stopwatch.stop();

      final stdout = stdoutBuffer.toString();
      var stderr = stderrBuffer.toString();

      if (stdoutError != null) {
        stderr = '${stderr.isEmpty ? '' : '$stderr\n'}$stdoutError';
      }
      if (stderrError != null) {
        stderr = '${stderr.isEmpty ? '' : '$stderr\n'}$stderrError';
      }

      final result = ProcessResult(
        exitCode: exitCode,
        stdout: stdout,
        stderr: stderr,
        duration: stopwatch.elapsed,
      );

      LoggerService.info(
        'Processo finalizado - Exit Code: $exitCode - Duração: ${result.duration.inSeconds}s',
      );

      if (exitCode != 0) {
        return rd.Success(result);
      }

      return rd.Success(result);
    } on TimeoutException catch (e) {
      stopwatch.stop();
      LoggerService.error('Timeout ao executar processo', e);
      return rd.Failure(
        BackupFailure(
          message: 'Timeout ao executar $executable: ${e.message}',
          originalError: e,
        ),
      );
    } on Object catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao executar processo', e, stackTrace);

      final errorString = e.toString().toLowerCase();
      var message = 'Erro ao executar $executable: $e';

      if (errorString.contains('não é reconhecido') ||
          errorString.contains('não reconhecido') ||
          errorString.contains('command not found') ||
          errorString.contains('não encontrado') ||
          errorString.contains('não foi encontrado') ||
          errorString.contains('cmdlet') ||
          errorString.contains('programa operável')) {
        final executableLower = executable.toLowerCase();
        final isPostgresTool =
            executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');

        final isSqlCmdTool = executableLower.contains('sqlcmd');

        final isSybaseTool = executableLower.contains('dbisql') ||
            executableLower.contains('dbbackup') ||
            executableLower.contains('dbverify');

        if (isPostgresTool) {
          final toolName = executableLower.contains('pg_basebackup')
              ? 'pg_basebackup'
              : executableLower.contains('pg_verifybackup')
              ? 'pg_verifybackup'
              : executableLower.contains('pg_restore')
              ? 'pg_restore'
              : executableLower.contains('pg_dump')
              ? 'pg_dump'
              : 'psql';

          message =
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
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else if (isSqlCmdTool) {
          message =
              'sqlcmd não encontrado no PATH do sistema.\n\n'
              'O sqlcmd é uma ferramenta de linha de comando do SQL Server.\n\n'
              'OPÇÕES PARA RESOLVER:\n\n'
              'Opção 1: Instalar SQL Server Command Line Tools\n'
              '  - Baixe SQL Server Command Line Tools da Microsoft\n'
              '  - Durante a instalação, selecione "SQL Server Command Line Tools"\n'
              '  - O instalador configurará o PATH automaticamente\n\n'
              'Opção 2: Adicionar ao PATH manualmente\n'
              '  - Localize a pasta Tools\\Binn do SQL Server instalado\n'
              '    (ex: C:\\Program Files\\Microsoft SQL Server\\Client SDK\\ODBC\\170\\Tools\\Binn)\n'
              '  - Adicione ao PATH do Windows:\n'
              '    * Pressione Win + X → "Sistema"\n'
              '    * Clique em "Configurações avançadas do sistema"\n'
              '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
              '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
              '    * Clique em "Novo" e adicione o caminho completo da pasta\n'
              '    * Clique em "OK" em todas as janelas\n\n'
              'Opção 3: Usar SQL Server Management Studio (SSMS)\n'
              '  - SSMS inclui sqlcmd\n'
              '  - Localize sqlcmd.exe na pasta do SSMS\n'
              '  - Adicione a pasta ao PATH conforme Opção 2\n\n'
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else if (isSybaseTool) {
          final toolName = executableLower.contains('dbisql')
              ? 'dbisql'
              : executableLower.contains('dbbackup')
              ? 'dbbackup'
              : 'dbverify';

          message =
              '$toolName não encontrado no PATH do sistema.\n\n'
              'As ferramentas do Sybase SQL Anywhere não estão disponíveis.\n\n'
              'OPÇÕES PARA RESOLVER:\n\n'
              'Opção 1: Adicionar ao PATH manualmente\n'
              '  - Localize a pasta Bin64 do SQL Anywhere instalado\n'
              '    (ex: C:\\Program Files\\SQL Anywhere 16\\Bin64)\n'
              '  - Adicione ao PATH do Windows:\n'
              '    * Pressione Win + X → "Sistema"\n'
              '    * Clique em "Configurações avançadas do sistema"\n'
              '    * Na aba "Avançado", clique em "Variáveis de Ambiente"\n'
              '    * Em "Variáveis do sistema", encontre "Path" e clique em "Editar"\n'
              '    * Clique em "Novo" e adicione o caminho completo da pasta Bin64\n'
              '    * Clique em "OK" em todas as janelas\n\n'
              'Opção 2: SQL Anywhere não instalado?\n'
              '  - Baixe e instale SQL Anywhere (versões 11, 12, 16 ou 17)\n'
              '  - Durante a instalação, selecione "Add to PATH"\n\n'
              r'Consulte: docs\path_setup.md para mais detalhes.';
        } else {
          message =
              '$executable não encontrado no PATH do sistema.\n\n'
              'Verifique se a ferramenta está instalada e adicionada ao PATH.';
        }
      }

      return rd.Failure(
        BackupFailure(
          message: message,
          originalError: e,
        ),
      );
    }
  }
}
