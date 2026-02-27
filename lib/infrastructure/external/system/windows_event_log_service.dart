import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;

/// Catálogo de Event IDs para troubleshooting no Event Viewer.
///
/// IDs estáveis entre versões. Ranges:
/// - 1001-1999: Backups (sucesso/início)
/// - 2001-2999: Backups (falha)
/// - 3001-3099: Serviço Windows (lifecycle)
/// - 4001-4999: Saúde/verificações
/// - 5001-5999: Erros críticos
class WindowsServiceEventIds {
  WindowsServiceEventIds._();

  static const int installStarted = 3010;
  static const int installSucceeded = 3011;
  static const int installFailed = 3012;
  static const int startStarted = 3013;
  static const int startSucceeded = 3014;
  static const int startFailed = 3015;
  static const int startTimeout = 3016;
  static const int stopStarted = 3017;
  static const int stopSucceeded = 3018;
  static const int stopFailed = 3019;
  static const int stopTimeout = 3020;
  static const int uninstallStarted = 3021;
  static const int uninstallSucceeded = 3022;
  static const int uninstallFailed = 3023;
}

/// Níveis de evento para Windows Event Log.
enum EventLogEntryType {
  /// Informação
  information,

  /// Aviso
  warning,

  /// Erro
  error,
}

/// Serviço para escrever eventos no Windows Event Log.
///
/// Usa o comando `eventcreate` do Windows para registrar eventos
/// que podem ser visualizados no Event Viewer (eventvwr.msc).
///
/// Apenas Windows é suportado. Em outras plataformas, os eventos
/// são ignorados silenciosamente.
class WindowsEventLogService implements IWindowsServiceEventLogger {
  WindowsEventLogService({
    required ps.ProcessService processService,
    this.sourceName = 'BackupDatabase',
  }) : _processService = processService;

  final ps.ProcessService _processService;
  final String sourceName;

  bool isEnabled = true;
  bool _isAvailable = false;

  /// Inicializa o serviço verificando se eventcreate está disponível.
  ///
  /// Usa `eventcreate /?` para detectar disponibilidade sem criar nenhum
  /// evento real, evitando poluição no Event Viewer a cada inicialização.
  Future<void> initialize() async {
    if (!Platform.isWindows) {
      LoggerService.debug(
        'WindowsEventLogService: não é Windows, desabilitado',
      );
      _isAvailable = false;
      isEnabled = false;
      return;
    }

    try {
      // Verifica disponibilidade com '/?'. O exit code pode ser não-zero em
      // algumas versões do Windows, então consideramos disponível se o processo
      // for executado (independente do exit code).
      final result = await _processService.run(
        executable: 'eventcreate',
        arguments: ['/?'],
        timeout: const Duration(seconds: 5),
      );

      // Se o processo rodou (mesmo com exit code != 0), eventcreate existe.
      _isAvailable = result.fold(
        (processResult) => true,
        (_) => false,
      );

      if (_isAvailable) {
        LoggerService.info('✅ WindowsEventLogService inicializado');
      } else {
        LoggerService.warning(
          'WindowsEventLogService: eventcreate não disponível ou não encontrado',
        );
      }
    } on Object catch (e) {
      LoggerService.debug('WindowsEventLogService não disponível: $e');
      _isAvailable = false;
    }
  }

  /// Escreve um evento no Windows Event Log.
  ///
  /// [type] Tipo do evento (informação, aviso, erro)
  /// [eventId] ID do evento (número único para o tipo de evento)
  /// [message] Mensagem do evento
  ///
  /// Retorna `true` se o evento foi registrado com sucesso.
  Future<bool> writeEvent({
    required EventLogEntryType type,
    required int eventId,
    required String message,
  }) async {
    if (!isEnabled || !_isAvailable) {
      return false;
    }

    if (!Platform.isWindows) {
      return false;
    }

    try {
      final typeStr = switch (type) {
        EventLogEntryType.information => 'INFO',
        EventLogEntryType.warning => 'WARNING',
        EventLogEntryType.error => 'ERROR',
      };

      // Escapa aspas na mensagem
      final escapedMessage = message.replaceAll('"', '""');

      final result = await _processService.run(
        executable: 'eventcreate',
        arguments: [
          '/ID',
          '$eventId',
          '/T',
          typeStr,
          '/SO',
          sourceName,
          '/D',
          escapedMessage,
        ],
        timeout: const Duration(seconds: 5),
      );

      final success = result.isSuccess();
      if (!success) {
        result.fold(
          (processResult) {
            LoggerService.debug(
              'eventcreate falhou: ${processResult.stderr}',
            );
          },
          (failure) {
            LoggerService.debug(
              'eventcreate falhou: $failure',
            );
          },
        );
      }

      return success;
    } on Object catch (e) {
      LoggerService.debug('Erro ao escrever no Event Log: $e');
      return false;
    }
  }

  /// Escreve um evento de backup bem-sucedido.
  Future<void> logBackupSuccess({
    required String databaseName,
    required String backupType,
    required String backupPath,
    required int fileSizeBytes,
    required Duration duration,
  }) async {
    final message =
        'Backup concluído com sucesso\n'
        'Banco: $databaseName\n'
        'Tipo: $backupType\n'
        'Caminho: $backupPath\n'
        'Tamanho: ${_formatBytes(fileSizeBytes)}\n'
        'Duração: ${duration.inSeconds}s';

    await writeEvent(
      type: EventLogEntryType.information,
      eventId: 1001,
      message: message,
    );
  }

