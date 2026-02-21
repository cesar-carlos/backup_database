import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_email_service.dart';
import 'package:backup_database/domain/services/i_oauth_smtp_service.dart';
import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';
import 'package:result_dart/result_dart.dart' as rd;

typedef SmtpSendFn =
    Future<SendReport> Function(
      Message message,
      SmtpServer smtpServer, {
      Duration? timeout,
    });

typedef RetryDelayFn = Future<void> Function(Duration duration);

class EmailService implements IEmailService {
  EmailService({
    required IOAuthSmtpService oauthSmtpService,
    SmtpSendFn? smtpSendFn,
    RetryDelayFn? retryDelayFn,
  }) : _oauthSmtpService = oauthSmtpService,
       _smtpSendFn = smtpSendFn ?? send,
       _retryDelayFn = retryDelayFn ?? Future.delayed;

  static final Random _random = Random();
  final SmtpSendFn _smtpSendFn;
  final RetryDelayFn _retryDelayFn;
  final IOAuthSmtpService _oauthSmtpService;

  static int get _maxSendAttempts => AppConstants.smtpMaxSendAttempts;
  static Duration get _smtpSendTimeout => AppConstants.smtpSendTimeout;
  static int get _baseRetryDelayMs => AppConstants.smtpBaseRetryDelayMs;
  static int get _maxRetryDelayMs => AppConstants.smtpMaxRetryDelayMs;

