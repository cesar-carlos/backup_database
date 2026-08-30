import 'package:backup_database/application/services/notification/notification_audit_writer.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class EmailConfigurationTester {
  EmailConfigurationTester({
    required this._emailService,
    required this._auditWriter,
  });

  final IEmailService _emailService;
  final NotificationAuditWriter _auditWriter;

  Future<rd.Result<bool>> test(EmailConfig config) async {
    final correlationId = buildTestCorrelationId(config.id);
    final destinationRecipient = config.recipients
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .firstOrNull;
    if (destinationRecipient == null || !destinationRecipient.contains('@')) {
      const failure = ValidationFailure(
        message:
            'Informe um e-mail de destino válido para testar a configuração',
      );
      await _auditWriter.saveEmailTestAudit(
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
      await _auditWriter.saveEmailTestAudit(
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

    if (sendResult.isSuccess()) {
      LoggerService.info(
        '[NotificationService] Teste SMTP aceito | '
        'correlationId=$correlationId '
        'to=$destinationRecipient',
      );
      await _auditWriter.saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: destinationRecipient,
        senderEmail: senderEmail,
      );
    } else {
      final Object? failure = sendResult.exceptionOrNull();
      LoggerService.warning(
        '[NotificationService] Teste SMTP falhou | '
        'correlationId=$correlationId '
        'to=$destinationRecipient '
        'erro=$failure',
      );
      await _auditWriter.saveEmailTestAudit(
        config: config,
        correlationId: correlationId,
        recipientEmail: destinationRecipient,
        senderEmail: senderEmail,
        failure: failure,
      );
    }

    return sendResult;
  }

  static String buildTestCorrelationId(String configId) {
    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final normalizedId = configId.replaceAll('-', '');
    final suffix = normalizedId.length <= 8
        ? normalizedId
        : normalizedId.substring(normalizedId.length - 8);
    return '$timestamp-$suffix';
  }
}
