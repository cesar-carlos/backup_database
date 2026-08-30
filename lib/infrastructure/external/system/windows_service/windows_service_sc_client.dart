import 'dart:async';

import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_timing_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

class WindowsServiceScClient {
  WindowsServiceScClient({
    required this._processService,
    WindowsServiceTimingConfig? timing,
    IMetricsCollector? metricsCollector,
  }) : _timing = timing ?? WindowsServiceTimingConfig.defaultConfig,
       _metrics = metricsCollector;

  final ProcessService _processService;
  final WindowsServiceTimingConfig _timing;
  final IMetricsCollector? _metrics;

  static const String _scExeName = 'sc';
  static const String _runningState = 'RUNNING';
  static const String _runningStatePt = 'EM EXECUÇÃO';
  static const String _runningStatePtNoAccent = 'EM EXECUCAO';
  static const int _serviceNotInstalledWinError = 1060;
  static const int _serviceNotInstalledBatchError = 36;
  static const int _accessDeniedWinError = 5;
  static const int _serviceAlreadyRunningWinError = 1056;

  static final RegExp _runningStateRegex = RegExp(
    r'(?:STATE|ESTADO)\s*:\s*4\b',
    caseSensitive: false,
  );
  static final RegExp _stateCodeRegex = RegExp(
    r'(?:STATE|ESTADO)\s*:\s*(\d+)',
    caseSensitive: false,
  );

  static const Set<String> _retryableFailureCodes = {
    'TIMEOUT',
    'PROCESS_TIMEOUT',
    'SCM_BUSY',
  };

  Future<rd.Result<ProcessResult>> run({
    required List<String> arguments,
    required Duration timeout,
  }) {
    return _processService.run(
      executable: _scExeName,
      arguments: arguments,
      timeout: timeout,
    );
  }

  Future<rd.Result<ProcessResult>> runWithRetry({
    required List<String> arguments,
    required Duration timeout,
    String operationName = 'sc',
  }) async {
    var attempt = 0;
    var delay = _timing.retryInitialDelay;
    rd.Result<ProcessResult>? lastResult;

    while (true) {
      attempt++;
      lastResult = await run(
        arguments: arguments,
        timeout: timeout,
      );

      if (lastResult.isSuccess()) {
        return lastResult;
      }

      final failure = lastResult.exceptionOrNull()!;
      final isLastAttempt = attempt >= _timing.retryMaxAttempts;
      final canRetry = _isRetryableProcessFailure(failure);

      LoggerService.warning(
        '$operationName falhou (tentativa $attempt/'
        '${_timing.retryMaxAttempts}): $failure',
        failure,
      );

      if (isLastAttempt || !canRetry) {
        return lastResult;
      }

      _metrics?.incrementCounter(ObservabilityMetrics.windowsServiceScRetries);

      LoggerService.info(
        'Retentando $operationName em ${delay.inMilliseconds}ms '
        '(tentativa ${attempt + 1}/${_timing.retryMaxAttempts})',
      );
      await Future.delayed(delay);
      delay = Duration(
        milliseconds: delay.inMilliseconds * _timing.retryBackoffMultiplier,
      );
    }
  }

  /// Classifica falhas retrátaveis vs permanentes.
  ///
  /// S10 da auditoria: antes confiávamos puramente em `failure.toString()`
  /// contendo strings como "timeout"/"scm"/"busy". Isso era frágil porque:
  /// - `TimeoutException.toString()` em alguns formats de locale não
  ///   começa com "timeout" lowercase;
  /// - `Failure(code: 'TIMEOUT')` é a forma canônica do projeto e
  ///   merece check explícito por tipo + code.
  ///
  /// A nova lógica:
  /// 1. `TimeoutException` direto: sempre retentar.
  /// 2. `Failure` com `code` em `_retryableFailureCodes`: retentar.
  /// 3. Fallback: string-match preservado para erros opacos do
  ///    `Process.run` que não foram embrulhados em `Failure`.
  bool _isRetryableProcessFailure(Object failure) {
    if (failure is TimeoutException) return true;
    if (failure is Failure && _retryableFailureCodes.contains(failure.code)) {
      return true;
    }
    final msg = failure.toString().toLowerCase();
    return msg.contains('timeout') ||
        msg.contains('timed out') ||
        msg.contains('scm') ||
        msg.contains('service control manager') ||
        msg.contains('busy') ||
        msg.contains('temporarily');
  }

