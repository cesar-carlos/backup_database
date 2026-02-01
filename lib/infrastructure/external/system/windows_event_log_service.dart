import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;

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
class WindowsEventLogService {
  WindowsEventLogService({
    required ps.ProcessService processService,
    this.sourceName = 'BackupDatabase',
  }) : _processService = processService;

  final ps.ProcessService _processService;
  final String sourceName;

  bool isEnabled = true;
  bool _isAvailable = false;

  /// Inicializa o serviço verificando se eventcreate está disponível.
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
      // Tenta executar eventcreate para verificar se está disponível
      final result = await _processService.run(
        executable: 'eventcreate',
        arguments: [
          '/ID',
          '1',
          '/T',
          'INFO',
          '/SO',
          sourceName,
          '/D',
          'Backup Database Event Log Service initialized',
        ],
        timeout: const Duration(seconds: 5),
      );

      _isAvailable = result.isSuccess();
      if (_isAvailable) {
        LoggerService.info('✅ WindowsEventLogService inicializado');
      } else {
        LoggerService.warning(
          'WindowsEventLogService: eventcreate não disponível',
        );
      }
    } on Object catch (e) {
      LoggerService.debug(
        'WindowsEventLogService não disponível: $e',
      );
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