  /// Escreve um evento de backup falhado.
  Future<void> logBackupFailure({
    required String databaseName,
    required String backupType,
    required String errorMessage,
  }) async {
    final message =
        'Backup falhou\n'
        'Banco: $databaseName\n'
        'Tipo: $backupType\n'
        'Erro: $errorMessage';

    await writeEvent(
      type: EventLogEntryType.error,
      eventId: 2001,
      message: message,
    );
  }

  /// Escreve um evento de início de backup.
  Future<void> logBackupStarted({
    required String databaseName,
    required String backupType,
  }) async {
    final message =
        'Backup iniciado\n'
        'Banco: $databaseName\n'
        'Tipo: $backupType';

    await writeEvent(
      type: EventLogEntryType.information,
      eventId: 1002,
      message: message,
    );
  }

  /// Escreve um evento de serviço iniciado.
  Future<void> logServiceStarted() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: 3001,
      message: 'Serviço de backup iniciado',
    );
  }

  /// Escreve um evento de serviço parado.
  Future<void> logServiceStopped() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: 3002,
      message: 'Serviço de backup parado',
    );
  }

  /// Escreve um evento quando o shutdown ocorreu com backups em execução
  /// que não concluíram antes do timeout.
  Future<void> logShutdownBackupsIncomplete({
    required Duration timeout,
    String? details,
  }) async {
    final message = details != null
        ? 'Shutdown: backups não concluíram antes do timeout (${timeout.inSeconds}s).\n$details'
        : 'Shutdown: backups não concluíram antes do timeout (${timeout.inSeconds}s).';

    await writeEvent(
      type: EventLogEntryType.warning,
      eventId: 3003,
      message: message,
    );
  }

  @override
  Future<void> logInstallStarted() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.installStarted,
      message: 'Instalação do serviço iniciada',
    );
  }

  @override
  Future<void> logInstallSucceeded() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.installSucceeded,
      message: 'Serviço instalado com sucesso',
    );
  }

  @override
  Future<void> logInstallFailed({required String error}) async {
    await writeEvent(
      type: EventLogEntryType.error,
      eventId: WindowsServiceEventIds.installFailed,
      message: 'Falha na instalação do serviço: $error',
    );
  }

  @override
  Future<void> logStartStarted() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.startStarted,
      message: 'Início do serviço solicitado',
    );
  }

  @override
  Future<void> logStartSucceeded() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.startSucceeded,
      message: 'Serviço iniciado com sucesso',
    );
  }

  @override
  Future<void> logStartFailed({required String error}) async {
    await writeEvent(
      type: EventLogEntryType.error,
      eventId: WindowsServiceEventIds.startFailed,
      message: 'Falha ao iniciar serviço: $error',
    );
  }

  @override
  Future<void> logStartTimeout({required Duration timeout}) async {
    await writeEvent(
      type: EventLogEntryType.warning,
      eventId: WindowsServiceEventIds.startTimeout,
      message: 'Timeout ao iniciar serviço (${timeout.inSeconds}s)',
    );
  }

  @override
  Future<void> logStopStarted() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.stopStarted,
      message: 'Parada do serviço solicitada',
    );
  }

  @override
  Future<void> logStopSucceeded() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.stopSucceeded,
      message: 'Serviço parado com sucesso',
    );
  }

  @override
  Future<void> logStopFailed({required String error}) async {
    await writeEvent(
      type: EventLogEntryType.error,
      eventId: WindowsServiceEventIds.stopFailed,
      message: 'Falha ao parar serviço: $error',
    );
  }

  @override
  Future<void> logStopTimeout({required Duration timeout}) async {
    await writeEvent(
      type: EventLogEntryType.warning,
      eventId: WindowsServiceEventIds.stopTimeout,
      message: 'Timeout ao parar serviço (${timeout.inSeconds}s)',
    );
  }

  @override
  Future<void> logUninstallStarted() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.uninstallStarted,
      message: 'Remoção do serviço iniciada',
    );
  }

  @override
  Future<void> logUninstallSucceeded() async {
    await writeEvent(
      type: EventLogEntryType.information,
      eventId: WindowsServiceEventIds.uninstallSucceeded,
      message: 'Serviço removido com sucesso',
    );
  }

  @override
  Future<void> logUninstallFailed({required String error}) async {
    await writeEvent(
      type: EventLogEntryType.error,
      eventId: WindowsServiceEventIds.uninstallFailed,
      message: 'Falha ao remover serviço: $error',
    );
  }

  /// Escreve um evento de saúde do serviço.
  Future<void> logServiceHealth({
    required String status,
    String? details,
  }) async {
    final message = details != null
        ? 'Verificação de saúde: $status\n$details'
        : 'Verificação de saúde: $status';

    final type = status == 'healthy'
        ? EventLogEntryType.information
        : status == 'warning'
        ? EventLogEntryType.warning
        : EventLogEntryType.error;

    await writeEvent(
      type: type,
      eventId: 4001,
      message: message,
    );
  }

  /// Escreve um evento crítico do sistema.
  Future<void> logCriticalError({
    required String error,
    String? context,
  }) async {
    final message = context != null
        ? 'Erro crítico: $error\n\nContexto: $context'
        : 'Erro crítico: $error';

    await writeEvent(
      type: EventLogEntryType.error,
      eventId: 5001,
      message: message,
    );
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

  /// Verifica se o serviço está disponível.
  bool get isAvailable => _isAvailable;
}
