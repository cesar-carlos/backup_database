import 'dart:io';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../core/errors/failure.dart';
import '../../../core/utils/logger_service.dart';
import '../../../domain/entities/email_config.dart';
import '../../../domain/entities/backup_history.dart';

class EmailService {
  Future<rd.Result<bool>> sendEmail({
    required EmailConfig config,
    required String subject,
    required String body,
    List<String>? attachmentPaths,
    bool isHtml = false,
  }) async {
    try {
      LoggerService.info('Enviando e-mail: $subject');

      final smtpServer = SmtpServer(
        config.smtpServer,
        port: config.smtpPort,
        username: config.username,
        password: config.password,
        ssl: config.useSsl,
        allowInsecure: !config.useSsl,
      );

      final message = Message()
        ..from = Address(config.fromEmail, config.fromName)
        ..recipients.addAll(config.recipients.map((e) => Address(e)))
        ..subject = subject
        ..text = isHtml ? null : body
        ..html = isHtml ? body : null;

      // Adicionar anexos
      if (attachmentPaths != null && attachmentPaths.isNotEmpty) {
        for (final path in attachmentPaths) {
          final file = File(path);
          if (await file.exists()) {
            message.attachments.add(FileAttachment(file));
          }
        }
      }

      await send(message, smtpServer);

      LoggerService.info('E-mail enviado com sucesso');
      return const rd.Success(true);
    } catch (e, stackTrace) {
      LoggerService.error('Erro ao enviar e-mail', e, stackTrace);
      return rd.Failure(ServerFailure(message: 'Erro ao enviar e-mail: $e'));
    }
  }

  Future<rd.Result<bool>> sendBackupSuccessNotification({
    required EmailConfig config,
    required BackupHistory history,
    String? logPath,
  }) async {
    if (!config.enabled || !config.notifyOnSuccess) {
      return const rd.Success(false);
    }

    final subject = '✅ Backup Concluído - ${history.databaseName}';
    final body = _buildSuccessEmailBody(history);

    return await sendEmail(
      config: config,
      subject: subject,
      body: body,
      attachmentPaths: config.attachLog && logPath != null ? [logPath] : null,
    );
  }

  Future<rd.Result<bool>> sendBackupErrorNotification({
    required EmailConfig config,
    required BackupHistory history,
    String? logPath,
  }) async {
    if (!config.enabled || !config.notifyOnError) {
      return const rd.Success(false);
    }

    final subject = '❌ Erro no Backup - ${history.databaseName}';
    final body = _buildErrorEmailBody(history);

    return await sendEmail(
      config: config,
      subject: subject,
      body: body,
      attachmentPaths: config.attachLog && logPath != null ? [logPath] : null,
    );
  }

  Future<rd.Result<bool>> sendBackupWarningNotification({
    required EmailConfig config,
    required String databaseName,
    required String warningMessage,
    String? logPath,
  }) async {
    if (!config.enabled || !config.notifyOnWarning) {
      return const rd.Success(false);
    }

    final subject = '⚠️ Aviso de Backup - $databaseName';
    final body = '''
Aviso durante o backup!

Base de Dados: $databaseName
Aviso: $warningMessage
Data/Hora: ${DateTime.now()}

Este é um e-mail automático do Sistema de Backup.
''';

    return await sendEmail(
      config: config,
      subject: subject,
      body: body,
      attachmentPaths: config.attachLog && logPath != null ? [logPath] : null,
    );
  }

  String _buildSuccessEmailBody(BackupHistory history) {
    final duration = history.durationSeconds != null
        ? '${history.durationSeconds} segundos'
        : 'N/A';
    final size = _formatFileSize(history.fileSize);

    return '''
Backup realizado com sucesso!

Base de Dados: ${history.databaseName}
Tipo: ${history.databaseType}
Arquivo: ${history.backupPath}
Tamanho: $size
Início: ${history.startedAt}
Término: ${history.finishedAt ?? 'N/A'}
Duração: $duration

Este é um e-mail automático do Sistema de Backup.
''';
  }

  String _buildErrorEmailBody(BackupHistory history) {
    return '''
Erro ao realizar backup!

Base de Dados: ${history.databaseName}
Tipo: ${history.databaseType}
Erro: ${history.errorMessage ?? 'Erro desconhecido'}
Data/Hora: ${history.startedAt}

Por favor, verifique os logs para mais detalhes.

Este é um e-mail automático do Sistema de Backup.
''';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

