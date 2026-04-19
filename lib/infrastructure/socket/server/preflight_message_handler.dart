import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show SendToClient;

/// Funcao injetavel que executa uma checagem de preflight e retorna
/// um [PreflightCheckResult]. Tudo que dispara excecao e tratado como
/// um check `blocking` falhado (fail-closed) — defesa em profundidade
/// contra checker que crashe.
typedef PreflightCheck = Future<PreflightCheckResult> Function();

/// Responde `preflightRequest` com snapshot agregado de prerequisites
/// para execucao remota de backup.
///
/// Implementa F1.8 do plano + parte de PR-1.
///
/// Os checks sao **injetados** para que o handler nao tenha
/// dependencias diretas dos servicos do servidor (ISP). Wirings em
/// producao podem injetar checks como:
/// - `compression_tool`: WinRAR/7-Zip disponivel no PATH
///   (`ToolVerificationService`)
/// - `temp_dir_writable`: pasta temporaria do servidor gravavel
///   (`validate_backup_directory`)
/// - `disk_space`: espaco livre suficiente para o maior schedule
///   conhecido (`StorageChecker`)
/// - `database_reachable`: ao menos um banco configurado responde
///   (`SybaseBackupService.testConnection` etc.)
///
/// Politica de agregacao:
/// - Qualquer check `blocking` falhou -> [PreflightStatus.blocked].
/// - Qualquer check `warning` falhou (sem blocking) ->
///   [PreflightStatus.passedWithWarnings].
/// - Caso contrario -> [PreflightStatus.passed].
class PreflightMessageHandler {
  PreflightMessageHandler({
    Map<String, PreflightCheck>? checks,
    DateTime Function()? clock,
  })  : _checks = checks ?? const <String, PreflightCheck>{},
        _clock = clock ?? DateTime.now;

  final Map<String, PreflightCheck> _checks;
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isPreflightRequestMessage(message)) return;

    final requestId = message.header.requestId;
    LoggerService.infoWithContext(
      'PreflightMessageHandler: respondendo preflight',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    try {
      final results = await _runAllChecks();
      final status = _aggregate(results);
      final summary = _summarize(results, status);

      await sendToClient(
        clientId,
        createPreflightResponseMessage(
          requestId: requestId,
          status: status,
          checks: results,
          serverTimeUtc: _clock(),
          message: summary,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'PreflightMessageHandler: falha ao executar preflight: $e',
        e,
        st,
      );
      // Mesmo em falha total, responde — cliente nao fica esperando.
      // Retorna `blocked` com check sintetico para diagnostico.
      await sendToClient(
        clientId,
        createPreflightResponseMessage(
          requestId: requestId,
          status: PreflightStatus.blocked,
          checks: [
            PreflightCheckResult(
              name: 'preflight_runner',
              passed: false,
              severity: PreflightSeverity.blocking,
              message: 'Preflight runner failed: $e',
            ),
          ],
          serverTimeUtc: _clock(),
          message: 'Preflight runner crashed',
        ),
      );
    }
  }

  Future<List<PreflightCheckResult>> _runAllChecks() async {
    final results = <PreflightCheckResult>[];
    for (final entry in _checks.entries) {
      results.add(await _runOne(entry.key, entry.value));
    }
    return results;
  }

  Future<PreflightCheckResult> _runOne(String name, PreflightCheck check) async {
    try {
      return await check();
    } on Object catch (e, st) {
      LoggerService.warning(
        'PreflightMessageHandler: check "$name" lancou excecao: $e',
        e,
        st,
      );
      // Fail-closed: excecao vira blocking failure.
      return PreflightCheckResult(
        name: name,
        passed: false,
        severity: PreflightSeverity.blocking,
        message: 'Check raised exception: $e',
      );
    }
  }

  PreflightStatus _aggregate(List<PreflightCheckResult> results) {
    var hasBlockingFailure = false;
    var hasWarningFailure = false;
    for (final r in results) {
      if (r.passed) continue;
      switch (r.severity) {
        case PreflightSeverity.blocking:
          hasBlockingFailure = true;
        case PreflightSeverity.warning:
          hasWarningFailure = true;
        case PreflightSeverity.info:
          // info nunca bloqueia nem alerta
          break;
      }
    }
    if (hasBlockingFailure) return PreflightStatus.blocked;
    if (hasWarningFailure) return PreflightStatus.passedWithWarnings;
    return PreflightStatus.passed;
  }

  String? _summarize(
    List<PreflightCheckResult> results,
    PreflightStatus status,
  ) {
    final failed = results.where((r) => !r.passed).toList();
    if (failed.isEmpty) return null;
    final names = failed.map((r) => r.name).join(', ');
    switch (status) {
      case PreflightStatus.blocked:
        return 'Bloqueado: $names';
      case PreflightStatus.passedWithWarnings:
        return 'Avisos: $names';
      case PreflightStatus.passed:
        return null;
    }
  }
}
