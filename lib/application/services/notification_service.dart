import 'dart:io';

import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/core/constants/observability_metrics.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:backup_database/domain/repositories/i_email_test_audit_repository.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_license_validation_service.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class NotificationService implements INotificationService {
  NotificationService({
    required IEmailConfigRepository emailConfigRepository,
    required IEmailNotificationTargetRepository
    emailNotificationTargetRepository,
    required IEmailTestAuditRepository emailTestAuditRepository,
    required IBackupLogRepository backupLogRepository,
    required IEmailService emailService,
    required ILicenseValidationService licenseValidationService,
    IMetricsCollector? metricsCollector,
  }) : _emailConfigRepository = emailConfigRepository,
       _emailNotificationTargetRepository = emailNotificationTargetRepository,
       _emailTestAuditRepository = emailTestAuditRepository,
       _backupLogRepository = backupLogRepository,
       _emailService = emailService,
       _licenseValidationService = licenseValidationService,
       _metricsCollector = metricsCollector;

  final IEmailConfigRepository _emailConfigRepository;
  final IEmailNotificationTargetRepository _emailNotificationTargetRepository;
  final IEmailTestAuditRepository _emailTestAuditRepository;
  final IBackupLogRepository _backupLogRepository;
  final IEmailService _emailService;
  final ILicenseValidationService _licenseValidationService;
  final IMetricsCollector? _metricsCollector;
  static const int _maxParallelRecipientSends = 4;
  /// Máximo de configurações de e-mail processadas em paralelo. Cada
  /// config faz auth + envio SMTP — paralelizar reduz tempo total
  /// quando há 2+ configs (ex.: corporativa + auditoria).
  static const int _maxParallelConfigs = 3;

  @override
  Future<rd.Result<bool>> notifyBackupComplete(
    BackupHistory history,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Success(false);
    }

    final configResult = await _emailConfigRepository.getAll();
    return configResult.fold(
      (configs) => _sendHistoryWithConfigs(configs, history),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> sendWarning({
    required String databaseName,
    required String message,
  }) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Success(false);
    }

    final configResult = await _emailConfigRepository.getAll();
    return configResult.fold(
      (configs) => _sendWarningWithConfigs(configs, databaseName, message),
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> testEmailConfiguration(
    EmailConfig config,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Notificação por e-mail requer licença válida com permissão.',
        ),
      );
    }

    final correlationId = _buildTestCorrelationId(config.id);
    final destinationRecipient = config.recipients
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .firstOrNull;
    if (destinationRecipient == null || !destinationRecipient.contains('@')) {
      const failure = ValidationFailure(
        message:
            'Informe um e-mail de destino válido para testar a configuração',
      );
      await _saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: '',
        senderEmail: config.fromEmail.trim().isNotEmpty
            ? config.fromEmail.trim()
            : config.username.trim(),
        failure: failure,
      );
      return const rd.Failure(failure);
    }

    final senderEmail = config.fromEmail.trim().isNotEmpty
        ? config.fromEmail.trim()
        : config.username.trim();
    if (senderEmail.isEmpty || !senderEmail.contains('@')) {
      const failure = ValidationFailure(
        message:
            'Informe um e-mail SMTP válido para realizar o teste de conexão',
      );
      await _saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: destinationRecipient,
        senderEmail: senderEmail,
        failure: failure,
      );
      return const rd.Failure(failure);
    }

    LoggerService.info(
      '[NotificationService] Iniciando teste SMTP | '
      'correlationId=$correlationId '
      'configId=${config.id} '
      'server=${config.smtpServer}:${config.smtpPort} '
      'to=$destinationRecipient',
    );

    final subject = '[SMTP-TEST:$correlationId] ${config.configName}';
    final body =
        '''
Esta é uma mensagem de teste da configuração SMTP do Backup Database.

Objetivo:
- Validar servidor, credenciais e entrega para o destinatario configurado.

Configuração testada:
- Nome: ${config.configName}
- Servidor SMTP: ${config.smtpServer}
- Porta: ${config.smtpPort}
- Usuário SMTP: ${config.username}
- Destinatario de teste: $destinationRecipient
- Correlation ID: $correlationId

Se você recebeu este e-mail, a configuração está funcionando corretamente.

Data/Hora do teste: ${DateTime.now()}
''';

    final sendResult = await _emailService.sendEmail(
      config: config.copyWith(
        recipients: [destinationRecipient],
        fromEmail: senderEmail,
      ),
      subject: subject,
      body: body,
    );

    sendResult.fold(
      (_) async {
        LoggerService.info(
          '[NotificationService] Teste SMTP aceito | '
          'correlationId=$correlationId '
          'to=$destinationRecipient',
        );
        await _saveEmailTestAudit(
          config: config,
          correlationId: correlationId,
          recipientEmail: destinationRecipient,
          senderEmail: senderEmail,
        );
      },
      (failure) async {
        LoggerService.warning(
          '[NotificationService] Teste SMTP falhou | '
          'correlationId=$correlationId '
          'to=$destinationRecipient '
          'erro=$failure',
        );
        await _saveEmailTestAudit(
          config: config,
          correlationId: correlationId,
          recipientEmail: destinationRecipient,
          senderEmail: senderEmail,
          failure: failure,
        );
      },
    );

    return sendResult;
  }

  @override
  Future<rd.Result<void>> sendTestEmail(
    String recipient,
    String subject,
  ) async {
    final isAllowed = await _isEmailNotificationAllowed();
    if (!isAllowed) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Notificação por e-mail requer licença válida com permissão.',
        ),
      );
    }

    final configResult = await _emailConfigRepository.get();

    return configResult.fold(
      (config) async {
        final body =
            '''
Este e um e-mail de teste do Sistema de Backup.

Data/Hora do teste: ${DateTime.now()}
''';

        final result = await _emailService.sendEmail(
          config: config.copyWith(recipients: [recipient]),
          subject: subject,
          body: body,
        );

        return result.fold(
          (success) => const rd.Success(()),
          rd.Failure.new,
        );
      },
      rd.Failure.new,
    );
  }

  Future<bool> _isEmailNotificationAllowed() async {
    try {
      final hasEmailNotification = await _licenseValidationService
          .isFeatureAllowed(LicenseFeatures.emailNotification);

      final allowed = hasEmailNotification.getOrElse((_) => false);
      if (!allowed) {
        _metricsCollector?.incrementCounter(
          ObservabilityMetrics.emailNotificationSkippedLicenseTotal,
        );
        LoggerService.info(
          'Notificação por email bloqueada - licença não possui permissão',
        );
      }
      return allowed;
    } on Object catch (e) {
      LoggerService.warning('Erro ao verificar licença para notificação: $e');
      return false;
    }
  }

  Future<rd.Result<bool>> _sendHistoryWithConfigs(
    List<EmailConfig> configs,
    BackupHistory history,
  ) {
    return _sendToConfigs(
      configs: configs,
      eventType: _eventTypeFor(history.status),
      processConfig: (config) async {
        // Cada config faz seu próprio export de log para garantir
        // isolamento (e cleanup independente). Configs em paralelo
        // não compartilham o mesmo arquivo temp.
        final logPath = config.attachLog
            ? await _exportLogsForBackup(history.id)
            : null;
        try {
          final targetResult = await _emailNotificationTargetRepository
              .getByConfigId(config.id);
          if (targetResult.isError()) {
            return _ConfigSendOutcome.failure(
              targetResult.exceptionOrNull() ??
                  Exception('Falha ao carregar destinatarios'),
            );
          }
          final targets = targetResult.getOrElse((_) => const []);
          if (targets.isEmpty) {
            LoggerService.info(
              'Configuracao ${config.id} sem destinatarios ativos '
              'para envio.',
            );
            return _ConfigSendOutcome.empty();
          }
          final summary = await _sendHistoryToTargets(
            config,
            targets,
            history,
            logPath,
          );
          return _ConfigSendOutcome.fromSummary(summary);
        } finally {
          await _cleanupTempLog(logPath);
        }
      },
    );
  }

  /// Apaga o diretório temporário criado por [_exportLogsForBackup].
  /// Best-effort — falhas de I/O são logadas em debug.
  Future<void> _cleanupTempLog(String? logPath) async {
    if (logPath == null) return;
    try {
      final file = File(logPath);
      final parent = file.parent;
      if (await file.exists()) {
        await file.delete();
      }
      if (await parent.exists() &&
          parent.path.contains('backup_logs_') &&
          (await parent.list().isEmpty)) {
        await parent.delete();
      }
    } on Object catch (e) {
      LoggerService.debug(
        '[NotificationService] Falha ao limpar log temporário '
        '$logPath: $e',
      );
    }
  }

  Future<rd.Result<bool>> _sendWarningWithConfigs(
    List<EmailConfig> configs,
    String databaseName,
    String message,
  ) {
    return _sendToConfigs(
      configs: configs,
      eventType: 'backup_warning',
      processConfig: (config) async {
        final targetResult = await _emailNotificationTargetRepository
            .getByConfigId(config.id);
        if (targetResult.isError()) {
          return _ConfigSendOutcome.failure(
            targetResult.exceptionOrNull() ??
                Exception('Falha ao carregar destinatarios'),
          );
        }
        final targets = targetResult.getOrElse((_) => const []);
        if (targets.isEmpty) {
          LoggerService.info(
            'Configuracao ${config.id} sem destinatarios ativos '
            'para envio de aviso.',
          );
          return _ConfigSendOutcome.empty();
        }
        final summary = await _sendWarningToTargets(
          config,
          targets,
          databaseName,
          message,
        );
        return _ConfigSendOutcome.fromSummary(summary);
      },
    );
  }

  /// Helper genérico que executa `processConfig` para todas as
  /// configurações habilitadas em **paralelo** (até
  /// `_maxParallelConfigs` simultâneas) e agrega o resultado.
  /// Substitui as duas implementações praticamente idênticas que
  /// existiam para `_sendHistoryWithConfigs` e `_sendWarningWithConfigs`,
  /// eliminando ~120 linhas duplicadas e o "dead code" do `fold` que
  /// reaplicava o `sentAny=true` já contabilizado pelo `summary`.
  Future<rd.Result<bool>> _sendToConfigs({
    required List<EmailConfig> configs,
    required String eventType,
    required Future<_ConfigSendOutcome> Function(EmailConfig config)
    processConfig,
  }) async {
    final enabled = configs.where((cfg) => cfg.enabled).toList();
    if (enabled.isEmpty) {
      return const rd.Success(false);
    }

    final outcomes = await _runInBatches<EmailConfig, _ConfigSendOutcome>(
      enabled,
      _maxParallelConfigs,
      (config) async {
        final outcome = await processConfig(config);
        // Loga o resumo da config — antes era inline em cada caminho.
        if (outcome.summary != null) {
          _logDeliverySummary(
            configId: config.id,
            eventType: eventType,
            summary: outcome.summary!,
          );
        } else if (outcome.failure != null) {
          LoggerService.warning(
            'Falha ao processar configuracao ${config.id}: '
            '${outcome.failure}',
          );
        }
        return outcome;
      },
    );

    var sentAny = false;
    Exception? firstFailure;
    for (final outcome in outcomes) {
      if (outcome.sent) sentAny = true;
      if (outcome.failure != null) {
        firstFailure ??= _toException(outcome.failure!);
      }
    }

    if (sentAny) return const rd.Success(true);
    if (firstFailure != null) return rd.Failure(firstFailure);
    return const rd.Success(false);
  }

  Future<_DeliverySendSummary> _sendHistoryToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    BackupHistory history,
    String? logPath,
  ) async {
    final enabledTargets = targets.where((target) => target.enabled).toList();
    final results =
        await _runInBatches<EmailNotificationTarget, _RecipientDeliveryResult>(
          enabledTargets,
          _maxParallelRecipientSends,
          (target) => _sendHistoryToTarget(
            config,
            target,
            history,
            logPath,
          ),
        );
    return _summarizeDeliveryResults(results);
  }

  Future<_DeliverySendSummary> _sendWarningToTargets(
    EmailConfig config,
    List<EmailNotificationTarget> targets,
    String databaseName,
    String warningMessage,
  ) async {
    final enabledTargets = targets.where((target) => target.enabled).toList();
    final results =
        await _runInBatches<EmailNotificationTarget, _RecipientDeliveryResult>(
          enabledTargets,
          _maxParallelRecipientSends,
          (target) => _sendWarningToTarget(
            config: config,
            target: target,
            databaseName: databaseName,
            warningMessage: warningMessage,
          ),
        );
    return _summarizeDeliveryResults(results);
  }

  Future<_RecipientDeliveryResult> _sendHistoryToTarget(
    EmailConfig config,
    EmailNotificationTarget target,
    BackupHistory history,
    String? logPath,
  ) async {
    // Resolve qual canal de notificação aplica para este `BackupStatus`.
    // Antes, `BackupStatus.warning` (introduzido para WAL vazio,
    // cancelamento) caía no caminho "skipped" sem nunca disparar
    // `sendBackupWarningNotification`, mesmo com `target.notifyOnWarning`
    // habilitado — bug real.
    final eventType = _eventTypeFor(history.status);
    final shouldNotify = _shouldNotifyTarget(target, history.status);
    if (!shouldNotify) {
      final result = _RecipientDeliveryResult.skipped(
        recipientEmail: target.recipientEmail,
        reason: _disabledRuleReason(history.status),
      );
      await _saveBackupDeliveryAuditLog(
        historyId: history.id,
        configId: config.id,
        target: target,
        eventType: eventType,
        result: result,
      );
      return result;
    }

    final targetConfig = config.copyWith(recipients: [target.recipientEmail]);
    final rd.Result<bool> sendResult;
    switch (history.status) {
      case BackupStatus.success:
        sendResult = await _emailService.sendBackupSuccessNotification(
          config: targetConfig,
          history: history,
          logPath: logPath,
        );
      case BackupStatus.error:
        sendResult = await _emailService.sendBackupErrorNotification(
          config: targetConfig,
          history: history,
          logPath: logPath,
        );
      case BackupStatus.warning:
        // Constrói uma mensagem de warning baseada no errorMessage do
        // histórico (que carrega o motivo do warning, ex.: "Backup
        // finalizado sem novos dados").
        final warningMessage =
            (history.errorMessage?.isNotEmpty ?? false)
                ? history.errorMessage!
                : 'Backup concluído com aviso (sem detalhes).';
        sendResult = await _emailService.sendBackupWarningNotification(
          config: targetConfig,
          databaseName: history.databaseName,
          warningMessage: warningMessage,
          logPath: logPath,
        );
      case BackupStatus.running:
        // Não notifica para status running (não deveria chegar aqui,
        // mas defensivo). `_shouldNotifyTarget` já cobriria.
        final result = _RecipientDeliveryResult.skipped(
          recipientEmail: target.recipientEmail,
          reason: 'Status running não dispara notificação',
        );
        await _saveBackupDeliveryAuditLog(
          historyId: history.id,
          configId: config.id,
          target: target,
          eventType: eventType,
          result: result,
        );
        return result;
    }

    final result = sendResult.fold(
      (sent) => sent
          ? _RecipientDeliveryResult.sent(recipientEmail: target.recipientEmail)
          : _RecipientDeliveryResult.skipped(
              recipientEmail: target.recipientEmail,
              reason: 'Envio não realizado pelo serviço SMTP',
            ),
      (failure) => _RecipientDeliveryResult.failed(
        recipientEmail: target.recipientEmail,
        failure: _toException(failure),
      ),
    );
    await _saveBackupDeliveryAuditLog(
      historyId: history.id,
      configId: config.id,
      target: target,
      eventType: eventType,
      result: result,
    );
    return result;
  }

  static String _eventTypeFor(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return 'backup_success';
      case BackupStatus.error:
        return 'backup_error';
      case BackupStatus.warning:
        return 'backup_warning';
      case BackupStatus.running:
        return 'backup_running';
    }
  }

  static bool _shouldNotifyTarget(
    EmailNotificationTarget target,
    BackupStatus status,
  ) {
    switch (status) {
      case BackupStatus.success:
        return target.notifyOnSuccess;
      case BackupStatus.error:
        return target.notifyOnError;
      case BackupStatus.warning:
        return target.notifyOnWarning;
      case BackupStatus.running:
        return false;
    }
  }

  static String _disabledRuleReason(BackupStatus status) {
    switch (status) {
      case BackupStatus.success:
        return 'Regra de sucesso desabilitada para destinatário';
      case BackupStatus.error:
        return 'Regra de erro desabilitada para destinatário';
      case BackupStatus.warning:
        return 'Regra de aviso desabilitada para destinatário';
      case BackupStatus.running:
        return 'Status running não suporta envio';
    }
  }

  Future<_RecipientDeliveryResult> _sendWarningToTarget({
    required EmailConfig config,
    required EmailNotificationTarget target,
    required String databaseName,
    required String warningMessage,
  }) async {
    if (!target.notifyOnWarning) {
      final result = _RecipientDeliveryResult.skipped(
        recipientEmail: target.recipientEmail,
        reason: 'Regra de aviso desabilitada para destinatário',
      );
      await _saveBackupDeliveryAuditLog(
        configId: config.id,
        target: target,
        eventType: 'backup_warning',
        result: result,
      );
      return result;
    }

    final targetConfig = config.copyWith(recipients: [target.recipientEmail]);
    final sendResult = await _emailService.sendBackupWarningNotification(
      config: targetConfig,
      databaseName: databaseName,
      warningMessage: warningMessage,
    );
    final result = sendResult.fold(
      (sent) => sent
          ? _RecipientDeliveryResult.sent(recipientEmail: target.recipientEmail)
          : _RecipientDeliveryResult.skipped(
              recipientEmail: target.recipientEmail,
              reason: 'Envio não realizado pelo serviço SMTP',
            ),
      (failure) => _RecipientDeliveryResult.failed(
        recipientEmail: target.recipientEmail,
        failure: _toException(failure),
      ),
    );
    await _saveBackupDeliveryAuditLog(
      configId: config.id,
      target: target,
      eventType: 'backup_warning',
      result: result,
    );
    return result;
  }

  Future<String?> _exportLogsForBackup(String backupHistoryId) async {
    try {
      final logsResult = await _backupLogRepository.getByBackupHistory(
        backupHistoryId,
      );

      return logsResult.fold(
        (logs) async {
          if (logs.isEmpty) return null;

          final buffer = StringBuffer();
          buffer.writeln('Logs do Backup - ${DateTime.now()}');
          buffer.writeln('=' * 50);
          buffer.writeln();

          for (final log in logs) {
            buffer.writeln(
              '[${log.createdAt}] [${log.level.name.toUpperCase()}] ${log.message}',
            );
            if (log.details != null) {
              buffer.writeln('  Detalhes: ${log.details}');
            }
          }

          final tempDir = await Directory.systemTemp.createTemp('backup_logs_');
          final logFile = File('${tempDir.path}/backup_log.txt');
          await logFile.writeAsString(buffer.toString());

          return logFile.path;
        },
        (failure) => null,
      );
    } on Object catch (e) {
      LoggerService.warning('Erro ao exportar logs: $e');
      return null;
    }
  }

  Future<List<R>> _runInBatches<T, R>(
    List<T> items,
    int concurrencyLimit,
    Future<R> Function(T item) task,
  ) async {
    if (items.isEmpty) {
      return const [];
    }

    final results = <R>[];
    for (var index = 0; index < items.length; index += concurrencyLimit) {
      final batchEnd = (index + concurrencyLimit > items.length)
          ? items.length
          : index + concurrencyLimit;
      final batch = items.sublist(index, batchEnd);
      final batchResults = await Future.wait(batch.map(task));
      results.addAll(batchResults);
    }
    return results;
  }

  _DeliverySendSummary _summarizeDeliveryResults(
    List<_RecipientDeliveryResult> results,
  ) {
    var sent = 0;
    var failed = 0;
    var skipped = 0;
    Exception? firstFailure;

    for (final result in results) {
      if (result.isSent) {
        sent++;
      } else if (result.isFailed) {
        failed++;
        firstFailure ??= result.failure;
      } else {
        skipped++;
      }
    }

    return _DeliverySendSummary(
      attemptedCount: results.length,
      sentCount: sent,
      failedCount: failed,
      skippedCount: skipped,
      firstFailure: firstFailure,
    );
  }

  void _logDeliverySummary({
    required String configId,
    required String eventType,
    required _DeliverySendSummary summary,
  }) {
    LoggerService.info(
      '[NotificationService] Resumo de envio | '
      'configId=$configId '
      'event=$eventType '
      'attempted=${summary.attemptedCount} '
      'sent=${summary.sentCount} '
      'failed=${summary.failedCount} '
      'skipped=${summary.skippedCount}',
    );
  }

  Future<void> _saveBackupDeliveryAuditLog({
    required String configId,
    required EmailNotificationTarget target,
    required String eventType,
    required _RecipientDeliveryResult result,
    String? historyId,
  }) async {
    final level = result.isFailed ? LogLevel.error : LogLevel.info;
    final status = result.isSent
        ? 'success'
        : result.isFailed
        ? 'failure'
        : 'skipped';
    final message =
        'Notificação $eventType para ${target.recipientEmail}: $status';
    final detailsBuffer = StringBuffer()
      ..write('configId=$configId;')
      ..write('targetId=${target.id};')
      ..write('recipient=${target.recipientEmail};')
      ..write('event=$eventType;')
      ..write('status=$status');
    if (result.reason != null && result.reason!.trim().isNotEmpty) {
      detailsBuffer.write(';reason=${result.reason!.trim()}');
    }
    if (result.failure != null) {
      detailsBuffer.write(';error=${result.failure}');
    }

    final log = BackupLog(
      backupHistoryId: historyId,
      level: level,
      category: LogCategory.audit,
      message: message,
      details: detailsBuffer.toString(),
    );
    final createResult = await _backupLogRepository.create(log);
    createResult.fold(
      (_) {},
      (failure) {
        LoggerService.warning(
          '[NotificationService] Falha ao persistir auditoria de entrega: $failure',
        );
      },
    );
  }

  Exception _toException(Object failure) {
    if (failure is Exception) {
      return failure;
    }
    return Exception(failure.toString());
  }

  String _buildTestCorrelationId(String configId) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final normalizedId = configId.replaceAll('-', '');
    final suffix = normalizedId.length <= 8
        ? normalizedId
        : normalizedId.substring(normalizedId.length - 8);
    return '$timestamp-$suffix';
  }

  Future<void> _saveEmailTestAudit({
    required EmailConfig config,
    required String correlationId,
    required String recipientEmail,
    required String senderEmail,
    Object? failure,
  }) async {
    final normalizedCorrelationId = correlationId.trim();
    if (normalizedCorrelationId.isEmpty) {
      return;
    }

    final normalizedRecipient = recipientEmail.trim();
    if (normalizedRecipient.isEmpty && failure == null) {
      return;
    }

    final audit = EmailTestAudit(
      configId: config.id,
      correlationId: normalizedCorrelationId,
      recipientEmail: normalizedRecipient,
      senderEmail: senderEmail.trim(),
      smtpServer: config.smtpServer,
      smtpPort: config.smtpPort,
      status: failure == null ? 'success' : 'failure',
      errorType: _classifyTestFailureType(failure),
      errorMessage: failure?.toString(),
    );

    final result = await _emailTestAuditRepository.create(audit);
    result.fold(
      (_) => null,
      (saveFailure) => LoggerService.warning(
        '[NotificationService] Falha ao persistir auditoria SMTP: $saveFailure',
      ),
    );
  }

  String? _classifyTestFailureType(Object? failure) {
    if (failure == null) {
      return null;
    }

    final text = failure.toString().toLowerCase();
    if (text.contains('autenticacao') ||
        text.contains('authentication') ||
        text.contains('535')) {
      return 'authentication';
    }
    if (text.contains('timeout') ||
        text.contains('socket') ||
        text.contains('conectar')) {
      return 'connectivity';
    }
    if (text.contains('rejeitou') || text.contains('rejected')) {
      return 'smtp_rejection';
    }
    if (text.contains('invalido') ||
        text.contains('validation') ||
        text.contains('destino')) {
      return 'validation';
    }
    return 'unknown';
  }
}

