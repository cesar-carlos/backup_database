import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:path/path.dart' as path;

import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';

class ProcessResult {
  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration duration;

  const ProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.duration,
  });

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

      // Mesclar variáveis de ambiente customizadas com o PATH do sistema
      final mergedEnvironment = <String, String>{};
      
      // Primeiro, copiar todas as variáveis de ambiente do sistema
      final systemEnv = Platform.environment;
      mergedEnvironment.addAll(systemEnv);
      
      // Tentar localizar o executável apenas no PATH do sistema/usuário usando 'where' (Windows) ou 'which' (Unix)
      String? executablePath;
      String? executableDir;
      bool executableFound = false;
      
      // Verificar se o executável é um caminho absoluto
      final isAbsolutePath = path.isAbsolute(executable);
      
      if (isAbsolutePath) {
        // Se for caminho absoluto, verificar diretamente se o arquivo existe
        final file = File(executable);
        if (file.existsSync()) {
          executablePath = executable;
          executableDir = path.dirname(executable);
          executableFound = true;
          LoggerService.info('Executável encontrado (caminho absoluto): $executablePath');
        } else {
          LoggerService.debug('Caminho absoluto fornecido mas arquivo não existe: $executable');
        }
      } else {
        // Se não for caminho absoluto, procurar no PATH
        try {
          if (Platform.isWindows) {
            // No Windows, usar 'cmd /c where' com runInShell: true para garantir que o PATH atualizado seja usado
            // Isso é importante porque Platform.environment pode não refletir mudanças recentes no PATH
            // runInShell: true faz o shell consultar o PATH do sistema em tempo de execução
            final whereResult = await Process.run(
              'cmd',
              ['/c', 'where', executable],
              runInShell: true, // Usar runInShell para consultar PATH do sistema em tempo de execução
            );
            
            if (whereResult.exitCode == 0 && whereResult.stdout.toString().trim().isNotEmpty) {
              final foundPath = whereResult.stdout.toString().trim().split('\n').first.trim();
              if (foundPath.isNotEmpty && File(foundPath).existsSync()) {
                executablePath = foundPath;
                executableDir = path.dirname(foundPath);
                executableFound = true;
                LoggerService.info('Executável encontrado via where no PATH: $executablePath');
              }
            } else {
              LoggerService.debug('where não encontrou $executable. Exit code: ${whereResult.exitCode}, stderr: ${whereResult.stderr}');
            }
          } else {
            // Unix/Linux/Mac
            final whereResult = await Process.run(
              'which',
              [executable],
              runInShell: false,
            );
            
            if (whereResult.exitCode == 0 && whereResult.stdout.toString().trim().isNotEmpty) {
              final foundPath = whereResult.stdout.toString().trim().split('\n').first.trim();
              if (foundPath.isNotEmpty && File(foundPath).existsSync()) {
                executablePath = foundPath;
                executableDir = path.dirname(foundPath);
                executableFound = true;
                LoggerService.info('Executável encontrado via which no PATH: $executablePath');
              }
            }
          }
        } catch (e) {
          LoggerService.debug('Erro ao usar where/which para encontrar $executable: $e');
        }
      }
      
      // Se não encontrou via where/which, tentar verificar diretamente em caminhos comuns do PostgreSQL
      if (!executableFound && Platform.isWindows) {
        final executableLower = executable.toLowerCase();
        final isPostgresTool = executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');
        
        if (isPostgresTool) {
          // Tentar caminhos comuns do PostgreSQL no Windows
          final commonPaths = [
            r'C:\Program Files\PostgreSQL\16\bin',
            r'C:\Program Files\PostgreSQL\15\bin',
            r'C:\Program Files\PostgreSQL\14\bin',
            r'C:\Program Files\PostgreSQL\13\bin',
            r'C:\Program Files (x86)\PostgreSQL\16\bin',
            r'C:\Program Files (x86)\PostgreSQL\15\bin',
            r'C:\Program Files (x86)\PostgreSQL\14\bin',
            r'C:\Program Files (x86)\PostgreSQL\13\bin',
          ];
          
          for (final basePath in commonPaths) {
            final potentialPath = path.join(basePath, executable);
            if (File(potentialPath).existsSync()) {
              executablePath = potentialPath;
              executableDir = basePath;
              executableFound = true;
              LoggerService.info('Executável encontrado em caminho comum: $executablePath');
              break;
            }
          }
        }
      }
      
      // Se não encontrou o executável, retornar erro imediatamente
      if (!executableFound) {
        // Verificar se é ferramenta do PostgreSQL para dar mensagem específica
        final executableLower = executable.toLowerCase();
        final isPostgresTool = executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');
        
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
              'Consulte: docs\\path_setup.md para mais detalhes.';
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
      
      // Se encontrou o executável no PATH, adicionar seu diretório ao PATH do processo se não estiver presente
      if (executableDir != null) {
        final currentPath = mergedEnvironment['PATH'] ?? mergedEnvironment['Path'] ?? '';
        final pathList = currentPath.split(Platform.isWindows ? ';' : ':');
        final normalizedExecutableDir = executableDir.replaceAll('\\', '/').toLowerCase();
        final isInPath = pathList.any((p) => 
            p.replaceAll('\\', '/').toLowerCase() == normalizedExecutableDir);
        
        if (!isInPath) {
          mergedEnvironment['PATH'] = '$executableDir${Platform.isWindows ? ';' : ':'}$currentPath';
          LoggerService.info('Adicionado diretório do executável ao PATH do processo: $executableDir');
        }
      }
      
      // Depois, sobrescrever/adicionar as variáveis customizadas
      if (environment != null) {
        mergedEnvironment.addAll(environment);
      }

      // Quando temos o caminho completo, não precisamos de runInShell: true
      // runInShell: true é necessário apenas quando queremos que o shell resolva via PATH
      // Mas quando temos o caminho completo, usar runInShell: false evita problemas com espaços
      final shouldUseShell = executablePath == null; // Usar shell apenas se não tivermos caminho completo
      
      // Se precisarmos usar shell e o caminho contém espaços, envolver em aspas duplas
      final finalExecutable = executablePath ?? executable;
      String executableToUse = finalExecutable;
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
              } catch (e) {
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
              } catch (e) {
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
      } catch (e) {
        LoggerService.warning('Erro ao aguardar stdout: $e');
      }

      try {
        await stderrFuture;
      } catch (e) {
        LoggerService.warning('Erro ao aguardar stderr: $e');
      }

      stopwatch.stop();

      String stdout = stdoutBuffer.toString();
      String stderr = stderrBuffer.toString();

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
    } catch (e, stackTrace) {
      stopwatch.stop();
      LoggerService.error('Erro ao executar processo', e, stackTrace);
      
      // Verificar se o erro é sobre executável não encontrado
      final errorString = e.toString().toLowerCase();
      String message = 'Erro ao executar $executable: $e';
      
      if (errorString.contains('não é reconhecido') ||
          errorString.contains("não reconhecido") ||
          errorString.contains('command not found') ||
          errorString.contains('não encontrado') ||
          errorString.contains('não foi encontrado') ||
          errorString.contains('cmdlet') ||
          errorString.contains('programa operável')) {
        // Se for ferramenta do PostgreSQL, dar mensagem específica
        final executableLower = executable.toLowerCase();
        final isPostgresTool = executableLower.contains('psql') ||
            executableLower.contains('pg_basebackup') ||
            executableLower.contains('pg_verifybackup') ||
            executableLower.contains('pg_restore') ||
            executableLower.contains('pg_dump');
        
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
              'Consulte: docs\\path_setup.md para mais detalhes.';
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