  @override
  Future<rd.Result<bool>> sendEmail({
    required EmailConfig config,
    required String subject,
    required String body,
    List<String>? attachmentPaths,
    bool isHtml = false,
  }) async {
    final recipients = config.recipients
        .map((email) => email.trim())
        .where((email) => email.isNotEmpty)
        .toList(growable: false);
    if (recipients.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Nenhum destinatario informado para envio de e-mail',
        ),
      );
    }

    final senderEmail = config.fromEmail.trim();
    if (senderEmail.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'E-mail remetente nao informado na configuracao SMTP',
        ),
      );
    }

    LoggerService.info(
      '[EmailService] Iniciando envio SMTP | '
      'configId=${config.id} '
      'server=${config.smtpServer}:${config.smtpPort} '
      'ssl=${config.useSsl} '
      'allowInsecure=${AppConstants.allowInsecureSmtp} '
      'from=${_maskEmail(senderEmail)} '
      'to=${_maskEmails(recipients)} '
      'subject="$subject" '
      'timeoutMs=${_smtpSendTimeout.inMilliseconds} '
      'maxAttempts=$_maxSendAttempts',
    );

    if (AppConstants.allowInsecureSmtp) {
      LoggerService.warning(
        '[EmailService] Modo inseguro SMTP habilitado via ALLOW_INSECURE_SMTP. '
        'Use apenas em ambientes controlados.',
      );
    }

    final smtpServerResult = await _buildSmtpServer(config);
    if (smtpServerResult.isError()) {
      return rd.Failure(smtpServerResult.exceptionOrNull()!);
    }
    final smtpServer = smtpServerResult.getOrElse((_) => throw StateError(''));

    final message = Message()
      ..from = Address(senderEmail, config.fromName)
      ..recipients.addAll(recipients.map(Address.new))
      ..subject = subject
      ..text = isHtml ? null : body
      ..html = isHtml ? body : null;

    if (attachmentPaths != null && attachmentPaths.isNotEmpty) {
      for (final path in attachmentPaths) {
        final file = File(path);
        if (await file.exists()) {
          message.attachments.add(FileAttachment(file));
        }
      }
    }

    for (var attempt = 1; attempt <= _maxSendAttempts; attempt++) {
      try {
        final report = await _smtpSendFn(
          message,
          smtpServer,
          timeout: _smtpSendTimeout,
        );

        LoggerService.info(
          '[EmailService] Mensagem aceita pelo servidor SMTP | '
          'configId=${config.id} '
          'attempt=$attempt/$_maxSendAttempts '
          'opened=${report.connectionOpened} '
          'sendStart=${report.messageSendingStart} '
          'sendEnd=${report.messageSendingEnd} '
          'to=${_maskEmails(recipients)} '
          'subject="$subject"',
        );
        return const rd.Success(true);
      } on Object catch (e, stackTrace) {
        final isTransient = _isTransientFailure(e);
        final isLastAttempt = attempt >= _maxSendAttempts;
        if (!isTransient || isLastAttempt) {
          return _mapSendErrorToFailure(
            configId: config.id,
            error: e,
            stackTrace: stackTrace,
            smtpServerHost: config.smtpServer,
            smtpServerPort: config.smtpPort,
            attempts: attempt,
          );
        }

        final delay = _calculateRetryDelay(attempt);
        LoggerService.warning(
          '[EmailService] Falha SMTP transiente; nova tentativa agendada | '
          'configId=${config.id} '
          'attempt=$attempt/$_maxSendAttempts '
          'retryInMs=${delay.inMilliseconds} '
          'erro=${_sanitizeErrorText(e.toString())}',
          _sanitizeErrorText(e.toString()),
          stackTrace,
        );
        await _retryDelayFn(delay);
      }
    }

    return const rd.Failure(
      ServerFailure(message: 'Falha SMTP apos 3 tentativas'),
    );
  }

  @override
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

    return sendEmail(
      config: config,
      subject: subject,
      body: body,
      attachmentPaths: config.attachLog && logPath != null ? [logPath] : null,
    );
  }

  @override
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

    return sendEmail(
      config: config,
      subject: subject,
      body: body,
      attachmentPaths: config.attachLog && logPath != null ? [logPath] : null,
    );
  }

  @override
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
    final body =
        '''
Aviso durante o backup!

Base de Dados: $databaseName
Aviso: $warningMessage
Data/Hora: ${DateTime.now()}

Este é um e-mail automático do Sistema de Backup.
''';

    return sendEmail(
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

  bool _isTransientFailure(Object error) {
    if (error is SocketException || error is TimeoutException) {
      return true;
    }
    if (error is SmtpClientCommunicationException) {
      final statusCode = _extractSmtpStatusCode(error.toString());
      return statusCode != null && statusCode >= 400 && statusCode < 500;
    }
    return false;
  }

  int? _extractSmtpStatusCode(String message) {
    final match = RegExp(r'\b([1-5][0-9]{2})\b').firstMatch(message);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  Duration _calculateRetryDelay(int attempt) {
    final expFactor = 1 << (attempt - 1);
    var delayMs = _baseRetryDelayMs * expFactor;
    if (delayMs > _maxRetryDelayMs) {
      delayMs = _maxRetryDelayMs;
    }
    final jitterMs = _random.nextInt(200);
    return Duration(milliseconds: delayMs + jitterMs);
  }

  rd.Result<bool> _mapSendErrorToFailure({
    required String configId,
    required Object error,
    required StackTrace stackTrace,
    required String smtpServerHost,
    required int smtpServerPort,
    required int attempts,
  }) {
    if (error is SmtpClientAuthenticationException) {
      LoggerService.error(
        'Erro de autenticacao SMTP (configId=$configId attempts=$attempts)',
        error,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(
          message:
              'Falha de autenticacao SMTP. Verifique usuario, senha e porta/SSL. Detalhe: ${_sanitizeErrorText(error.toString())}',
        ),
      );
    }

    if (error is SmtpClientCommunicationException) {
      LoggerService.error(
        'Servidor SMTP rejeitou a mensagem (configId=$configId attempts=$attempts)',
        error,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(
          message:
              'Servidor SMTP rejeitou a mensagem. Verifique remetente/destinatario e politicas do servidor. Detalhe: ${_sanitizeErrorText(error.toString())}',
        ),
      );
    }

    if (error is SmtpMessageValidationException) {
      LoggerService.error('Mensagem SMTP invalida (configId=$configId)', error, stackTrace);
      return rd.Failure(
        ValidationFailure(
          message:
              'Mensagem de e-mail invalida. Detalhe: ${_sanitizeErrorText(error.toString())}',
        ),
      );
    }

    if (error is SocketException || error is TimeoutException) {
      LoggerService.error(
        'Falha de conexao SMTP (configId=$configId attempts=$attempts)',
        error,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(
          message:
              'Nao foi possivel conectar ao servidor SMTP ($smtpServerHost:$smtpServerPort). Detalhe: ${_sanitizeErrorText(error.toString())}',
        ),
      );
    }

    if (error is MailerException) {
      LoggerService.error(
        'Falha SMTP ao enviar e-mail (configId=$configId attempts=$attempts)',
        error,
        stackTrace,
      );
      return rd.Failure(
        ServerFailure(
          message:
              'Falha SMTP ao enviar e-mail: ${_sanitizeErrorText(error.toString())}',
        ),
      );
    }

    LoggerService.error(
      'Erro ao enviar e-mail (configId=$configId attempts=$attempts)',
      error,
      stackTrace,
    );
    return rd.Failure(
      ServerFailure(
        message:
            'Erro ao enviar e-mail: ${_sanitizeErrorText(error.toString())}',
      ),
    );
  }

  String _maskEmail(String email) {
    final value = email.trim();
    final at = value.indexOf('@');
    if (at <= 1) {
      return value;
    }

    final local = value.substring(0, at);
    final domain = value.substring(at + 1);
    final first = local[0];
    return '$first***@$domain';
  }

  String _maskEmails(List<String> emails) {
    return emails.map(_maskEmail).join(', ');
  }

  String _sanitizeErrorText(String text) {
    return text.replaceAll(
      RegExp(
        r'(password|passwd|pwd|token|secret)\s*[:=]\s*([^\s,;]+)',
        caseSensitive: false,
      ),
      r'$1=<redacted>',
    );
  }

  Future<rd.Result<SmtpServer>> _buildSmtpServer(EmailConfig config) async {
    if (!config.authMode.isOAuth) {
      return rd.Success(
        AppConstants.allowInsecureSmtp
            ? SmtpServer(
                config.smtpServer,
                port: config.smtpPort,
                username: config.username,
                password: config.password,
                ssl: config.useSsl,
                allowInsecure: true,
              )
            : SmtpServer(
                config.smtpServer,
                port: config.smtpPort,
                username: config.username,
                password: config.password,
                ssl: config.useSsl,
              ),
      );
    }

    final provider = config.oauthProvider;
    if (provider == null) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Provedor OAuth SMTP nao configurado para esta conta',
        ),
      );
    }

    final tokenKey = config.oauthTokenKey?.trim() ?? '';
    if (tokenKey.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Conexao OAuth SMTP nao configurada para esta conta',
        ),
      );
    }

    final tokenResult = await _oauthSmtpService.resolveValidAccessToken(
      provider: provider,
      tokenKey: tokenKey,
    );
    if (tokenResult.isError()) {
      return rd.Failure(tokenResult.exceptionOrNull()!);
    }

    final accessToken = tokenResult.getOrElse((_) => '');
    final username = _resolveOAuthUserEmail(config);
    if (username.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message: 'Usuario OAuth SMTP invalido para autenticacao XOAUTH2',
        ),
      );
    }

    final xoauth2Token = _buildXoauth2Token(
      userEmail: username,
      accessToken: accessToken,
    );

    return rd.Success(
      AppConstants.allowInsecureSmtp
          ? SmtpServer(
              config.smtpServer,
              port: config.smtpPort,
              ssl: config.useSsl,
              allowInsecure: true,
              xoauth2Token: xoauth2Token,
            )
          : SmtpServer(
              config.smtpServer,
              port: config.smtpPort,
              ssl: config.useSsl,
              xoauth2Token: xoauth2Token,
            ),
    );
  }

  String _resolveOAuthUserEmail(EmailConfig config) {
    final preferred = config.username.trim();
    if (preferred.isNotEmpty && preferred.contains('@')) {
      return preferred;
    }

    final account = config.oauthAccountEmail?.trim() ?? '';
    if (account.isNotEmpty && account.contains('@')) {
      return account;
    }

    final from = config.fromEmail.trim();
    if (from.isNotEmpty && from.contains('@')) {
      return from;
    }

    return '';
  }

  String _buildXoauth2Token({
    required String userEmail,
    required String accessToken,
  }) {
    final raw = 'user=$userEmail\u0001auth=Bearer $accessToken\u0001\u0001';
    return base64.encode(utf8.encode(raw));
  }
}