class _RecipientDeliveryResult {
  const _RecipientDeliveryResult._({
    required this.recipientEmail,
    required this.state,
    this.failure,
    this.reason,
  });

  factory _RecipientDeliveryResult.sent({required String recipientEmail}) {
    return _RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      state: _RecipientDeliveryState.sent,
    );
  }

  factory _RecipientDeliveryResult.failed({
    required String recipientEmail,
    required Exception failure,
  }) {
    return _RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      failure: failure,
      state: _RecipientDeliveryState.failed,
    );
  }

  factory _RecipientDeliveryResult.skipped({
    required String recipientEmail,
    required String reason,
  }) {
    return _RecipientDeliveryResult._(
      recipientEmail: recipientEmail,
      reason: reason,
      state: _RecipientDeliveryState.skipped,
    );
  }

  final String recipientEmail;
  final Exception? failure;
  final String? reason;
  final _RecipientDeliveryState state;

  bool get isSent => state == _RecipientDeliveryState.sent;
  bool get isFailed => state == _RecipientDeliveryState.failed;
}

class _DeliverySendSummary {
  const _DeliverySendSummary({
    required this.attemptedCount,
    required this.sentCount,
    required this.failedCount,
    required this.skippedCount,
    required this.firstFailure,
  });

  final int attemptedCount;
  final int sentCount;
  final int failedCount;
  final int skippedCount;
  final Exception? firstFailure;
}

/// Resultado da tentativa de envio para uma única configuração de
/// e-mail. Encapsula os 3 caminhos possíveis (sem destinatários, sucesso
/// parcial/total, falha ao carregar destinatários) sob um único tipo
/// para que o agregador `_sendToConfigs` saiba o que somar.
class _ConfigSendOutcome {
  const _ConfigSendOutcome._({
    required this.sent,
    this.summary,
    this.failure,
  });

  factory _ConfigSendOutcome.empty() =>
      const _ConfigSendOutcome._(sent: false);

  factory _ConfigSendOutcome.failure(Object failure) =>
      _ConfigSendOutcome._(sent: false, failure: failure);

  factory _ConfigSendOutcome.fromSummary(_DeliverySendSummary summary) =>
      _ConfigSendOutcome._(
        sent: summary.sentCount > 0,
        summary: summary,
        failure: summary.firstFailure,
      );

  final bool sent;
  final _DeliverySendSummary? summary;
  final Object? failure;
}

enum _RecipientDeliveryState { sent, failed, skipped }