  /// Verifica se a saída do sc query indica estado RUNNING.
  /// Suporta locale EN (RUNNING) e PT-BR (EM EXECUÇÃO), além do código 4.
  bool isRunningState(String stdout) {
    final upper = stdout.toUpperCase();
    return upper.contains(_runningState) ||
        upper.contains(_runningStatePt.toUpperCase()) ||
        upper.contains(_runningStatePtNoAccent) ||
        _runningStateRegex.hasMatch(stdout);
  }

  WindowsServiceStateCode? parseStateCode(String stdout) {
    final match = _stateCodeRegex.firstMatch(stdout);
    if (match == null) return null;
    final code = int.tryParse(match.group(1) ?? '');
    return code != null ? WindowsServiceStateCode.fromCode(code) : null;
  }

  bool isServiceNotInstalledResponse(ProcessResult processResult) {
    if (processResult.exitCode == _serviceNotInstalledWinError ||
        processResult.exitCode == _serviceNotInstalledBatchError) {
      return true;
    }

    final output = getProcessOutput(processResult).toLowerCase();
    return output.contains('1060') ||
        output.contains('does not exist as an installed service') ||
        output.contains('specified service does not exist') ||
        output.contains('nao existe como servico instalado') ||
        output.contains('não existe como serviço instalado');
  }

  bool isAccessDeniedResponse(ProcessResult processResult) {
    if (processResult.exitCode == _accessDeniedWinError) {
      return true;
    }
    return textContainsAccessDenied(getProcessOutput(processResult));
  }

  /// Detector case-insensitive de "access denied" em mensagens do `sc.exe`,
  /// `nssm.exe` e `taskkill` (PT-BR + EN).
  ///
  /// Consolida ~4 cadeias inline duplicadas (`errorMessage.contains('Acesso
  /// negado') || errorMessage.contains('Access denied') ||
  /// errorMessage.contains('FALHA 5') || errorMessage.contains('FAILURE 5')`)
  /// em `_install`, `_configure`, `_uninstall` e `_stopService`. Também é a
  /// primitiva usada por `isAccessDeniedResponse` (que mantém o
  /// short-circuit pelo `exitCode == _accessDeniedWinError`).
  ///
  /// **Histórico (S13 da auditoria)**: este helper antes excluía a variante
  /// `"access is denied"` (com "is"), que ficava como check in-line apenas
  /// no `_startService`. Algumas builds do `sc.exe` imprimem essa variação,
  /// e a assimetria foi mantida quando o helper foi extraído para preservar
  /// backwards-compat com os outros caminhos. Após validação de testes
  /// (todos os existentes seguem passando com a inclusão), agora cobrimos
  /// todas as variantes em um único lugar — eliminando o foot-gun para
  /// próximos refactors.
  bool textContainsAccessDenied(String text) {
    final lower = text.toLowerCase();
    return lower.contains('acesso negado') ||
        lower.contains('access denied') ||
        lower.contains('access is denied') ||
        lower.contains('falha 5') ||
        lower.contains('failure 5');
  }

  bool isServiceAlreadyRunningResponse(
    ProcessResult processResult,
    String output,
  ) {
    if (processResult.exitCode == _serviceAlreadyRunningWinError) {
      return true;
    }

    final normalizedOutput = output.toLowerCase();
    return normalizedOutput.contains('1056') ||
        normalizedOutput.contains('already running') ||
        normalizedOutput.contains('já está em execução') ||
        normalizedOutput.contains('ja esta em execucao') ||
        normalizedOutput.contains('uma copia deste serv') ||
        normalizedOutput.contains('uma cópia deste serv');
  }

  String getProcessOutput(ProcessResult processResult) {
    final stderr = processResult.stderr.trim();
    final stdout = processResult.stdout.trim();
    if (stderr.isNotEmpty && stdout.isNotEmpty) {
      return '$stderr | $stdout';
    }
    if (stderr.isNotEmpty) {
      return stderr;
    }
    if (stdout.isNotEmpty) {
      return stdout;
    }
    return 'sem saída';
  }
}
