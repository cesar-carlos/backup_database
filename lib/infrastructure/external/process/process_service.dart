import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
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
  static const Duration _executableCacheTtl = Duration(minutes: 10);

  /// Limite máximo de bytes capturados por stream (stdout/stderr) por
  /// execução. Backups longos (`pg_basebackup -P`, `sqlcmd STATS=10`) podem
  /// produzir muitos megabytes de progresso; manter tudo em memória pode
  /// causar OOM. Acima do limite, descartamos os bytes mais antigos
  /// preservando a parte final, que é onde mensagens de erro tendem a
  /// aparecer.
  static const int _maxOutputBytes = 5 * 1024 * 1024; // 5 MB

  final Map<String, _ExecutableCacheEntry> _executablePathCache = {};
  final Map<String, Process> _runningProcesses = {};

  static const _sensitiveEnvVars = {
    'SQLCMDPASSWORD',
    'PGPASSWORD',
    'DBPASSWORD',
  };

  static String _redactSensitiveInArg(String arg) {
    if (arg.contains(RegExp('PWD=', caseSensitive: false))) {
      return arg.replaceAll(
        RegExp('PWD=[^;]*', caseSensitive: false),
        'PWD=***REDACTED***',
      );
    }
    return arg;
  }

  static String redactCommandForLogging(
    String executable,
    List<String> arguments,
  ) {
    final redactedArgs = <String>[];
    for (var i = 0; i < arguments.length; i++) {
      final arg = arguments[i];
      if (arg == '-P' && i + 1 < arguments.length) {
        redactedArgs.add('-P');
        redactedArgs.add('***REDACTED***');
        i++;
      } else {
        redactedArgs.add(_redactSensitiveInArg(arg));
      }
    }
    return '$executable ${redactedArgs.join(' ')}';
  }

  String _redactCommand(String executable, List<String> arguments) =>
      redactCommandForLogging(executable, arguments);

  static String redactEnvForLogging(Map<String, String>? environment) {
    if (environment == null || environment.isEmpty) return '';

    final redactedEntries = <String>[];
    for (final entry in environment.entries) {
      if (_sensitiveEnvVars.contains(entry.key.toUpperCase())) {
        redactedEntries.add('${entry.key}=***REDACTED***');
      }
    }
    return redactedEntries.isNotEmpty ? ' ${redactedEntries.join(' ')}' : '';
  }

  String _redactEnv(Map<String, String>? environment) =>
      redactEnvForLogging(environment);

  Future<rd.Result<ProcessResult>> run({
    required String executable,
    required List<String> arguments,
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    String? tag,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final redactedCommand = _redactCommand(executable, arguments);
      final redactedEnv = _redactEnv(environment);
      LoggerService.info('Executando: $redactedCommand$redactedEnv');

      final mergedEnvironment = <String, String>{};

      final systemEnv = Platform.environment;
      mergedEnvironment.addAll(systemEnv);

      String? executablePath;
      String? executableDir;
      var executableFound = false;
      final cacheKey = executable.toLowerCase();

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
        final cachedEntry = _executablePathCache[cacheKey];
        if (cachedEntry != null) {
          final isExpired =
              DateTime.now().difference(cachedEntry.cachedAt) >
              _executableCacheTtl;
          if (!isExpired && File(cachedEntry.path).existsSync()) {
            executablePath = cachedEntry.path;
            executableDir = path.dirname(cachedEntry.path);
            executableFound = true;
            LoggerService.debug(
              'Executavel encontrado em cache: $executablePath',
            );
          } else {
            _executablePathCache.remove(cacheKey);
          }
        }

        try {
          if (!executableFound && Platform.isWindows) {
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
          } else if (!executableFound) {
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
            executableLower.contains('pg_dump') ||
            executableLower.contains('pg_receivewal');

        final isSqlCmdTool = executableLower.contains('sqlcmd');

        final isSybaseTool =
            executableLower.contains('dbisql') ||
            executableLower.contains('dbbackup') ||
            executableLower.contains('dbverify') ||
            executableLower.contains('dbvalid');

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

      if (!isAbsolutePath && executableFound && executablePath != null) {
        _executablePathCache[cacheKey] = _ExecutableCacheEntry(
          path: executablePath,
          cachedAt: DateTime.now(),
        );
      }

      if (!executableFound) {
        _executablePathCache.remove(cacheKey);
        return rd.Failure(
          BackupFailure(
            message: ToolPathHelp.buildMessage(executable),
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

      if (tag != null && tag.isNotEmpty) {
        _runningProcesses[tag] = process;
      }

      final stdoutBuffer = _BoundedByteBuffer(_maxOutputBytes);
      final stderrBuffer = _BoundedByteBuffer(_maxOutputBytes);
      String? stdoutError;
      String? stderrError;

      final stdoutFuture = process.stdout
          .listen(
            (chunk) {
              try {
                stdoutBuffer.add(chunk);
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
          .listen(
            (chunk) {
              try {
                stderrBuffer.add(chunk);
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

      if (tag != null && tag.isNotEmpty) {
        _runningProcesses.remove(tag);
      }

      final stdout = _decorateTruncated(
        _decodeProcessOutput(stdoutBuffer.takeBytes()),
        truncated: stdoutBuffer.wasTruncated,
        droppedBytes: stdoutBuffer.droppedBytes,
        streamName: 'stdout',
      );
      var stderr = _decorateTruncated(
        _decodeProcessOutput(stderrBuffer.takeBytes()),
        truncated: stderrBuffer.wasTruncated,
        droppedBytes: stderrBuffer.droppedBytes,
        streamName: 'stderr',
      );

      if (stdoutError != null) {
        stderr = '${stderr.isEmpty ? '' : '$stderr\n'}$stdoutError';
      }
      if (stderrError != null) {
        stderr = '${stderr.isEmpty ? '' : '$stderr\n'}$stderrError';
      }

      if (stdout.isNotEmpty) {
        LoggerService.debug('STDOUT: $stdout');
      }
      if (stderr.isNotEmpty) {
        LoggerService.debug('STDERR: $stderr');
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
        _executablePathCache.remove(executable.toLowerCase());
        message = ToolPathHelp.buildMessage(executable);
      }

      return rd.Failure(
        BackupFailure(
          message: message,
          originalError: e,
        ),
      );
    }
  }

  void cancelByTag(String tag) {
    final process = _runningProcesses[tag];
    if (process != null) {
      LoggerService.info('Cancelando processo com tag: $tag');
      process.kill();
      _runningProcesses.remove(tag);
    }
  }

  /// Cancela todos os processos rastreados (qualquer tag). Usado pelo
  /// shutdown da aplicação para impedir que processos do SGBD fiquem
  /// órfãos depois que a UI fecha. Itera sobre cópia das chaves para
  /// não modificar o map enquanto percorre.
  int cancelAllRunning() {
    if (_runningProcesses.isEmpty) return 0;
    final tags = List<String>.from(_runningProcesses.keys);
    LoggerService.info(
      'Cancelando ${tags.length} processo(s) em execução: $tags',
    );
    var cancelled = 0;
    for (final tag in tags) {
      final process = _runningProcesses.remove(tag);
      if (process != null) {
        try {
          process.kill();
          cancelled++;
        } on Object catch (e) {
          LoggerService.warning(
            'Falha ao matar processo com tag $tag: $e',
          );
        }
      }
    }
    return cancelled;
  }

  String _decodeProcessOutput(List<int> bytes) {
    if (bytes.isEmpty) {
      return '';
    }

    final utf8Text = utf8.decode(bytes, allowMalformed: true);
    final utf8Score = _decodeQualityScore(utf8Text);

    if (!Platform.isWindows) {
      return utf8Text;
    }

    final systemText = _decodeWithSystemEncoding(bytes);
    final systemScore = _decodeQualityScore(systemText);

    return systemScore < utf8Score ? systemText : utf8Text;
  }

  String _decodeWithSystemEncoding(List<int> bytes) {
    try {
      return systemEncoding.decode(bytes);
    } on Object {
      return utf8.decode(bytes, allowMalformed: true);
    }
  }

  int _decodeQualityScore(String text) {
    const replacementCodePoint = 0xFFFD;
    const garbledMarker = 'Ã';
    var score = 0;
    for (final codePoint in text.runes) {
      if (codePoint == replacementCodePoint) {
        score += 2;
      }
    }
    return score + garbledMarker.allMatches(text).length;
  }

  /// Acrescenta um cabeçalho informando truncamento quando o buffer
  /// descartou bytes. Mantém os usuários cientes de que parte do output
  /// não está disponível, e reduz risco de diagnósticos enganosos quando
  /// stdout/stderr foram cortados.
  String _decorateTruncated(
    String text, {
    required bool truncated,
    required int droppedBytes,
    required String streamName,
  }) {
    if (!truncated) return text;
    final droppedKb = (droppedBytes / 1024).toStringAsFixed(0);
    return '[Aviso: $streamName foi truncado; '
        '$droppedKb KB iniciais descartados '
        '(limite ${(_maxOutputBytes / 1024 / 1024).toStringAsFixed(0)} MB).]\n'
        '$text';
  }
}

/// Buffer com janela rolante de bytes. Mantém no máximo [maxBytes] em
/// memória, descartando os bytes mais antigos quando excedido. Usado para
/// proteger contra OOM em comandos de longa duração com muito output
/// (ex.: `pg_basebackup -P`, `sqlcmd STATS=10`).
class _BoundedByteBuffer {
  _BoundedByteBuffer(this.maxBytes);

  final int maxBytes;
  final List<int> _bytes = <int>[];
  int _droppedBytes = 0;

  bool get wasTruncated => _droppedBytes > 0;
  int get droppedBytes => _droppedBytes;

  void add(List<int> chunk) {
    _bytes.addAll(chunk);
    if (_bytes.length > maxBytes) {
      final overflow = _bytes.length - maxBytes;
      _bytes.removeRange(0, overflow);
      _droppedBytes += overflow;
    }
  }

  List<int> takeBytes() => List<int>.unmodifiable(_bytes);
}

class _ExecutableCacheEntry {
  const _ExecutableCacheEntry({
    required this.path,
    required this.cachedAt,
  });

  final String path;
  final DateTime cachedAt;
}
