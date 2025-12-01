import 'dart:io';
import 'dart:convert';
import 'dart:async';

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

      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: true,
      );

      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();
      String? stdoutError;
      String? stderrError;

      // Capturar stdout com tratamento de erro de encoding
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
          ).asFuture();

      // Capturar stderr com tratamento de erro de encoding
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
          ).asFuture();

      // Aguardar conclusão com timeout
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

      // Aguardar captura de stdout/stderr
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

      // Combinar mensagens de erro se houver
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
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar $executable: $e',
          originalError: e,
        ),
      );
    }
  }
}
